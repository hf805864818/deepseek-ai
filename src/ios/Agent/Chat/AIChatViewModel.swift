//
//  AIChatViewModel.swift
//  Minis - chat view model (Agent/Chat)
//
//  AIChatViewModel - one chat session's view model: messages, the agent loop
//  that talks to the model and runs tools, and the state the chat UI binds to.
//
//  Map of the AIChatViewModel files (all in Agent/Chat/)
//  ====================================================
//
//    AIChatViewModel.swift      this file: every stored property (@Published
//        state, loop / queue / speech / sync state, signals), init / deinit,
//        and a few small computed properties that read like state
//    Turn flow
//        +Send            send(), retry(), resume(), unanswered user turn
//        +AgentLoop       runAgentLoop / runAgentLoopCore (request, stream,
//                         tools, repeat)
//        +Rerun           retry from a message / tool block, delete from here
//        +EditMessage     edit a sent message, cut at a user bubble
//        +Cancel          Stop, cancel work bound to a previous model
//        +PromptQueue     queued prompts: drain, inject as a new turn
//        +TurnCompletion  haptic, failure banner, stop / cancel cleanup
//        +SSEStream, +ConcurrentTools, +ToolDefinitions, +ToolPreflight,
//        +RequestBudget, +Fallback, +ProviderFactory, +ProgrammaticPrompt,
//        +UserAsk, +Offloading, +Compaction   (older extension files)
//    Prompt and context
//        +SystemPrompt    base system prompt, fixed token cost
//        +ContextUsage    usage glow / hint, model capability queries
//        +ThinkingLevel   session thinking level
//    UI plumbing
//        +StreamingUI     streaming / transition gates, streamed text writes
//        +Speech          TTS output;  +AutoPlayAudio  audio auto-play, MIME
//        +Attachments, +MentionMenu, +SlashCommands   (older extension files)
//    Session and lifecycle
//        +Lifecycle       cache eviction teardown, font cache invalidation
//        +Persistence, +TitleGeneration, +BackgroundTask, +Misc   (older)
//    Tools
//        +FileTools, +MemoryTools, +ISHCommand   (older extension files)
//    Diagnostics
//        +DebugDumps      agentHistory / queue log dumps
//    LLMProviderError.swift  the provider error enum that ended this file
//
//  Rules that keep this split working
//  ==================================
//
//  - Stored properties stay in this class body (extensions cannot hold them);
//    their order is the order they had before the split.
//  - Each extension file declares its own file-private `logger` (category
//    "AIChatVM"), like the older extension files.
//  - Members used from another file are internal; treat them as private to
//    the view model.
//  - New behaviour goes into the extension file of its concern (or a new one).
//  - Source-scanning tests (MinisTests/Standalone) read this file together with
//    the files split out of it (chatViewModelSource() lists them), so code may
//    move between those files; a new file split out of this one belongs on
//    that list too.
//
//  History: +Lifecycle, +ContextUsage, +StreamingUI, +Speech, +AutoPlayAudio,
//  +SystemPrompt, +Send, +Rerun, +EditMessage, +Cancel, +PromptQueue,
//  +DebugDumps, +TurnCompletion, +AgentLoop, +ThinkingLevel and
//  LLMProviderError.swift were split out of this file (~8.5k lines before).
//  The code was moved verbatim; the differences are the repeated import list,
//  per-file logger copies, dropped `private` / `fileprivate`, the extension
//  wrappers and one doc comment put back on its function (see
//  AIChatViewModel+TurnCompletion.swift).
//

import AVFoundation
import Combine
import CryptoKit
import Foundation
import ImageIO
import SQLite3
import UIKit
import os.log

private let logger = AppLogger(category: "AIChatVM")

// MARK: - View Model

@MainActor
final class AIChatViewModel: ObservableObject, SpeechControlling {

    /// Maximum characters returned in a single tool result to the model
    static let kMaxToolResultChars = 15000

    /// Maximum number of images retained in agent history when building the
    /// context sent to the model. Older images are replaced with a text
    /// placeholder (containing dimensions + byte size + persisted path) so
    /// they can be re-viewed via the `read_image` tool.
    static let kImageContextKeepCount = 20

    // MARK: - Image byte budgets (T-imgsize-13b7d81c, T-image-budget-base64)
    //
    // [T-image-budget-base64] These budgets are measured in BASE64 bytes —
    // the size the image actually occupies in the request body — not in raw
    // decoded bytes.
    //
    // The original comment here reasoned that Anthropic's 30 MB limit applies
    // to decoded image bytes, so budgeting in raw bytes was equivalent. That
    // is true of Anthropic's own per-image content rule, but it is NOT the
    // constraint that was actually breaking requests: gateways in front of
    // several providers (OpenAI and Anthropic both observed) enforce a 32 MB
    // limit on the HTTP REQUEST BODY, and images travel that body base64
    // encoded, which inflates them by 4/3. A 25 MB raw budget therefore put
    // ~33.3 MB on the wire before a single byte of text history or tool
    // schema — over the cap on its own, which is exactly the
    // "request too large (~32 MB, limit 32 MB)" failure users hit.
    //
    // Budgeting in base64 bytes makes the number mean what it says: the
    // ceiling is what we are about to send. Raw-byte sizes are converted
    // with `estimatedBase64Length` at every comparison instead of the
    // constants being scaled down, so there is no rounding drift and the
    // headroom below stays exact rather than approximate.
    //
    // Other providers have similar but undocumented caps. We enforce a
    // tighter, pre-encoding budget so the request never reaches the wire
    // too big:
    //
    //   - Per image: 5 MB after JPEG re-encode. The Anthropic SDK's own
    //     per-image soft hint; well under the 30 MB request cap and
    //     ensures a single huge photo can't gobble the whole budget.
    //     Anything bigger runs the compressor ladder (smaller max edge +
    //     lower JPEG quality) until it fits or until we've shrunk it
    //     past readability.
    //   - Per message: 25 MB cumulative across all inlined images.
    //     Leaves ~5 MB headroom under Anthropic's 30 MB request cap for
    //     other parts of the payload (tool results, prior message
    //     attachments echoed back, etc.).
    //   - Above the message cap, additional images are dropped to a text
    //     placeholder (same fallback the count cap already uses).

    /// [T-image-budget-base64] Bytes `rawBytes` will occupy once base64
    /// encoded into the request body: 4 output bytes per 3 input bytes,
    /// rounded up to the next 4-byte group (which is what padding produces).
    ///
    /// Exact for the encoding itself, so no fudge factor is needed. It
    /// deliberately does NOT model the JSON string overhead around the
    /// payload (quotes, the `data:` prefix, escaping) — those are tens of
    /// bytes against megabytes, and the budgets already reserve headroom for
    /// the rest of the body.
    ///
    /// Computed rather than measured: base64-encoding every candidate image
    /// just to learn its length would cost a full copy of each image's bytes
    /// on every request-budget pass, for a number this returns exactly.
    ///
    /// Mirrors Android's `ImageBudget.estimatedBase64Length`.
    static func estimatedBase64Length(_ rawBytes: Int) -> Int {
        guard rawBytes > 0 else { return 0 }
        return ((rawBytes + 2) / 3) * 4
    }

    /// [T-image-budget-base64] Inverse of `estimatedBase64Length`: the largest
    /// raw byte count that still encodes within `base64Budget`.
    ///
    /// Needed because the compressor ladder (`compressedImageDataUnderBudget`)
    /// measures its output in RAW bytes — it is comparing `data.count` against
    /// the target it was handed. Feeding it a base64 budget directly would
    /// silently let it stop compressing at 5 MB raw, i.e. ~6.7 MB on the wire,
    /// which is the very overshoot this change removes. So budgets cross that
    /// boundary through here.
    ///
    /// Mirrors Android's `ImageBudget.rawBytesForBase64Budget`.
    static func rawBytesForBase64Budget(_ base64Budget: Int) -> Int {
        guard base64Budget > 0 else { return 0 }
        return (base64Budget / 4) * 3
    }

    /// Hard ceiling per single image after compression, measured in BASE64
    /// bytes (see `estimatedBase64Length`). 5 MB of wire payload is ~3.75 MB
    /// of decoded image, still comfortably above what the compressor ladder
    /// targets for a readable photo.
    static let kPerImageMaxBytes = 5 * 1024 * 1024

    /// Hard ceiling across all inlined images in one user message.
    /// 5 MB under Anthropic's 30 MB request cap, leaving headroom for
    /// tool results and prior-turn attachments still in context.
    static let kMessageImageMaxBytes = 25 * 1024 * 1024

    /// Hard ceiling on cumulative inline-image bytes across the FULL
    /// request body (all messages, all tool results). When a long
    /// session accumulates browser screenshots + attachments + read_image
    /// results past this cap, gpt-5.5 via factory.pub silently returns
    /// 200 + empty SSE + `finish_reason=stop` and the client treats the
    /// empty turn as completion (T-request-imgsize). Eldest images are
    /// elided to text placeholders here.
    static let kRequestImageMaxBytes = 25 * 1024 * 1024

    /// Hard ceiling on agent loop iterations within a single user turn.
    /// Backstop against runaway tool-call cycles that slip past
    /// `ToolLoopDetector` (e.g. visited args/results vary just enough to
    /// dodge the global circuit breaker). On reaching the limit the loop
    /// finalizes as resumable — see runAgentLoop's tail — so the user gets
    /// an inline explanation + Resume affordance rather than an unbounded
    /// runaway. Mirrors Android ChatViewModel.MAX_AGENT_TURNS.
    static let maxAgentTurns = 200
    /// [T-chat-auto-compact-inloop] Max in-loop auto-compactions per single
    /// user turn. Beyond this the loop stops as exhausted rather than
    /// compacting endlessly (which would defeat the maxAgentTurns backstop).
    static let maxInLoopCompactions = 3

    /// [StreamDiag] (#181) Monotonic counter tagging each outbound streaming
    /// request so the stall watchdog's log line can be correlated with the
    /// request it belongs to. Main-actor isolated (the whole class is), so the
    /// `&+=` bump needs no additional synchronization. Diagnostics only —
    /// nothing reads this for control flow.
    static var diagRequestSeq: UInt64 = 0

    /// If non-nil, this VM is in read-only mode viewing a remote device's session.
    var remoteDeviceId: String?

    /// Short unique ID for this ViewModel instance (for debugging lifecycle).
    let vmInstanceId = UUID().uuidString.prefix(6)

    /// [T-deferred-sync-reload] Set to true when a
    /// `.cloudSyncDidFetchChanges` notification fires WHILE
    /// `isProcessing == true`. The `$isProcessing` sink drains it on
    /// the false-edge by replaying exactly one `reloadMessagesFromDB`
    /// so the user sees the post-send DB state without waiting for the
    /// next 60s sync timer.
    var pendingSyncReloadOnIdle = false

    // MARK: - Post-stop sync hold (T-ios-defer-icloud-sync-after-stop)

    /// While the agent loop runs (`isProcessing`), and for a grace window AFTER
    /// it stops, BOTH iCloud directions are held: no push to cloud, no pull-
    /// driven local reload. This stops a deferred sync from overwriting the
    /// just-finished candidate the instant the loop ends (field repro: content
    /// vanished + a brief loading flash right after Stop). The hold is released
    /// — and a single catch-up sync (flush dirty push + replay reload) runs —
    /// when the earliest of these happens: the 60s timer fires, the user leaves
    /// the session (back to the list), or the app is backgrounded.
    static let postStopSyncHoldSeconds: TimeInterval = 60
    /// Deadline of the current hold; nil when not held.
    private(set) var postStopSyncHoldUntil: Date?
    private var postStopSyncHoldTimer: Timer?

    /// True while the post-stop grace window is active.
    var isSyncHeld: Bool {
        guard let until = postStopSyncHoldUntil else { return false }
        return until > Date()
    }

    /// Enter the post-stop hold for the PULL side only, and release the push
    /// immediately. Called when the agent loop transitions to idle.
    ///
    /// [T-icloud-sync-tier1-push-on-idle] This used to also call
    /// `SyncCore.pause(for: 60)`, holding every outbound record for a full
    /// minute after the loop ended. That pause never protected anything:
    /// the on-screen overwrite it was added for (c74a3a313, 2026-06-01) is
    /// caused by a PULL-driven reload replacing in-memory content, which the
    /// `isSyncHeld` guard in `reloadMessagesFromDB` and the cancel guard from
    /// ebe9cb844 already prevent — and our own pushed records come back as
    /// `ownEcho` and never trigger a reload. Measured cost of the pause on
    /// two devices: 60 of the 96–160 s it took a finished turn to appear on
    /// the peer. `persistAgentMessage` is awaited before `isProcessing`
    /// flips, so on every normal completion the records are already durable
    /// here; on cancel the kept partial is memory-only and is never marked
    /// dirty until it persists, so nothing unpersisted can be pushed either.
    ///
    /// So: end this vm's send deferral and flush NOW (the store still holds
    /// the send back if another loop is running), and keep only the pull
    /// hold — `postStopSyncHoldUntil` + the timer — so a peer change that
    /// arrived mid-turn is merged at the hold's release, not the instant the
    /// candidate lands.
    @MainActor
    private func beginPostStopSyncHold() {
        let until = Date().addingTimeInterval(Self.postStopSyncHoldSeconds)
        postStopSyncHoldUntil = until
        postStopSyncHoldTimer?.invalidate()
        postStopSyncHoldTimer = Timer.scheduledTimer(withTimeInterval: Self.postStopSyncHoldSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.releasePostStopSyncHold(reason: "timer-60s") }
        }
        let owner = String(vmInstanceId)
        Task {
            await ChatStore.shared.endSyncSendDeferral(owner: owner)
            await ChatStore.shared.flushPendingSyncDirty()
        }
        logger.info("[SyncHold] BEGIN pull-hold until \(until) (\(Int(Self.postStopSyncHoldSeconds))s), push released now sid=\(self.sessionId?.prefix(8) ?? "nil")")
    }

    /// Release the hold early/at-deadline and run one catch-up sync: resume
    /// SyncCore, flush deferred dirty (push), and replay any pending reload
    /// (pull). Idempotent — safe to call from any of the release triggers.
    @MainActor
    func releasePostStopSyncHold(reason: String) {
        guard postStopSyncHoldUntil != nil else { return }
        postStopSyncHoldUntil = nil
        postStopSyncHoldTimer?.invalidate()
        postStopSyncHoldTimer = nil
        // [T-p0-sync-defer-refcount] Another session's loop may still be
        // streaming. Its own hold/release will resume + flush when IT finishes
        // (SyncCore.pause is deadline-bounded, so skipping resume here can't
        // strand it). Only release this vm's deferral and let the store decide
        // whether anything is still holding the send back.
        let owner = String(vmInstanceId)
        let othersActive = SessionActivityTracker.shared.activeSessions.contains { $0 != self.sessionId }
        logger.info("[SyncHold] RELEASE reason=\(reason) sid=\(self.sessionId?.prefix(8) ?? "nil") othersActive=\(othersActive) — \(othersActive ? "deferring catch-up to the running session" : "resuming sync + catch-up")")
        // [T-icloud-sync-tier1-push-on-idle] Push was already released and
        // flushed in beginPostStopSyncHold; SyncCore was never paused, so
        // there is nothing to resume. `endSyncSendDeferral` is set-based and
        // idempotent — call it again only as a belt-and-braces for the
        // paths that reach here without having gone through begin (deinit,
        // background). It does not re-flush.
        _ = othersActive
        Task { await ChatStore.shared.endSyncSendDeferral(owner: owner) }
        // Pull: replay a deferred reload now that it's safe.
        if pendingSyncReloadOnIdle, !isProcessing, sessionId != nil {
            pendingSyncReloadOnIdle = false
            Task { @MainActor in await self.reloadMessagesFromDB(reason: "syncHoldReleased(\(reason))") }
        }
    }

    /// Cancellable for tracking `isProcessing` → `SessionActivityTracker`.
    private var activityTrackingCancellable: AnyCancellable?
    private var captureSuppressCancellable: AnyCancellable?
    private var mediaPreemptCancellable: AnyCancellable?
    private var voiceStateCancellable: AnyCancellable?
    /// Observer for font-size changes to invalidate cached attributed strings.
    private var fontChangeObserver: Any?
    /// Observer for iCloud sync changes to reload messages.
    private var syncChangeObserver: Any?
    /// Observer for group binding changes to update in-memory context limit.
    /// Observer that releases the post-stop sync hold when the app backgrounds.
    private var backgroundSyncHoldObserver: Any?
    /// [T-tool-bg-suspended-hint] Observer firing on foreground return; stamps
    /// still-running browser tool blocks that have spanned a background period
    /// and exceeded the long-run threshold so the chat capsule can hint at the
    /// likely background slowdown. In-memory only (not persisted).
    private var bgHintForegroundObserver: Any?
    private var snapshotForegroundObserver: Any?
    private var detachedLoopEndObserver: Any?
    /// [T-ios-switch-model-ghost-retry] Observes `.sessionModelBindingChanged`
    /// so a mid-conversation model switch tears down work aimed at the model
    /// being switched away from. The notification was already being posted by
    /// `SessionModelPicker`; until this, nothing listened to it.
    private var modelBindingChangeObserver: Any?
    /// [T-ios-switch-model-next-request] Set when the user picks a different
    /// model while a HEALTHY turn is in flight. The running agent loop checks
    /// it at the top of each iteration — i.e. before its next LLM request —
    /// and swaps to the newly bound model there, so the switch takes effect
    /// without interrupting the stream or tool call already under way.
    var pendingModelSwitch = false
    /// Timestamp of the most recent background-entry, used to detect that a
    /// long-running browser task actually spanned a background period.
    var bgHintBackgroundEntryDate: Date?
    /// A browser tool running longer than this when the app returns to the
    /// foreground (after having been backgrounded) gets the suspension hint.
    static let bgHintBrowserThreshold: TimeInterval = 5 * 60

    init() {
        logger.info("🔄SESSION [vm=\(self.vmInstanceId)] init — new AIChatViewModel created")

        fontChangeObserver = NotificationCenter.default.addObserver(
            forName: .fontSettingsMessageBaseChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.invalidateAttributedStringCaches() }
        }

        // [T-ios-defer-icloud-sync-after-stop] Backgrounding is a release
        // trigger for the post-stop sync hold — let the held catch-up sync run
        // before the app suspends, instead of waiting out the 60s window.
        backgroundSyncHoldObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // [T-tool-bg-suspended-hint] Remember when we went to background so
            // a foreground return can tell a browser task actually spanned it.
            self.bgHintBackgroundEntryDate = Date()
            Task { @MainActor in self.releasePostStopSyncHold(reason: "background") }
        }

        // [T-tool-bg-suspended-hint] On foreground return, flag any still-running
        // browser tool that spanned the background period and has now exceeded the
        // long-run threshold — the WebView/JS is likely throttled or stalled while
        // backgrounded, so the capsule surfaces the "enable enhanced background"
        // hint. In-memory only; mirrors the BackgroundInterruptionTracker gate
        // (skip when enhanced background is already effective).
        bgHintForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.markLongBackgroundBrowserTasks() }
        }

        // [T-ios-bg-blocks-lost] On foreground return, replay the deferred
        // snapshot rebuild if isProcessing went false while backgrounded.
        // When the app is in background with streamingUIUpdatesSuspended=false,
        // bind4b may call applySnapshot but UIKit can silently drop or
        // incompletely apply UICollectionView diffs while not in .active.
        // The isProcessing didSet sets needsSnapshotReloadOnResume=true for
        // this case, but clearStreamingUIUpdatesSuspended won't fire (the
        // flag was never set). This observer is the missing trigger.
        // [T-ios-bg-blocks-lost] Replay the deferred snapshot rebuild when the
        // app returns to .active. Uses didBecomeActiveNotification (not
        // willEnterForegroundNotification) because the deferred path triggers
        // for BOTH .background and .inactive states — inactive→active is
        // common (e.g. Control Center swipe, notification shade pull) and
        // willEnterForeground only fires from background, missing the
        // inactive case entirely.
        snapshotForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // [T-blockslost-defensive defect ②] Gate on being the
                // CURRENTLY-DISPLAYED session. This observer was written
                // (02970b7b) when the flag could only mean suspended /
                // backgrounded — cases where foreground-return implies this
                // VM's view is mounted. b5f6a1e1 later added the
                // "no subscriber" deferral (user viewing ANOTHER session):
                // for that case a foreground-return must NOT consume the
                // flag — the replay signal would fire with no CollectionView
                // subscriber bound and be lost, starving
                // consumeDeferredSnapshotIfNeeded (the in-app switch-back
                // path) of the flag it exists to consume.
                let sid = self.sessionId
                let gatePassed = (sid != nil && Self.activeSessionId == sid)
                let needsFlag = self.needsSnapshotReloadOnResume
                logger.info("[BlocksLost] didBecomeActive gate sid=\(sid?.prefix(8) ?? "nil") vm=\(self.vmInstanceId) activeSessionId=\(Self.activeSessionId?.prefix(8) ?? "nil") gatePassed=\(gatePassed) needsFlag=\(needsFlag)")
                guard needsFlag else { return }
                guard gatePassed else {
                    // Keep the flag: the user is on another session; the
                    // onAppear-reuse path consumes it when they switch back.
                    return
                }
                self.needsSnapshotReloadOnResume = false
                let totalBlocks = self.messages.reduce(0) { $0 + $1.blocks.count }
                let lastBlocks = self.messages.last?.blocks.count ?? 0
                logger.info("[BlocksLost] REPLAY retrySnapshot — app became active. sid=\(sid?.prefix(8) ?? "nil") totalBlocks=\(totalBlocks) lastMsgBlocks=\(lastBlocks) msgCount=\(self.messages.count)")
                self.retrySnapshotReloadSignal.send()
            }
        }

        // [T-ios-detached-vm-loop-end] When the agent loop finishes on a
        // detached VM (user navigated away mid-loop, or VM was evicted and
        // recreated), that VM posts .sessionAgentLoopDidEnd. The currently-
        // displayed VM for the same session picks it up here and reloads
        // from DB so the final tool results / assistant text appear.
        detachedLoopEndObserver = NotificationCenter.default.addObserver(
            forName: .sessionAgentLoopDidEnd, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let sid = self.sessionId else { return }
            guard let notifSid = notification.object as? String, notifSid == sid else { return }
            guard Self.activeSessionId == sid else { return }
            guard !self.isProcessing else { return }
            logger.info("[BlocksLost] DETACHED reload — agent loop ended on another VM, reloading. sid=\(sid.prefix(8)) vm=\(self.vmInstanceId)")
            Task { @MainActor in
                await self.reloadMessagesFromDB(reason: "detachedVMLoopEnd")
            }
        }

        // [T-ios-switch-model-ghost-retry] A model switch must stop whatever is
        // still aimed at the model being switched away from. `SessionModelPicker`
        // has always posted this; nothing observed it, so the old model's agent
        // loop kept retrying and its errors kept surfacing over the new model's
        // working replies.
        modelBindingChangeObserver = NotificationCenter.default.addObserver(
            forName: .sessionModelBindingChanged, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let sid = self.sessionId else { return }
            // Only THIS conversation's switch. The notification is global and
            // carries its session id, so a switch in another chat (or from a
            // background/scheduled binding write) must not cancel this one.
            guard let notifSid = notification.userInfo?["sessionId"] as? String,
                  notifSid == sid else { return }
            Task { @MainActor in
                self.cancelWorkBoundToPreviousModel(reason: "user switched model")
            }
        }

        syncChangeObserver = NotificationCenter.default.addObserver(
            forName: .cloudSyncDidFetchChanges, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let sid = self.sessionId else { return }
            // Only the foreground-visible VM reacts. ViewModelCache holds
            // every session the user has ever opened in this launch, and
            // each instance is a notification subscriber — without this
            // gate, one inbound batch fans out into N concurrent
            // reloadMessagesFromDB calls, each of which loadMessages-es
            // its session (potentially thousands of rows + JSON decode).
            // The hidden VMs catch up on their own via the
            // AIChatView.onAppear REUSING branch, which already does the
            // same hash+count comparison before reloading.
            if Self.activeSessionId != sid { return }
            // [T-deferred-sync-reload] If a send is in flight, don't
            // reload mid-stream — that would re-snapshot messages and
            // could clobber the streaming assistant block / hide the
            // "Minis is thinking" indicator. Flip a flag instead; the
            // $isProcessing observer below picks it up and replays one
            // reload as soon as the send completes. This avoids waiting
            // the full sync-timer cycle (~60s) for the next refresh.
            if self.isProcessing {
                self.pendingSyncReloadOnIdle = true
                logger.info("[ReloadTrace] DEFER reason=cloudSyncDidFetchChanges sid=\(sid.prefix(8)) isProcessing=true — will reload on idle")
                return
            }
            // [T-scroll-sync-defer] A reload mid-fling either costs frames (hash
            // check) or re-snapshots the list under the user's finger; run it
            // once the list is still.
            // Re-check the gates above when it finally runs: a send may have
            // started, or the user may have left, in the meantime.
            ChatScrollActivity.runWhenStill("chat.syncReload.\(sid)") { [weak self] in
                guard let self, self.sessionId == sid, Self.activeSessionId == sid else { return }
                if self.isProcessing {
                    self.pendingSyncReloadOnIdle = true
                    return
                }
                Task { @MainActor in
                    await self.reloadMessagesFromDB(reason: "cloudSyncDidFetchChanges")
                }
            }
        }

        activityTrackingCancellable = $isProcessing
            .removeDuplicates()
            .sink { [weak self] processing in
                guard let self else { return }
                // Key selection:
                //   - Before the draft has a real session (sessionId == nil),
                //     fall back to draftId so the sidebar proxy row still
                //     reflects activity.
                //   - Once sessionId exists, use ONLY it; mixing in draftId
                //     caused leaks — ensureSession migrates draft→real but
                //     draftId stays set for sidebar UX, and a second send()
                //     would setActive(draftId) again while the first send's
                //     setInactive(sessionId) wasn't reliably paired.
                let activeKey: String
                if let sid = self.sessionId {
                    activeKey = sid
                } else if let did = self.draftId {
                    activeKey = did
                } else {
                    return
                }
                let src = "vm=\(self.vmInstanceId) isProcessing=\(processing)"
                logger.info("🔄SESSION [vm=\(self.vmInstanceId)] isProcessing=\(processing) key=\(activeKey) draftId=\(self.draftId ?? "nil") sessionId=\(self.sessionId ?? "nil")")
                if processing {
                    SessionActivityTracker.shared.setActive(activeKey, source: src)
                    if let sid = self.sessionId {
                        Task {
                            if let session = await ChatStore.shared.getSession(sid),
                               let title = session.title, !title.isEmpty {
                                await MainActor.run {
                                    SessionActivityTracker.shared.updateSessionTitle(sid, title: title)
                                }
                            }
                        }
                    }
                    // [T-ios-session-running-shows-pause-badge] Starting/resuming
                    // a loop means this session is no longer paused — drop any
                    // stale ⏸ immediately, independent of the canResume didSet
                    // (which only fires on a value transition and can miss a queue
                    // entry seeded by the launch reconcile or a prior VM).
                    if let sid = self.sessionId {
                        SessionBadgeStore.shared.remove(.paused, for: sid)
                    }
                    // [T-ios-ipad-sidebar-spinner-stale-after-resend] Re-assert
                    // the draft→real alias on every activation. On iPad the
                    // sidebar keeps showing the new chat's row under its DRAFT
                    // id (ContentView.displaySessions builds a proxy with
                    // id=draftId so List(selection:) stays valid), and that row
                    // reads `isActive(draftId)`. The alias was registered once at
                    // draft→real migration, but `setInactive(real)` CLEARS it
                    // (it drops aliases pointing at a now-inactive session). So
                    // after the first stop the alias is gone; a resend calls
                    // setActive(real) but the sidebar proxy — still keyed by
                    // draftId — no longer resolves, and its spinner never spins
                    // again until the user navigates away (which collapses the
                    // proxy to the real id). Re-registering the alias here on
                    // each true-transition keeps the draft-keyed row in sync.
                    if let did = self.draftId, did != activeKey, self.sessionId != nil {
                        SessionActivityTracker.shared.setDraftAlias(draft: did, real: activeKey)
                    }
                } else {
                    SessionActivityTracker.shared.setInactive(activeKey, source: src)
                    // [T-ios-session-completed-badge-not-cleared] The loop just
                    // stopped. If it didn't stop in a resumable state, the session
                    // completed normally — clear any ⏸ that lingers. The canResume
                    // didSet handles the true→false transition, but a turn that
                    // finished with canResume ALREADY false (the common completion
                    // path: line ~4044 sets false even when it was false → no
                    // didSet) leaves a stale badge (seeded by reconcile / a prior
                    // VM) untouched. Gating on !canResume preserves a genuine
                    // interruption (Stop / bg-suspend) that ends the loop with
                    // canResume=true — that badge must stay.
                    if !self.canResume, let sid = self.sessionId {
                        SessionBadgeStore.shared.remove(.paused, for: sid)
                    }
                    // Safety net: if the draft id ever ended up in the tracker
                    // (e.g. from a prior send() that started before ensureSession
                    // returned), scrub it on this transition too so it can't
                    // orphan.
                    if let did = self.draftId, did != activeKey {
                        SessionActivityTracker.shared.setInactive(did, source: src + " (stray draftId)")
                    }
                    self.browserTabPool.releaseAllTabs()
                    // [T-deferred-sync-reload] Drain any sync reloads that
                    // arrived during the send so the UI catches up with the DB
                    // now that the stream finished.
                    // [T-ios-defer-icloud-sync-after-stop] BUT not while the
                    // post-stop hold is active — replaying a reload here is the
                    // exact overwrite we're preventing. Keep the flag armed; the
                    // hold release (timer / leave / background) replays it.
                    if self.pendingSyncReloadOnIdle, let sid = self.sessionId {
                        if self.isSyncHeld {
                            logger.info("[ReloadTrace] HOLD reason=isProcessing→false sid=\(sid.prefix(8)) — deferred reload kept until post-stop hold releases")
                        } else {
                            self.pendingSyncReloadOnIdle = false
                            logger.info("[ReloadTrace] DRAIN reason=isProcessing→false sid=\(sid.prefix(8)) — replaying deferred sync reload")
                            Task { @MainActor in
                                await self.reloadMessagesFromDB(reason: "deferredSyncReloadOnIdle")
                            }
                        }
                    }
                }
            }

        // When the mic starts capturing, immediately silence any in-progress
        // reply TTS (capture and playback are mutually exclusive — no echo). New
        // speech is already suppressed by `canSpeakNow`; this stops the current
        // System utterance too (the cloud queue is stopped by the panel).
        captureSuppressCancellable = VoiceModePreference.shared.$isCapturing
            .removeDuplicates()
            .sink { [weak self] capturing in
                if capturing { self?.stopSpeech() }
            }

        // A media attachment preempted reply TTS — stop the System synthesizer
        // (cloud queue already stopped by the coordinator). Don't auto-resume.
        mediaPreemptCancellable = NotificationCenter.default
            .publisher(for: AudioSessionCoordinator.replyTTSPreemptedNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.speechSynthesizer.isSpeaking {
                    self.speechSynthesizer.stopSpeaking(at: .immediate)
                }
                self.isReadingAloud = false
                self.speechPaused = false
            }

        // Read-replies is now GLOBAL state (VoiceOutputState.shared). Forward its
        // changes so views observing `vm.speakEnabled` refresh, and stop this VM's
        // System TTS the moment it's turned off anywhere.
        voiceStateCancellable = VoiceOutputState.shared.$isEnabled
            .dropFirst()                 // skip the synchronous current-value emit
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                self.objectWillChange.send()
                if !enabled { self.stopSpeech() }
            }
    }

    deinit {
        let vmId = vmInstanceId
        // Snapshot tracker-relevant state at deinit so we can spot leaks: if
        // isProcessing was still true when the vm is about to die, the
        // corresponding sessionId/draftId keys will remain stuck in
        // `SessionActivityTracker.activeSessions` because the `$isProcessing`
        // sink won't fire once self is gone. Fields are MainActor-isolated
        // and deinit is nonisolated; `_deinitSnapshot` is updated on the
        // main actor during normal flow so we can read it here safely.
        logger.info("🔄SESSION [vm=\(vmId)] deinit lastKnown: \(self._deinitSnapshot)")
        // [T-p0-sync-defer-refcount] A vm evicted mid-hold never reaches
        // releasePostStopSyncHold (the timer holds self weakly); drop its
        // deferral so it cannot pin iCloud sends off forever.
        let owner = String(vmId)
        Task { await ChatStore.shared.endSyncSendDeferral(owner: owner) }
        if let observer = fontChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = syncChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = backgroundSyncHoldObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = bgHintForegroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = snapshotForegroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = detachedLoopEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = modelBindingChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Published State

    @Published var messages: [ChatMessage] = []
    /// [T-in-chat-search] "Search in Chat" for this conversation. Not
    /// @Published: the search bar and the highlighted rows observe it
    /// directly, so typing a query never re-renders the whole chat page.
    lazy var chatSearch: ChatSearchController = {
        let search = ChatSearchController()
        search.viewModel = self
        return search
    }()
    /// [T-voice-input-mode-preference-ios] True when a voice session
    /// contributed to the CURRENT composition (set on recording start by any
    /// path: mic tap, quick action, preference auto-entry). Cleared whenever
    /// the composer empties, so send() can detect "composed without voice
    /// since the composer was last cleared" and flip the remembered
    /// input-mode preference back to "text".
    var voiceUsedInComposition = false
    @Published var inputText = "" {
        didSet {
            if inputText.isEmpty && !oldValue.isEmpty {
                voiceUsedInComposition = false
                #if DEBUG
                logger.info("🔑DRAFT [vm=\(self.vmInstanceId)] inputText CLEARED (was '\(String(oldValue.prefix(30)))') sessionId=\(self.sessionId ?? "nil") draftId=\(self.draftId ?? "nil") isProcessing=\(self.isProcessing)")
                #else
                logger.info("🔑DRAFT [vm=\(self.vmInstanceId)] inputText CLEARED (was \(oldValue.count)ch) sessionId=\(self.sessionId ?? "nil") draftId=\(self.draftId ?? "nil") isProcessing=\(self.isProcessing)")
                #endif
            }
            updateSlashMenuState()
            updateMentionMenuState()
        }
    }
    /// Caret position (character offset) published by the input text view.
    /// Used by the `@` mention detector to locate the active token.
    @Published var inputCaret: Int = 0 {
        didSet {
            updateMentionMenuState()
            // If the caret arrived at the desired location, clear the pending
            // request so subsequent edits aren't forced back.
            if let p = pendingCaret, p == inputCaret {
                pendingCaret = nil
            }
        }
    }
    /// One-shot request to move the caret to a specific offset. Cleared once
    /// the text view publishes a matching caret position via `inputCaret`.
    @Published var pendingCaret: Int?
    /// Plain string capture of the vm state for diagnostic logging from deinit
    /// (which is nonisolated and can't touch @Published MainActor properties).
    /// Updated on every isProcessing flip and on send entry.
    nonisolated(unsafe) var _deinitSnapshot: String = "isProcessing=false session=nil draft=nil"

    // [T-ios-context-usage-hint] Context-window occupancy, published so the
    // composer can render the ambient glow live and the placeholder line
    // once per finished turn. Recomputed by publishContextUsage() whenever
    // a message's usage lands or a session loads; nil when no assistant turn
    // has reported usage yet (some providers never do — the feature then
    // stays hidden instead of showing 0%).
    @Published var contextUsage: ContextUsage?
    /// One request per finished user-visible turn; the composer's Coordinator
    /// acts on each generation exactly once (debounced there).
    @Published var contextUsageHint: ContextUsageHint?
    var contextUsageHintGeneration = 0
    /// [T-ctx-usage-after-compact] The message whose stamped usage was taken
    /// BEFORE the latest compaction in this session. Its `latestContextTokens`
    /// is the size of the context the compaction replaced, so while it is
    /// still the newest usage-bearing message, `publishContextUsage()` shows
    /// the measured post-compaction size instead. Cleared implicitly: the next
    /// turn stamps usage on a newer message, which no longer matches.
    var usageReportSupersededByCompaction: UUID?
    /// [T-ios-context-usage-realtime-crossing] Shared by the mid-loop crossing
    /// path and the loop-end path so the two never announce the same tier
    /// twice within seconds. Internal (not private) so the session-load
    /// extension can reset it.
    var contextTierTracker = ContextTierCrossingTracker()

    /// [T-ctx-measure-outbound] Calibration state for `ContextSizeMeter`.
    ///
    /// Replaces `liveContextTokensForCapacity`, a mirror of the newest API
    /// report that the capacity guard folded in with `max()`. That number
    /// described the previous request and nothing but another successful call
    /// could replace it, so after a compaction it kept the guard above the line
    /// and the loop re-compacted until it gave up (see ContextSizeMeter).
    ///
    /// `contextCalibrationRatios` — provider count / our estimate, taken from the
    ///   same request, PER MODEL: a ratio mostly reflects the provider's
    ///   tokenizer, so one learned on model A does not describe model B after a
    ///   switch. `lastLearnedCalibration` is the newest ratio of any model; a
    ///   model with none of its own borrows it with a margin (see
    ///   ContextSizeMeter.ratio(for:)).
    /// `contextFixedTokens` — estimated system prompt + tool schemas, refreshed
    ///   every loop iteration; seeded from the last stamped turn on load so the
    ///   send-time check has it before any loop has run.
    /// `lastDispatchEstimate` — estimate of the request currently in flight,
    ///   paired with its report when usage arrives.
    var contextCalibrationRatios: [String: Double] = [:]
    var lastLearnedCalibration: Double? = nil
    /// The session the in-memory ratios were learned for (see seedContextCalibration).
    var calibrationSessionId: String? = nil
    /// [T-ctx-warmup-fit] Per compaction marker: how many leading warm-up
    /// messages were dropped to fit. Decided once, then reused, so the request
    /// prefix stays stable across turns (see trimWarmUpToFit).
    var warmUpDropByMarker: [String: Int] = [:]
    var contextFixedTokens = 0
    /// [T-ctx-count-reasoning] Whether the provider serving this session sends
    /// past `reasoningContent` back (AgentProvider.echoesReasoningContent). Set
    /// by the agent loop from the live provider; the send-time check, which
    /// runs before a provider exists, reads the value of the previous request.
    var contextEchoesReasoning = false
    /// [T-ctx-trim-ladder] The live provider's default output cap, for the
    /// output reserve of the watermarks. Set by the agent loop like the flag
    /// above; 16K until a provider has been seen.
    var contextProviderMaxOutput = 16_384
    /// [T-ctx-trim-ladder] The frozen trim plan: cut-off keys re-applied to
    /// every measurement and request until the next re-plan, so the request
    /// prefix (and the provider's prompt cache) stays stable. In memory only.
    /// It belongs to one session and one compaction marker; a change of either
    /// drops it (see applyFrozenTrim).
    var trimState: ContextTrimPlanner.State?
    var trimStateSessionId: String?
    var trimStateMarkerId: String?
    /// [T-ctx-trim-plan-window] The window the plan was sized for.
    var trimStateWindow: Int?
    /// Set when the next check must re-plan even below the trigger (after a
    /// compaction, or when the frozen plan stopped matching the history).
    var trimReplanPending = false
    /// [T-ctx-trim-collapse-first] Set once a re-plan was allowed to collapse;
    /// later re-plans for the same session and marker keep allowing it (see
    /// ContextTrimPlanner.CollapseUnlock).
    var trimCollapseUnlock: ContextTrimPlanner.CollapseUnlock?
    /// [T-ctx-trim-escalate] True when the re-plan just made could not
    /// collapse and recovered too little (ContextTrimPlanner.shouldEscalate).
    var lastTrimPlanEscalates = false
    /// Disk paths of what the ladder already offloaded, so re-applying a plan
    /// writes nothing.
    var trimOffloadPaths: [String: String] = [:]
    var lastDispatchEstimate = 0
    /// [T-ctx-overflow-attribute-dispatch] Model id and window of the request
    /// in flight, so a rejection is attributed to the model that received it.
    var lastDispatchModelId: String?
    var lastDispatchWindow = 0
    /// The ratio and calibrated size used for the request in flight, so its
    /// response can be scored against the prediction ([CtxMeter] actual).
    var lastDispatchRatio: Double = 1.0
    var lastDispatchPredicted = 0
    /// Whether an uncalibrated send past an extrapolated "over the window"
    /// verdict has already been spent (see the in-loop guard). One per piece
    /// of provider evidence: an accepted response re-arms it, a rejection
    /// spends it, and it survives Retry.
    var sentPastExtrapolatedLimitThisLoop = false

    @Published var isProcessing = false {
        didSet {
            _deinitSnapshot = "isProcessing=\(isProcessing) session=\(sessionId ?? "nil") draft=\(draftId ?? "nil")"
            if isProcessing && !oldValue {
                // Agent loop starting — defer iCloud sync sends until completion.
                // [T-p0-sync-defer-refcount] Owner-keyed: two sessions can run
                // loops concurrently (ViewModelCache + SessionConcurrencyManager),
                // and a plain bool let the first loop to finish un-defer sync
                // under the one still streaming. The deferral for this vm is
                // released in releasePostStopSyncHold (or deinit).
                let owner = String(vmInstanceId)
                Task { await ChatStore.shared.beginSyncSendDeferral(owner: owner) }
                // [T-ios-defer-icloud-sync-after-stop] A new turn supersedes any
                // pending post-stop hold; clear it WITHOUT a catch-up sync (the
                // new turn re-pauses sync via setSyncSendDeferred anyway).
                if postStopSyncHoldUntil != nil {
                    postStopSyncHoldUntil = nil
                    postStopSyncHoldTimer?.invalidate()
                    postStopSyncHoldTimer = nil
                    logger.info("[SyncHold] CLEAR — new turn started, superseding post-stop hold")
                }
                // Begin watching for main-thread hangs while streaming is
                // active. Captures a backtrace whenever the main runloop
                // doesn't drain for >1s, plus a snapshot of streamed text
                // around the stall, so we can confirm whether the 0x8BADF00D
                // watchdog lands inside _fillLayoutHole, SwiftUI Layout, or
                // elsewhere — and correlate with the content being rendered.
                StreamingHangLogger.shared.acquire(reason: "isProcessing=true session=\(sessionId ?? "nil")")
            } else if !isProcessing && oldValue {
                // [T-ios-defer-icloud-sync-after-stop] Agent loop finished. Do
                // NOT flush the deferred iCloud push or replay a pull reload now
                // — that immediate sync is what overwrote the just-finished
                // candidate. Instead enter the post-stop hold: both directions
                // stay paused for the grace window, then a single catch-up sync
                // runs on release (60s timer / leave session / background).
                beginPostStopSyncHold()
                StreamingHangLogger.shared.release(reason: "isProcessing=false session=\(sessionId ?? "nil")")
                // [T-p0-programmatic-prompt] A silent (programmatic) turn ends
                // here whether it completed or was cancelled; never let the
                // flag leak into the user's next manual send.
                // [T-subagent-callback-no-keyboard] Hand the fact forward first:
                // this didSet runs before SwiftUI's onChange, so the auto-focus
                // observer would otherwise see an already-cleared flag and pop
                // the keyboard on a sub agent's callback.
                turnWasSilentProgrammatic = programmaticSilentTurn
                programmaticSilentTurn = false
                programmaticTurnOrigin = nil  // [T-user-ask]
                // [T-ios-context-usage-hint] Offer the usage line for this
                // turn. Only for a turn the user started and let finish:
                // a cancelled turn's usage is whatever call happened to be
                // in flight, and a silent sub-agent callback is not the
                // user's turn at all. The composer must also be empty —
                // the label is hidden behind typed text anyway, so the
                // request would just expire unseen. The Coordinator adds
                // its own debounce on top so a burst of quick turns shows
                // the line once, for the last of them.
                publishContextUsage()
                // [T-ios-context-usage-realtime-crossing] Keep the shared tier
                // record in step with the final usage (a cancelled or
                // queued-turn path may have landed usage the mid-loop observer
                // never saw), and skip the line when the mid-loop path already
                // announced this very tier moments ago — the label would just
                // repaint the same text and the voice panel would re-show it.
                let loopEndNow = Date()
                if let tier = contextUsage?.tier { _ = contextTierTracker.observe(tier, now: loopEndNow) }
                if !userDidCancel, !turnWasSilentProgrammatic, inputText.isEmpty,
                   let usage = contextUsage {
                    if contextTierTracker.recentlyFired(for: usage.tier, now: loopEndNow) {
                        logger.info("[ContextUsageHint] loop-end → dedup: mid-loop crossing hint for \(usage.tier) fired <\(Int(ContextTierCrossingTracker.minInterval))s ago (\(usage.usedTokens)/\(usage.windowTokens))")
                    } else {
                        contextUsageHintGeneration += 1
                        contextUsageHint = ContextUsageHint.make(usage: usage, generation: contextUsageHintGeneration,
                                                              quota: composerQuotaPart())
                        contextTierTracker.markFired(usage.tier, now: loopEndNow)
                        logger.info("[ContextUsageHint] loop-end → hint gen\(contextUsageHintGeneration) '\(contextUsageHint?.text ?? "")' (\(usage.usedTokens)/\(usage.windowTokens))")
                    }
                } else {
                    logger.info("[ContextUsageHint] loop-end → NO hint: cancel=\(userDidCancel) silent=\(turnWasSilentProgrammatic) inputEmpty=\(inputText.isEmpty) usage=\(contextUsage.map { "\($0.usedTokens)/\($0.windowTokens)" } ?? "nil")")
                }
                // [T-p0-programmatic-prompt] Rescue drain. Every drain runs in
                // some loop's epilogue BEFORE that loop flips isProcessing to
                // false, so a prompt enqueued in the await-gap between the
                // epilogue's drain and this flip has no consumer — it would sit
                // in promptQueue until the user's next turn. Start one now.
                // cancel() owns its own resume (resumeQueueAfterCancel) and
                // sets userDidCancel first, so it is excluded here.
                if !promptQueue.isEmpty && !userDidCancel {
                    startDrainIfIdle(reason: "loop-ended-with-queued-prompts")
                }
                // [T-ios-ui-frozen-on-tool-while-loop-runs] Force one snapshot
                // re-apply from the CURRENT in-memory messages at loop end.
                //
                // Why this is needed: during a multi-turn agent loop, tool blocks
                // are appended to the EXISTING last-assistant ChatMessage. The
                // messages ARRAY doesn't change, so the Coordinator's `$messages`
                // sink never re-fires and the per-message block-count subscription
                // can miss the appends — the new tool capsules are in the data
                // model but never get cells. The loop-end full reload that should
                // rebuild them goes through `reloadMessagesFromDB`, which is held
                // by the post-stop SyncHold and then SKIP-LOADs (`hashSame=true`,
                // because the DB baseline already advanced as the loop persisted),
                // so it never repaints. Result: the UI froze on the last-rendered
                // capsule for minutes while many turns ran un-rendered.
                //
                // `retrySnapshotReloadSignal` already does exactly the right thing
                // — re-applies the diffable snapshot from `vm.messages` even when
                // the array identity is unchanged (its original use: in-place
                // block mutation on retry). It is a pure UI re-render from memory:
                // it does NOT touch the DB / reload / SyncHold, so it can't
                // overwrite unpersisted content. Idempotent (the snapshot diff is
                // a no-op when nothing changed).
                //
                // CRITICAL guard — only fire when FOREGROUND and not UI-suspended:
                // the Coordinator's applySnapshot does a synchronous
                // `layoutIfNeeded()` (cell creation + self-sizing) on the main
                // thread. For a large history that is heavy work; running it while
                // backgrounded risks the 0x8BADF00D background-render watchdog
                // SIGKILL that `streamingUIUpdatesSuspended` exists to prevent. If
                // the loop ends while suspended/backgrounded, the Coordinator
                // already has `hasPendingSnapshot=true` and the suspend-resume hook
                // (T-ios-ui-blocks-lost-suspend-resume) flushes it on the next
                // foreground transition — so we must NOT force-apply here. We only
                // cover the foreground case (the actual freeze: block-count sub
                // missed in-place appends with NO suspend involved). Also gated on
                // `!transitionSuspended` so a session-switch outgoing VM doesn't
                // poke a tearing-down view graph (same guard as the manual
                // objectWillChange.send sites).
                // [T-blockslost-defensive defect ③] The flag ASSIGNMENT is no
                // longer wrapped in the `!transitionSuspended` gate: setting
                // `needsSnapshotReloadOnResume` touches no view, so the gate —
                // which exists to keep view-graph pokes out of the 0.4s
                // session-switch animation window — was pure collateral here.
                // A loop that ended inside that window previously left NO flag
                // behind, so nothing ever replayed for it. The gate still
                // protects the only view-touching action (the immediate
                // signal send below), whose conditions are unchanged.
                let inTransitionWindow = transitionSuspended
                if !inTransitionWindow,
                   !streamingUIUpdatesSuspended,
                   UIApplication.shared.applicationState == .active,
                   let sid = sessionId, Self.activeSessionId == sid {
                    retrySnapshotReloadSignal.send()
                } else {
                    needsSnapshotReloadOnResume = true
                    let totalBlocks = messages.reduce(0) { $0 + $1.blocks.count }
                    let lastBlocks = messages.last?.blocks.count ?? 0
                    let reason: String
                    if streamingUIUpdatesSuspended {
                        reason = "suspended"
                    } else if UIApplication.shared.applicationState != .active {
                        reason = "backgrounded"
                    } else if let sid = sessionId, Self.activeSessionId != sid {
                        reason = "no subscriber (active=\(Self.activeSessionId?.prefix(8) ?? "nil"))"
                    } else {
                        reason = "transition window"
                    }
                    logger.info("[BlocksLost] DEFERRED retrySnapshot — \(reason) at loop end. sid=\(sessionId?.prefix(8) ?? "nil") vm=\(vmInstanceId) transitionWindow=\(inTransitionWindow) totalBlocks=\(totalBlocks) lastMsgBlocks=\(lastBlocks) msgCount=\(messages.count)")
                }
                // [T-ios-detached-vm-loop-end] When an agent loop finishes on
                // a VM that is NOT the currently-displayed one (user navigated
                // away mid-loop), the final DB writes are invisible to the
                // displayed VM. Post a notification so the active VM for this
                // session reloads from DB and picks up the new data.
                if let sid = sessionId, Self.activeSessionId != sid {
                    logger.info("[BlocksLost] DETACHED loop end — posting reload for sid=\(sid.prefix(8)) (active=\(Self.activeSessionId?.prefix(8) ?? "nil"))")
                    NotificationCenter.default.post(name: .sessionAgentLoopDidEnd, object: sid)
                }
                // Also drain any skill-filesystem rescan that the AI's
                // shell tools may have queued during this turn. We hold
                // the rescan off the hot path so it runs once at quiet
                // time, not interleaved with every iSH write event.
                if #available(iOS 17.0, *) {
                    SkillFilesystemNotifier.shared.drainIfDirty(reason: "agent turn finished")
                }
            }
        }
    }
    /// [T-ios-group-pause-badge-restamp] Set only while a load / pre-warm is
    /// flipping `canResume` because the persisted tail STILL looks interrupted —
    /// i.e. the session was already paused and we are re-deriving that fact, not
    /// observing a new interruption. The `canResume` didSet reads this to decide
    /// whether the badge's entry timestamp may be overwritten. Not `@Published`:
    /// it is a transient annotation on the assignment, never UI state.
    /// Internal (not `private`) because the detecting site lives in the
    /// `+Persistence` extension, i.e. a different file.
    var isRedetectingInterruptedTail = false

    @Published var canResume = false {
        didSet {
            // [T-session-paused-badge-active-false-positive] Drive the session-
            // list PAUSED badge directly off canResume — the authoritative "this
            // session is interrupted (tap Resume)" flag and the single chokepoint
            // over every canResume setter. true → badge on; false (resumed / new
            // turn / completed) → badge off. Replaces the prior push at the
            // background-interruption point + clear-on-open, so a session merely
            // glanced at keeps its badge and a running/resolved session never
            // shows one. (Mirrors the Android canResume collector.)
            if oldValue != canResume, let sid = sessionId {
                if canResume {
                    // [T-ios-group-pause-badge-restamp] Only a REAL interruption
                    // re-stamps the badge's entry time. This didSet is the single
                    // chokepoint over every canResume setter, so it also fires
                    // when a load/pre-warm merely RE-DETECTS an old interrupted
                    // tail — that is not a new entry into the paused state, and
                    // re-stamping it there is what let a days-old pause keep
                    // looking "fresh" to the group card's 24h window forever.
                    // The detecting site sets `isRedetectingInterruptedTail`
                    // around its assignment; everything else is a live event.
                    SessionBadgeStore.shared.pushFront(
                        .paused, for: sid,
                        restamp: !isRedetectingInterruptedTail,
                        source: isRedetectingInterruptedTail ? .redetect : .push)
                } else {
                    SessionBadgeStore.shared.remove(.paused, for: sid)
                }
            }
            // [T-ios-cancel-reload-overwrite] reloadMessagesFromDB defers a
            // sync reload while `canResume` is true and the in-memory candidate
            // holds unpersisted interrupted content (so the reload can't
            // overwrite it). Once the interrupted state clears (Resume finished
            // / a normal turn completed and persisted everything), replay the
            // deferred reload so iCloud-synced changes finally land.
            if oldValue && !canResume && pendingSyncReloadOnIdle, let sid = sessionId {
                // [T-ios-retry-usermsg-vanish] Don't replay the deferred reload
                // if canResume is being cleared as the FIRST step of a retry
                // truncation — the reload would race the in-flight
                // messages/DB truncation and can drop the retried user message
                // from the UI. Leave pendingSyncReloadOnIdle armed; the retry's
                // own completion (isProcessing→false) drains it safely.
                if isTruncatingForRetry {
                    logger.info("[ReloadTrace] SKIP reason=canResume→false sid=\(sid.prefix(8)) — retry truncation in progress; deferred reload stays armed")
                } else {
                    pendingSyncReloadOnIdle = false
                    logger.info("[ReloadTrace] DRAIN reason=canResume→false sid=\(sid.prefix(8)) — replaying deferred sync reload after interrupted state cleared")
                    Task { @MainActor [weak self] in
                        await self?.reloadMessagesFromDB(reason: "deferredAfterResumeCleared")
                    }
                }
            }
        }
    }
    @Published var isSuspended = false
    /// [T-ios-streamdiag-phantom-model] LEGACY FALLBACK DEFAULT — never
    /// written anywhere; permanently holds `.claudeHaiku45`. The real model
    /// selection flows through `activeEntryId` → `ProviderConfigStore`
    /// (see runAgentLoop). The only legitimate reads are `?? selectedModel`
    /// last-resort fallbacks when entry resolution fails (documented in
    /// +ToolDefinitions). NEVER log or display this as "the current model":
    /// the SSE stall diagnostics did exactly that, and a stall investigation
    /// was nearly pinned on claude-haiku-4-5 — a model the session never used.
    @Published var selectedModel: LLMModel = .claudeHaiku45
    @Published var isLoadingSession = false
    /// False until the FIRST loadSession() for this vm completes. Lets the view
    /// distinguish "entering the session, nothing rendered yet" (show the soft
    /// centered loading card) from every later reload — iCloud sync, compaction,
    /// stale-cache refresh — which must keep the unobtrusive spinner and never
    /// cover content the user is already reading. Not @Published on purpose: it
    /// only ever changes alongside isLoadingSession, whose publish already
    /// re-evaluates the view.
    var hasCompletedInitialLoad = false
    @Published var errorMessage: String?

    /// [T-ios-retry-keyboard] Marks the in-flight turn as one the user started
    /// by tapping Retry / Resume on an EXISTING failed message, rather than by
    /// sending something new.
    ///
    /// The auto-focus-after-reply observer keys off the `isProcessing` true→false
    /// edge, and a retry produces exactly that edge — so re-running an old
    /// failure looked identical to "a reply just finished" and popped the
    /// keyboard. That is wrong for a retry specifically: the user's gesture was
    /// "send this again", not "let me type", and the composer rising covers the
    /// error they are trying to read.
    ///
    /// Deliberately NOT "suppress focus whenever a turn fails": auto-focus at
    /// the moment a fresh send fails is existing, wanted behaviour. The
    /// distinction being drawn is the ORIGIN of the turn, not its outcome.
    ///
    /// Not @Published — the observer reads it synchronously inside the
    /// isProcessing handler, and publishing it would re-render the whole chat
    /// on every retry for no visual reason.
    var turnStartedByRetry = false

    /// [T-longctx-persona-reminder-cachebreak] Context size at which the
    /// long-context persona reminder was last appended to `agentHistory`, or
    /// nil when this session has not been reminded yet.
    ///
    /// Drives the re-arm interval in `personaReminderIsDue(contextTokens:)`.
    /// Intentionally NOT persisted: on a fresh launch it starts nil and
    /// `personaReminderAlreadyInHistory()` recovers the state from history
    /// itself, which is self-healing and survives reload / iCloud restore
    /// without adding a schema column.
    var lastPersonaReminderContextTokens: Int?

    /// [T-subagent-callback-no-keyboard] True when the turn that just ended was
    /// started programmatically and silently — a sub agent's progress report or
    /// completion callback arriving via `submitProgrammaticPrompt(silent:)`.
    ///
    /// `programmaticSilentTurn` cannot serve here: it is cleared inside
    /// `isProcessing`'s own `didSet`, which runs BEFORE SwiftUI delivers the
    /// `onChange`, so the view would always read false. This flag is set from
    /// the same place and read (and consumed) by the auto-focus observer.
    ///
    /// Why it matters: the observer treats every `isProcessing → false` edge as
    /// "a reply arrived, ready the composer". A background sub agent reporting
    /// in drives a full parent turn, so each progress callback raised the
    /// keyboard while the user was reading — a focus change they never asked
    /// for. Same reasoning as `turnStartedByRetry`: the ORIGIN of the turn
    /// decides, not its outcome.
    ///
    /// Not @Published — read synchronously in the isProcessing handler.
    var turnWasSilentProgrammatic = false
    /// Transient banner for one-off notices the user should see (e.g. a
    /// resumed sub agent whose definition is gone, HelperRunner). UI clears it
    /// after a short display window. Not for automatic per-request handling:
    /// the request-level image budget notice that used to be set here was
    /// silenced to a log line ([T-silence-auto-notices]).
    @Published var transientNotice: String?

    @Published var autoRetryAttempt: Int = 0
    @Published var autoRetryCountdown: Int = 0
    /// [T-ios-empty-after-toolresult-reminder] Guards the one-shot
    /// `<system-reminder>` retry when the server returns an empty response
    /// right after a tool result. Set the first time we inject the reminder in
    /// a given agent loop; if the reminder round is ALSO empty we report an
    /// error instead of injecting again — so it can never loop. Reset at the
    /// start of each agent loop (a fresh user turn).
    var didInjectEmptyToolReminderThisRun = false
    /// Incremented when a model fallback occurs so the UI can animate the model name change.
    @Published var fallbackTrigger: Int = 0
    /// Signal to trigger scroll-to-bottom in views (not @Published to avoid full view diff).
    let scrollToBottomSignal = PassthroughSubject<Void, Never>()
    /// Fired when the view model wants the composer to grab keyboard focus
    /// (e.g. after a `/skill` tap fills the input — the user expects to
    /// immediately type their question without an extra tap on the field).
    let requestComposerFocusSignal = PassthroughSubject<Void, Never>()
    /// Force scroll-to-bottom AND re-enable auto-scroll. Used only for explicit user actions
    /// (send, enqueue, session reuse) — NOT during streaming, so user scroll position is respected.
    let forceScrollToBottom = PassthroughSubject<Void, Never>()
    /// Force scroll-to-top (first message). Used by the floating "scroll to
    /// first message" button — a counterpart to forceScrollToBottom that does
    /// NOT change auto-scroll mode (jumping to the top is always a browse action).
    let forceScrollToTop = PassthroughSubject<Void, Never>()
    /// Signal sent when a text block transitions from empty to non-empty content.
    /// The coordinator reconfigures the affected cell so UIHostingConfiguration
    /// re-measures its height (UIKit doesn't always trigger preferredLayoutAttributesFitting
    /// reliably when the SwiftUI body changes inside a UIHostingConfiguration).
    let blockContentFilledSignal = PassthroughSubject<(messageId: UUID, blockId: UUID), Never>()
    /// [T-fold-at-request-end] The assistant message the running agent loop
    /// is writing into; nil between loops. The message list folds only this
    /// message up to its fold horizon and plans every other message whole —
    /// `isProcessing` alone is too broad (a manual compaction sets it with no
    /// loop running, and the previous reply would then be cut back).
    var toolFoldRunningMessageId: UUID?
    /// [T-fold-at-request-end] For the running message: the last block of
    /// every request (one LLM call) whose reply was long enough to fold the
    /// tool runs before it (`ToolFoldPlanner.isFoldSeparator`), plus the last
    /// block it already held when this loop started writing into it (a resumed
    /// or retried turn: that content is finished, and was planned whole). The
    /// list folds the message up to the latest of these
    /// (`ToolFoldPlanner.foldHorizon`). Kept here rather than in the list so a
    /// re-created chat view still knows them. Cleared when a loop starts/ends.
    var toolFoldSeparators: [UUID: Set<UUID>] = [:]
    /// Fires with the message id after a request added to `toolFoldSeparators`.
    let toolFoldSeparatorSignal = PassthroughSubject<UUID, Never>()
    /// Content offset Y published on each scroll event (for debug jitter monitoring).
    let contentOffsetYSignal = PassthroughSubject<CGFloat, Never>()
    /// Content size height delta signal (for debug jitter monitoring).
    let contentSizeDeltaSignal = PassthroughSubject<CGFloat, Never>()
    /// Fired after a retry truncation to force the message list to re-apply its
    /// diffable snapshot. Needed because `retryFromToolBlock`'s sub-message path
    /// mutates `messages[i].blocks` in-place without changing the messages
    /// array count, so `$messages` won't fire a new value and the UIKit-backed
    /// `CollectionViewMessageListV3` (which doesn't observe `objectWillChange`)
    /// would otherwise keep showing the pre-cut block identifiers.
    let retrySnapshotReloadSignal = PassthroughSubject<Void, Never>()
    /// Whether the message list is scrolled near the bottom. Updated by CollectionViewMessageList.
    @Published var isNearBottom: Bool = true

    /// Whether the viewport is already at the very first user turn's top — i.e.
    /// the up-button ("scroll to previous turn") has nowhere further up to go.
    /// Drives ONLY the up-button's visibility (the down-button still keys off
    /// isNearBottom): once the user has walked all the way up, the up-button
    /// hides. Updated by CollectionViewMessageList on scroll/jump.
    @Published var isAtFirstTurn: Bool = false

    /// [ScrollDiag] View-layer record of a scroll-jump button's actual SwiftUI
    /// mount/unmount, so a ring dump (debug.scrollMetrics) can be diffed against
    /// the VM-side buttonsVisible. `up` picks which button; `visible` is true on
    /// appear, false on disappear. DEBUG-only; compiled out in Release.
    func recordScrollButtonRender(up: Bool, visible: Bool) {
        #if DEBUG
        ScrollMetricsRecorder.shared.record(
            kind: "btnRender",
            a: visible ? 1 : 0,
            pos: "\(up ? "up" : "down")-\(visible ? "appear" : "disappear") vmNearBottom=\(isNearBottom)")
        #endif
    }

    // Note: Stream throttle timestamps (lastTextDeltaFlush, lastFileWriteStreamUpdate,
    // lastToolInputStreamUpdate) are now local vars inside processStreamEvents().
    @Published var kernelStatus: KernelStatus = .notBooted
    /// When enabled, agent responses and tool descriptions are spoken aloud.
    /// Initialized from the persisted "Read replies" preference so an already-on
    /// toggle drives streaming TTS for new chats.
    /// Read-replies on/off. NOT per-session state — proxies the GLOBAL
    /// `VoiceOutputState.shared` so toggling in any session (or the home screen)
    /// is reflected everywhere. `voiceStateCancellable` (set in init) forwards the
    /// global object's changes to this VM so views observing `vm.speakEnabled`
    /// still refresh.
    var speakEnabled: Bool {
        get { VoiceOutputState.shared.isEnabled }
        set { VoiceOutputState.shared.isEnabled = newValue }
    }
    /// When enabled, uses 1-hour cache TTL instead of 5-minute for Anthropic requests.
    @Published var enhancedCacheEnabled = false

    /// Whether the Enhanced Cache toggle should be visible. Only Anthropic
    /// official API (no custom base URL) supports the cache TTL protocol.
    var showEnhancedCacheToggle: Bool {
        guard let entry = resolveCurrentEntry(),
              let inst = ProviderConfigStore.shared.instance(for: entry.providerInstanceId)
        else { return false }
        guard inst.providerType == .anthropic else { return false }
        if let url = inst.customBaseURL, !url.isEmpty { return false }
        return true
    }

    // MARK: - Compact State
    /// Whether the slash command menu should be shown.
    @Published var showSlashMenu = false
    /// Filter text after "/" in the input.
    @Published var slashFilter = ""
    /// Currently highlighted index in the slash menu (-1 = none selected).
    @Published var slashMenuSelectedIndex = -1
    /// Whether a compaction is in progress.
    @Published var isCompacting = false
    /// When true, shows a prompt asking user to compact before sending.
    @Published var showCompactBeforeSendPrompt = false
    /// [T-chat-auto-compact-opt-in] Global (cross-session) opt-in: when the
    /// context-capacity threshold fires, compact automatically instead of
    /// prompting — the same no-UI path shortcut sessions already use. Set
    /// from the confirm dialog's "Compact & Enable Auto-Compact" button or
    /// the "..." menu's Auto Compact toggle; persisted in UserDefaults so
    /// future conversations inherit it.
    @Published var autoCompactEnabled: Bool = UserDefaults.standard.bool(forKey: "autoCompactOnThreshold") {
        didSet {
            guard autoCompactEnabled != oldValue else { return }
            UserDefaults.standard.set(autoCompactEnabled, forKey: "autoCompactOnThreshold")
        }
    }
    /// When true, shows a prompt telling user to start a new session or clear chat.
    @Published var showContextExhaustedPrompt = false
    /// Message text held back while the compact-before-send prompt is shown.
    var pendingSendText: String?
    /// Attachments held back while the compact-before-send prompt is shown.
    var pendingSendAttachments: [InputAttachment] = []
    /// [T-programmatic-prompt-no-composer] True when `pendingSendText` came
    /// from the composer, i.e. the user typed it. A programmatic prompt can
    /// reach the same holding area (send()'s .needsCompact / .exhausted
    /// branches run for every caller), and `cancelCompactBeforeSend` must not
    /// pour a job's prompt into the user's draft — it restores only their own
    /// text.
    var pendingSendIsFromComposer = false
    /// When true, skip the needsCompactBeforeSend check (used after compactAndSend to avoid loop).
    var skipCompactCheck = false
    /// When false, memory_write tool calls are skipped (returns "Memory disabled") in this session.
    @Published var memoryEnabled = true

    // MARK: - Session Stats
    /// Accumulated streaming duration (seconds) for output token speed calculation.
    var sessionStreamDuration: TimeInterval = 0
    /// Total output tokens produced during streaming (for speed calculation).
    var sessionStreamOutputTokens: Int = 0
    /// Cumulative cache read tokens across all API calls in this session.
    var sessionCacheReadTokens: Int = 0
    /// Cumulative cache write (creation) tokens across all API calls in this session.
    var sessionCacheWriteTokens: Int = 0
    /// Cumulative input tokens (excl. cache) across all API calls in this session.
    var sessionInputTokens: Int = 0
    /// Cumulative output tokens across all API calls in this session.
    var sessionOutputTokens: Int = 0

    // Tool snapshots
    @Published var toolSnapshots: [ToolSnapshotItem] = []

    // Attachments
    @Published var attachments: [InputAttachment] = []
    /// [OpenMinis#433] The composer holds something worth keeping when the
    /// user leaves: non-blank text (which also covers `[Pasted#N]`
    /// placeholders, whose buffer lives on this VM) or an attachment.
    var hasUnsentDraft: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }
    /// Number of videos currently being imported from the photo picker.
    @Published var loadingVideoCount = 0

    // [T-paste-placeholder] Session-scoped buffer for long pasted texts.
    //
    // A long paste no longer becomes a .txt attachment (models treat files
    // through a different, often worse, path than inline text). Instead the
    // text is stashed here and a `[pasted#N]` literal is inserted at the
    // caret; send() expands the literals back to the original text.
    //
    // Deliberately memory-only: the composer draft itself (`inputText`) is
    // never persisted, so buffer and draft share one lifetime by
    // construction — there is no "draft survived but buffer didn't" state to
    // degrade from. `nextPasteId` is monotonically increasing per vm
    // lifetime so ids are never reused while any draft that references them
    // can still exist.
    @Published var pastedTexts: [PastedText] = []
    var nextPasteId = 1

    /// Old iOS releases visibly jitter when the actively streaming markdown block
    /// re-self-sizes during user scroll/deceleration. While this flag is set, the
    /// newest streamed text snapshot is buffered and only applied after scrolling settles.
    struct DeferredStreamingTextUpdate {
        let messageId: UUID
        let blockId: UUID
        let text: String
        let parsedMarkdown: MarkdownContent?
        let cacheAttributedString: Bool
    }
    var deferredStreamingTextUpdates: [DeferredStreamingTextUpdate] = []
    var streamingUIUpdatesSuspended = false

    /// Set when `isProcessing` transitions to false but `retrySnapshotReloadSignal`
    /// cannot fire because `streamingUIUpdatesSuspended` is true. Cleared when the
    /// suspend lifts — at that point the snapshot rebuild is safe and is replayed.
    var needsSnapshotReloadOnResume = false

    /// [T-ios-ui-blocks-lost-suspend-resume] Fired on the main thread whenever
    /// `streamingUIUpdatesSuspended` transitions from true → false, from ANY
    /// path (scroll-settle resume, transition resume, explicit clear). The
    /// message-list Coordinator registers this so it can rebuild a snapshot it
    /// deferred while suspended (`hasPendingSnapshot`). Without it, a suspend
    /// window that opens during a multi-tool agent loop and closes after the
    /// stream ends has no subscription left to trigger the deferred flush, so
    /// the trailing assistant blocks never render even though they're in the DB.
    var onStreamingUIUpdatesResumed: (() -> Void)?

    /// [T-voice-viewport-context] Installed by the message-list Coordinator: the rows
    /// around what the user is looking at, for voice correction's on-screen context.
    /// Main thread. nil (or returning nil) when no list is on screen.
    var captureViewportSnapshot: (() -> ViewportSnapshot?)?

    /// True while this vm is the OUTGOING side of a session-switch transition.
    /// During the brief window when the UICollectionView/SwiftUI host views of
    /// the previous session are being torn down and the new session's views
    /// are being mounted, both ViewGraphs share the same AsyncRenderer thread.
    /// A concurrent mutation on the outgoing vm here can cause
    /// AG::Subgraph::NodeCache::~NodeCache to deref a dangling pointer
    /// (FB13213926, recurring), evidenced by build-48 crash
    /// Minis-2026-06-01-134710.ips: user switched sessions while both vms had
    /// `isProcessing=true`, EXC_BAD_ACCESS in
    /// `_UIHostingView.isHiddenForReuse.setter → ViewGraphHost.updateRemovedState
    /// → AG::Subgraph::invalidate_now → AG::Subgraph::NodeCache::~NodeCache`.
    /// While `transitionSuspended` is true:
    ///   * `streamingUIUpdatesSuspended` is force-true (text-block flush defer)
    ///   * Manual `objectWillChange.send()` callers consult `isTransitionSuspended`
    ///     and elide the publish when true (retry / edit / thinking-level
    ///     paths). The next genuine state change after resume re-publishes.
    var transitionSuspended = false

    /// True for the synchronous window of `retryFromMessage` /
    /// `retryFromToolBlock`: from the moment we start clearing `canResume` /
    /// truncating `messages` until the DB truncation (`deleteMessagesAfter`)
    /// has completed. While set, a deferred iCloud-sync `reloadMessagesFromDB`
    /// must NOT run — it would rebuild `messages` from a DB snapshot taken
    /// mid-truncation (before/around the delete) and can drop the retried user
    /// message from the UI even though it survives in agentHistory (so the
    /// reply is based on it but its bubble vanishes). Reload calls skip+rearm
    /// while this is true, and the canResume didSet does not replay the
    /// deferred reload; the next safe idle drains it. [T-ios-retry-usermsg-vanish]
    var isTruncatingForRetry = false

    // MARK: - Browser
    /// `var`, not `let`: a helper (child) vm adopts its PARENT's pool so both
    /// agents browse in one tab set (T-p2-shared-workspace). Per-agent default
    /// tabs keep them from stepping on each other — see BrowserTabPool.owner.
    var browserTabPool = BrowserTabPool()
    /// When true, the agent loop pauses at the next checkpoint to let the user operate the browser.
    @Published var browserTakeoverActive = false

    // MARK: - Prompt Queue
    /// Prompts queued by the user while the agent loop is running.
    @Published var promptQueue: [QueuedPrompt] = []

    // MARK: - Speech

    let speechSynthesizer = AVSpeechSynthesizer()
    lazy var speechDelegate = SpeechFinishedDelegate()
    /// True when speech is paused (not stopped). Toggled by the floating speech button.
    @Published var speechPaused = false

    /// Accumulates reasons for provider fallbacks within a single attempt, consumed by runAgentLoop to insert info blocks.
    var fallbackReasons: [(model: String, instance: String, reason: String)] = []

    /// [T-provider-live-check] Model and provider each agent provider object
    /// of this conversation was built for, by entry id. Read before every
    /// request to check that provider is still there and enabled.
    var providerIdentities: [String: ProviderAvailabilityRules.Identity] = [:]

    /// True when the synthesizer is actively speaking or has queued utterances.
    var isSpeaking: Bool {
        speechSynthesizer.isSpeaking
    }

    /// Current read-replies speed multiplier, mirrored for the player control.
    /// Source of truth is VoiceOutputPreferences.speedMultiplier.
    @Published var speechSpeed: Float = VoiceOutputPreferences.speedMultiplier

    /// True once the first reply utterance has been handed to a TTS engine — used
    /// by the player control to collapse from expanded to compact on first speak.
    @Published var isReadingAloud = false

    /// Whether the floating speech player control is expanded (vs compact). Lives
    /// here so the chat view can overlay a tap-to-dismiss layer while expanded.
    /// Defaults to COMPACT — expansion is only initiated by an explicit user action
    /// that turns reading on (so a new session / relaunch shows compact).
    @Published var speechPlayerExpanded = false

    /// Per-reply snapshot of the TTS engine choice; cleared at each reply start.
    var replyUsesCloudTTS: Bool?

    /// True once THIS turn (one user send, spanning ALL agent-loop iterations)
    /// has cleared the previous turn's TTS leftovers. Lives on the vm — NOT on
    /// StreamResult, which is recreated per loop iteration: a per-iteration
    /// flag made every iteration's first textDelta call stopSession and cut
    /// off the previous iteration's still-playing speech. One turn = one
    /// read-aloud context; iterations append and play back-to-back.
    var hasClearedTTSForCurrentTurn = false

    // MARK: - Private

    /// Approximate current time string, rounded to the hour for cache stability.
    var _cachedTimeString: String = ""
    var _cachedTimeDate: Date = .distantPast

    /// Session ID for persistence integration. Set by the view on appear.
    var sessionId: String? {
        didSet {
            // A helper shares its parent's pool; never restamp it with the
            // child's id (that would move tab persistence to the child).
            if helperConfig == nil { browserTabPool.sessionId = sessionId }
            // [T-opencode-dedicated-channel] Keep the off-MainActor mirror in
            // step. This `didSet` is the single choke point every promotion
            // path flows through (ensureSessionReturningId, loadSession, the
            // RPC/intent entry points), so mirroring here means no caller has
            // to remember to do it.
            openCodeSessionBox.value = sessionId
        }
    }

    /// [T-opencode-dedicated-channel] Off-MainActor mirror of `sessionId`, read
    /// by the OpenCode channel's per-request header hook.
    ///
    /// The hook runs wherever the request is built, which is not guaranteed to
    /// be the MainActor, while `sessionId` is MainActor-isolated state — so it
    /// cannot be read directly from a `@Sendable` closure. This box is the
    /// hand-off: written on main by the `didSet` above, read under a lock by
    /// the hook. Held by the VM (not global) because the id is per
    /// conversation.
    let openCodeSessionBox = OpenCodeSessionBox()

    /// The draft ID assigned by the parent view (e.g. "__new__<UUID>").
    /// Included in `.sessionDidCreate` notification so the parent can correlate.
    var draftId: String?

    /// Source tag written to the session record on creation (e.g. "shortcut").
    var sessionSource: String?

    /// [T-shortcut-duplicate-completion-notification] Suppresses the *generic*
    /// background-completion notification for this run, because a Shortcuts
    /// intent already posts its own via `ShortcutNotification`. Without this the
    /// user gets two overlapping notifications for one task: "Minis Task
    /// Completed" from the intent and "✅ {sessionTitle}" from
    /// `endBackgroundProcessing`.
    ///
    /// Deliberately NOT keyed off `sessionSource == "shortcut"`: that value also
    /// drives near-capacity auto-compaction and the context-exhausted error path
    /// (see `send()`), and RetryRun/FollowUp operate on sessions the user may
    /// have created by hand in the app. Tagging those as "shortcut" to get the
    /// notification behaviour would silently opt them into auto-compaction too.
    /// This flag carries exactly one meaning and nothing else reads it.
    ///
    /// Run-scoped and CONSUMED on read: `endBackgroundProcessing` clears it as it
    /// checks it, so it suppresses exactly the one completion it was set for.
    /// That matters because a VM is cached and reused — if the user opens the
    /// same session later and sends a message by hand, that run must still get
    /// its normal completion notification. A sticky flag would silence the
    /// session forever. Not persisted; each intent sets it fresh.
    var suppressGeneralCompletionNotification: Bool = false

    /// Model group to bind when creating a new session (from long-press FAB).
    var initialGroupId: String?

    /// Currently active session ID — accessible from anywhere for minis:// URL resolution.
    /// Updated whenever a session is loaded.
    nonisolated(unsafe) static var activeSessionId: String?
    /// REPRO-DIAG(2026-05-16): global round counter — each runAgentLoop
    /// invocation bumps this. Use `ROUND \d+` to slice the log by attempt.
    nonisolated(unsafe) private static var diagRoundCounter: Int = 0
    nonisolated static func bumpDiagRound() -> Int {
        // Not atomic because runAgentLoop is invoked from main actor and
        // serialised per ViewModel; concurrent rounds across VMs may race
        // and skip/dup a number, which is acceptable for a diagnostic id.
        diagRoundCounter &+= 1
        return diagRoundCounter
    }
    nonisolated static func currentDiagRound() -> Int { diagRoundCounter }
    /// Timestamp when onAppear fires — used to measure end-to-end load latency.
    nonisolated(unsafe) static var onAppearTimestamp: CFAbsoluteTime = 0

    /// Number of title generation attempts for this session (max 3).
    var titleGenAttempts = 0
    /// Whether a title generation request is currently in-flight.
    var isTitleGenerating = false

    /// [T-ios-switch-model-ghost-retry] Generation token for the detached
    /// title-generation Task.
    ///
    /// That Task resolves its model ONCE (`resolveSubEntry()`, which with no
    /// per-session sub model is the PRIMARY entry) and then retries up to 3
    /// times with a 1.5s gap. Without a token, a model switch during that
    /// window left it calling the model the user had just abandoned — one of
    /// the two ghost-retry sources in this bug.
    ///
    /// `cancelWorkBoundToPreviousModel` bumps this; the Task compares it
    /// before each attempt and bails on a mismatch. A plain bool could not do
    /// the job: title generation legitimately re-runs later (more turns
    /// arrive), and a bool would either block the new run or be reset by it.
    var titleGenEpoch: UInt = 0

    /// Unified conversation history used by both Anthropic and Gemini agent loops.
    var agentHistory: [AgentMessage] = []

    #if DEBUG
    /// [T-ios-log-noise-reduction] High-water mark of how many agentHistory
    /// entries the Debug `📋 agentHistory[i]` dump has already printed. The
    /// per-API-call dump only NSLogs entries at index ≥ this value (the delta
    /// since the previous call) instead of re-printing the whole growing
    /// history every iteration. Reset to 0 when the history shrinks.
    var lastDumpedAgentHistoryCount: Int = 0
    #endif

    /// Detects tool-call loops (repeated unknown tools, no-progress polling, runaway
    /// retries) and either injects warnings or short-circuits execution.
    let toolLoopDetector = ToolLoopDetector()

    // MARK: - Cache Keep-Alive State
    /// Snapshot of agent loop state for cache keep-alive warmup requests.
    /// Updated each iteration so the manager can replay the same prefix.
    var keepAliveHistory: [AgentMessage] = []
    var keepAliveSystemPrompt: String?
    var keepAliveTools: [AgentToolDefinition] = []

    // MARK: - Compact Marker (Phase B)
    /// Cached latest compact marker for this session. Phase B agent loop uses this
    /// (via effectiveAgentHistory) to inject the summary at inference time instead
    /// of mutating agentHistory. Updated by loadSession, compactBefore, and any
    /// path that writes a new marker.
    var cachedLatestMarker: CompactMarker?
    /// [T-offload-scan-cache] Per-part verdicts of the context-offload scanner,
    /// so a re-trigger does not re-judge and re-tokenize the whole history.
    /// In memory only; an empty cache (new VM, relaunch) simply rebuilds on the
    /// next scan. See `OffloadScanCache`.
    let offloadScanCache = OffloadScanCache()
    /// The session's persisted model id (from ChatStore.getSession). Cached at
    /// loadSession time so resolveCurrentEntry can fall back to it without an
    /// async hop to the actor. Empty string means "not yet loaded" — treat as
    /// no fallback.
    var cachedSessionModelId: String = ""
    /// The ModelEntry used in the current/last agent loop, for rebuilding the provider.
    var keepAliveEntry: ModelEntry?
    /// Pending thought signatures loaded from persisted session, keyed by tool call ID.
    /// Applied to GeminiAgentProvider when the agent loop starts.
    var pendingThoughtSignatures: [String: ToolCallMetadata] = [:]
    // `internal` (not `private`): the +Compaction extension's
    // schedulePostCompactDrain() runs the post-compact queue drain on this
    // task so cancel() can stop it. [T-compact-queued-drain]
    var currentTask: Task<Void, Never>?
    var compactTask: Task<Void, Never>?

    /// [T-ios-compact-task-binding] Which entry point started the compaction
    /// `compactTask` is currently holding.
    ///
    /// This exists because cancel()'s cleanup is NOT uniform across entry
    /// points: only compact-and-send has queued prompts to roll back. Once
    /// every entry point binds `compactTask` (previously only two of five did),
    /// cancelling a long-press compaction would otherwise run the
    /// compact-and-send rollback — emptying `promptQueue` and bouncing someone
    /// else's queued message into the input box. The origin lets cancel() undo
    /// only what this particular compaction actually set up.
    enum CompactOrigin {
        /// `/compact` slash command, or the toolbar item.
        case slashCommand
        /// Long-press a message → "Compact Above".
        case longPress
        /// User sent a message that needed compaction first; prompts are queued.
        case beforeSend
        /// Debug JSON-RPC (DEBUG builds only).
        case debugRPC
    }
    var compactOrigin: CompactOrigin?
    var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    /// [T-ios-bgkeepalive-diag] Process-wide count of LIVE
    /// `beginBackgroundTask` grants, so crash diagnostics can report whether a
    /// real `UIBackgroundTaskIdentifier` was held — previously the crash report's
    /// "BG task active" field showed `BackgroundKeepAliveManager.isActive`, a
    /// keep-alive *intent* flag with no relation to the OS grant, which made
    /// every report read as "background task healthy" even when no task was held.
    /// Maintained by begin/endBackgroundProcessing; `nonisolated(unsafe)` +
    /// lock-free because it is only mutated on the MainActor.
    @MainActor
    private(set) static var liveBackgroundTaskCount = 0

    @MainActor
    static func noteBackgroundTaskBegan() { liveBackgroundTaskCount += 1 }

    @MainActor
    static func noteBackgroundTaskEnded() {
        liveBackgroundTaskCount = max(0, liveBackgroundTaskCount - 1)
    }
    /// Tracks how many blocks on the current assistant message have been fully committed
    /// to agentHistory. Used by retry()/resume() to trim partial iteration content.
    var committedBlockCount: Int = 0
    /// The committedBlockCount before the current/last iteration started.
    /// Used by handleUserCancelledCleanup to roll back the last iteration.
    var prevCommittedBlockCount: Int = 0
    /// Set by cancel() so the task's error handler knows this was a user stop.
    /// Internal-access so concurrent tool extensions can read it. [T-concurrent-tools]
    var userDidCancel = false
    /// [T-stop-queued-cancel-error] Whether a turn's error epilogue is looking
    /// at the end of a Stop rather than a real failure.
    ///
    /// `userDidCancel` alone is not enough. It is shared by every turn of this
    /// vm, and when Stop leaves queued prompts behind, `resumeQueueAfterCancel`
    /// resets it to false after 200 ms so the drained turn can run. A turn
    /// stopped before its first token is usually still waiting on the HTTP
    /// response at that point, so its `LLMError.cancelled` ("Request was
    /// cancelled") arrives after the reset, reads as a real failure, and is
    /// pinned (with Retry) to the last assistant row — by then the NEW drained
    /// turn's bubble, whose start-of-turn error sweep already ran, so it never
    /// goes away. `Task.isCancelled` belongs to the stopped task itself and
    /// cannot be reset from outside, so it catches that late error.
    var turnWasStopped: Bool { userDidCancel || Task.isCancelled }
    /// [T-stop-sibling-subagent] Set when the user stops a sub agent from its
    /// card rather than stopping this conversation outright.
    ///
    /// Kept separate from `userDidCancel` on purpose. `userDidCancel` is read
    /// all over the loop's ending path — it removes placeholder blocks, marks
    /// the turn interrupted and drives `handleUserCancelledCleanup`. Setting it
    /// from a card would put the parent through a stop it never asked for. This
    /// flag says only "results delivered from now on must not restart the
    /// conversation", which is the whole of what the card's Stop means for the
    /// parent. Cleared whenever a new turn begins.
    var delegationResultsMuted = false
    /// [T-p0-programmatic-prompt] True while the current turn was started by
    /// `submitProgrammaticPrompt(silent: true)`; suppresses the send and
    /// completion haptics for that turn only. Cleared on every
    /// isProcessing → false transition.
    var programmaticSilentTurn = false
    /// [T-user-ask] Origin of a programmatic prompt that STARTED the current
    /// run (Shortcut / CLI / job) — such a run has no one to ask, so user_ask
    /// is not exposed. Cleared on every isProcessing → false transition.
    var programmaticTurnOrigin: ProgrammaticPromptOrigin?
    /// [T-user-ask] Whether this run exposes user_ask, decided with the tool
    /// list so the system prompt's fragment agrees with it for the whole run.
    var userAskExposedThisRun: Bool?
    /// [T-user-ask-deferred] This run exposes user_ask in deferred mode (no
    /// one can answer while it runs): the call returns `deferred` at once.
    var userAskDeferredThisRun: Bool?
    /// [T-user-ask-fallback] user_ask was called in this run (any outcome), so
    /// a question in the final text is not a missed ask. Reset per run.
    var userAskAskedThisRun = false
    /// [T-user-ask] The assistant row (tool_use included) of the tool batch
    /// now executing, and its tool ids — the loop writes that row only after
    /// the batch, so user_ask keeps a copy for recovery after a kill.
    var currentBatchAssistantRaw: RawMessage?
    var currentBatchToolUseIds: [String] = []
    /// [T-p1-delegate-task] Non-nil on a helper (child) vm. Drives the
    /// helper-specific prompt, tool set, turn cap and skill scope.
    var helperConfig: HelperConfig?
    /// [T-agent-model-identity] What the latest served turn of this vm's
    /// loop actually ran on (entry after fallback + the API-reported model).
    /// Read by the parent's HelperRunner / AgentJobRegistry for agent
    /// sessions; harmless bookkeeping on every other vm.
    @Published var lastEffectiveModel: EffectiveModelRecord?
    /// [T-agent-wrapup-turn] Set by the parent's budget watcher when a
    /// helper's wall-clock budget runs out: the loop then gives the child ONE
    /// more turn without tools to write its deliverable (see runAgentLoop).
    var helperWrapUpRequested = false
    /// [T-subagent-timeout-reason] Set by HelperRunner right before it
    /// cancels this helper because the budget AND the wrap-up grace ran out.
    /// That `cancel()` also sets `userDidCancel`; this flag is what tells the
    /// runner's timeout stop apart from a real user / parent Stop when the
    /// ending is classified. Reset when the runner starts a run.
    var helperStoppedForTimeout = false
    /// [T-subagent-termination] The loop sent this helper its one-shot
    /// closing request after a turn that ended with no text. Read by
    /// HelperRunner when it records how the run ended.
    var helperClosingAttempted = false
    /// [T-sub-agents-steer] Course corrections the parent queued for a running
    /// sub agent, delivered at the top of its next loop turn.
    ///
    /// Deliberately NOT delivered by interrupting: an in-flight tool call is
    /// never cut, so a steer that lands while the child is inside a 2-minute
    /// shell command is read when that command returns. That is the whole point
    /// of steering rather than cancelling — the work so far is kept.
    ///
    /// Written by the parent's tool call on the main actor and drained by the
    /// child's loop on the same actor, so no lock is needed.
    var pendingSteerMessages: [String] = []
    /// [T-p0-programmatic-prompt] Ids of queued prompts that arrived through
    /// `submitProgrammaticPrompt(silent: true)`. A drain started by
    /// `startDrainIfIdle` consults this to decide whether the turn it runs is
    /// silent (only when EVERY prompt it drains is programmatic).
    var silentQueuedPromptIds = Set<UUID>()
    /// [T-scheduled-preset-tool] Preset first steps of scheduled fires handed
    /// to this session, keyed by job id, waiting for the request that answers
    /// the fire's envelope (see `takePresetToolStream`). A later fire of the
    /// same job replaces its entry.
    var pendingPresetToolCalls: [String: ScheduledPresetToolCallRequest] = [:]
    /// Reentrancy guard for `drainQueuedPrompts()`. After a Stop with queued
    /// prompts, `cancel()` hands off to a fresh Task via `resumeQueueAfterCancel()`,
    /// but the original (superseded) send/retry/resume Task ALSO reaches its own
    /// post-loop `drainQueuedPrompts()` call. Without a guard both Tasks could run
    /// the queued turn, firing the next LLM request — and thus every tool call +
    /// reply — TWICE. Set/cleared only on @MainActor, so the check-and-set is
    /// atomic and spans the `await runAgentLoop()` suspension where the second
    /// drainer would otherwise slip in. [T-ios-concurrent-stop-double-request]
    var isDrainingQueue = false
    /// [T-queue-drain-handover] A drain was requested while another task held
    /// `isDrainingQueue`; the holder re-offers it when it releases the guard.
    var drainRequestedWhileBusy = false
    /// [T-compact-queued-drain] True while a post-compact queue drain has been
    /// scheduled (task created) but not finished. Dedup guard so the two
    /// schedulers (compactBefore's success tail + compactAndSend's failure
    /// backstop) can't spawn two racing drain tasks for the same compact.
    var postCompactDrainPending = false
    /// When non-nil, the next send() acts as an edit: truncates conversation from this
    /// message index and re-sends. Cleared after the edit is applied.
    @Published var editingMessageIndex: Int?
    /// [T-bubble-span] The edited bubble's id and its pre-edit text, captured
    /// by editMessage() and cleared with editingMessageIndex. In memory only.
    /// send() uses them to re-find the bubble (the index can go stale between
    /// Edit and Send) — see resolveEditedBubbleIndex.
    var editingMessageId: UUID?
    var editingOriginalText: String?
    /// [T-bubble-span] Bubbles an edit / delete-from-here removed while their
    /// send() had not yet appended the history entry (`awaitingHistoryEntry`).
    /// That send consumes its id here and drops the stale turn instead of
    /// appending the removed message behind the cut.
    var abandonedPendingSendIds: Set<UUID> = []
    /// Set when the background task expires mid-agent-loop; cleared on resume.
    var backgroundSuspended = false
    /// Continuation used to pause the agent loop while suspended in background.
    var foregroundContinuation: CheckedContinuation<Void, Never>?
    /// Continuation used to pause the agent loop during browser takeover (between turns).
    var takeoverContinuation: CheckedContinuation<Void, Never>?
    /// Continuation used to pause mid-action when the user takes over during a browser action.
    var midActionTakeoverContinuation: CheckedContinuation<Void, Never>?
    /// Timeout task for mid-action takeover (5 minutes).
    var takeoverTimeoutTask: Task<Void, Never>?
    var foregroundObserver: NSObjectProtocol?
    /// Timer that logs tool execution status while the app is backgrounded.
    var backgroundStatusTimer: Timer?
    let defaultCommandTimeout: TimeInterval = 900 // 15 minutes
    /// PID of the currently running shell command (0 = none).
    @Published var runningCommandPid: Int32 = 0
    /// Start time of the currently running command (nil = no command running).
    @Published var commandStartTime: Date?
    /// Set to `true` when the user explicitly stops a running command via the stop button.
    /// Checked after command completion so the tool_result can inform the model.
    var commandCancelledByUser = false

    /// Number of shell_execute tools currently in their pre-execution `delay`
    /// countdown. Lets `stopCurrentCommand()` treat the stop button as a valid
    /// cancel during the wait even though no iSH process exists yet.
    /// [T-delay-stop-latency] A COUNTER, not a Bool: under concurrent tool
    /// execution a second delaying tool finishing (and running its `defer`)
    /// would otherwise flip a shared Bool back to false while a sibling was
    /// still counting down, making the stop button a NOOP for that sibling.
    var toolDelayWaitCount = 0

    /// True while at least one shell_execute tool is in its pre-execution
    /// `delay` countdown.
    var toolDelayWaitActive: Bool { toolDelayWaitCount > 0 }

    /// Whether at least one enabled provider instance exists (has selectable models).
    /// Credential validity is checked at send time, not here — avoids blocking the
    /// send button due to Keychain/OAuth state that SwiftUI can't observe.
    var isReady: Bool {
        ProviderConfigStore.shared.instances.contains { $0.isEnabled }
    }

    // MARK: - Session Persistence

    /// Load an existing session's messages from the database and rebuild UI + agent history.
    ///
    /// The DB stores one RawMessage per API turn: user, assistant, user(tool-results), assistant, ...
    /// Reload messages from DB after iCloud sync brings new data.
    /// Only reloads if there are new messages (avoids disrupting active sessions).
    /// Tracks the highest DB sortOrder seen after each load, so iCloud sync reload
    /// only triggers when genuinely new messages arrive from another device.
    var lastKnownDbSortOrder: Int = 0
    /// Tracks the DB message count so we can detect remote deletions (retry propagation).
    var lastKnownDbCount: Int = 0
    /// Hash of the (id, sort_order) pairs from the last DB load. Catches a
    /// silent reorder by another sync path (HEAL on LWW skip) where neither
    /// the count nor the max sort_order changed.
    var lastKnownDbOrderHash: Int = 0
    /// Number of assistant turns in `agentHistory` at the moment we LAST marked
    /// this session unread. `endBackgroundProcessing()` is called from ~15 sites
    /// (normal completions, kernel-failure early-returns, cancel cleanup, the
    /// bgTask-expiration handler, resumeQueueAfterCancel, …), and it used to
    /// push `.unread` unconditionally on every one of them. That made a late or
    /// duplicate call — e.g. a background keep-alive bgTask expiring after the
    /// user already read and left the session — re-add the red dot with NO new
    /// content. We now only re-badge when the assistant-turn count has actually
    /// grown since the last badge, i.e. this run genuinely produced a new
    /// completion. [T-ios-unread-dot-reappears]
    var lastBadgedAssistantTurnCount: Int = -1

    // MARK: - Slash Commands (stored state)
    // Method bodies live in AIChatViewModel+SlashCommands.swift; stored
    // properties must stay on the class itself (extensions can't add them).

    /// Set by the slash-command handler to ask the view to show the
    /// "Clear Chat?" confirmation alert. The view mirrors this into its
    /// local @State and resets the flag back to false on observation.
    @Published var clearChatConfirmRequested = false

    /// Text saved before showing slash menu over existing input.
    /// When non-nil, the menu was opened via the "/" button while text existed —
    /// executing a command should restore this text instead of clearing it.
    var savedInputBeforeSlash: String?
    /// Caret offset saved alongside `savedInputBeforeSlash`.
    var savedCaretBeforeSlash: Int?

    // MARK: - File Mention (`@`) Menu

    /// Whether the `@`-file menu is visible.
    @Published var showMentionMenu = false
    /// Currently highlighted row index (-1 = none).
    @Published var mentionSelectedIndex: Int = -1
    /// Live filter extracted from the active `@<token>` in the input.
    @Published var mentionFilter: String = ""
    /// The `@` character's UTF-16 offset in `inputText` for the currently active trigger.
    /// Used to replace the token on selection. -1 when inactive.
    var mentionAnchor: Int = -1



    /// In-memory thinking level for sessions not yet persisted (no sessionId yet).
    /// nil = user hasn't explicitly set one; fall back to the default group's level.
    var pendingThinkingLevel: ThinkingLevel?

    /// Append an ephemeral system info message (not sent to LLM).
    func appendSystemInfo(_ text: String, icon: String) {
        let msg = ChatMessage(role: .systemInfo, content: text)
        msg.systemIcon = icon
        messages.append(msg)
    }

}

extension AIChatViewModel {
    /// [T-deep-mode] Global "深度龙虾Ai" agent-mode switch, read live from
    /// UserDefaults (the Settings toggle) so it applies across all sessions
    /// without per-session state. When on, an extra deep-mode behavior
    /// fragment is injected and the bundled deep skills are enabled.
    var deepModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "deepMode.enabled")
    }

    /// [T-deep-mode-level] Three-tier intensity for deep mode, controlling
    /// which cognitive abilities are active and which sentinels are forced.
    /// Stored in UserDefaults so it persists across sessions and is readable
    /// from both ContentView (settings) and AIChatView (slash menu picker).
    /// - low: base workflow + C1-C5 (prompt only) + C9 background monitoring
    /// - medium: low + C10/C12/C14 forced sentinels + C9 sentinel
    /// - high: medium + C11 tool registration + C13 root cause
    var deepModeLevel: DeepModeLevel {
        DeepModeLevel(rawValue: UserDefaults.standard.string(forKey: "deepMode.level") ?? "medium") ?? .medium
    }

    /// Setter for deep mode level — persists to UserDefaults and broadcasts
    /// so live VMs re-read the level on the next turn.
    func setDeepModeLevel(_ level: DeepModeLevel) {
        UserDefaults.standard.set(level.rawValue, forKey: "deepMode.level")
        NotificationCenter.default.post(name: .deepModeLevelDidChange, object: nil)
    }

    /// [T-deep-mode-plan-gate] Gate state for Layer B: `.awaitingApproval`
    /// when the agent's last turn was a plan-only reply awaiting the user's
    /// confirm/edit. Only ever set while deep mode is on.
    @Published var planGateState: PlanGate.State = .idle

    /// [T-deep-mode-floating-panel] Multi-path selection state for the
    /// Trae-style floating confirm panel. Holds the user's chosen path indexes
    /// (1-based, matching CandidatePath.index) while a multi-path plan is
    /// awaiting approval. Empty means "use the recommended path". Reset to
    /// empty in resetWorkflow() so it never lingers across workflows.
    @Published var selectedPathIndexes: Set<Int> = []

    /// [T-deep-mode-workflow] Phase 1 explicit workflow state machine. The
    /// client owns the phase — `.planning` (plan raised), `.executing` (user
    /// confirmed) — instead of relying on the model's fuzzy plan output. Always
    /// gated on `deepModeEnabled` and reset to `.idle` whenever the toggle is
    /// off, so disabling deep mode leaves no residue.
    @Published var workflowPhase: WorkflowPhase = .idle


    /// [T-deep-mode-resume-opt] Saved state for fast resume after pause.
    /// When user pauses during workflow, we save the current state here.
    /// On resume, we skip re-evaluation and directly restore the saved state.
    private var savedWorkflowState: (phase: WorkflowPhase, steps: [WorkflowStep], verifyRoundsLeft: Int, goalRunnerRoundsLeft: Int)? = nil
    /// [T-deep-mode-workflow] Parsed plan steps for the current workflow, shown
    /// as a live progress list. Empty unless a plan is active. In-memory only.
    @Published var workflowSteps: [WorkflowStep] = []

    /// [T-deep-mode-session-workflow] P2: Rollback switch for session-scoped
    /// workflow. Default ON.
    ///
    /// When ON, an in-flight workflow (.executing/.verifying) survives
    /// interjections and pause/resume — the P0/P1 session behavior and its
    /// progress capsule. When OFF, the client falls back to the LEGACY
    /// "per-request workflow" behavior: every user send resets phase/steps, no
    /// snapshot is saved on pause, and nothing is restored on resume (the
    /// pre-refactor semantics). This is a configuration-layer kill-switch /
    /// grayscale lever, per refactor plan item 5. The default is read
    /// true-when-absent so a fresh install keeps the new behavior; the toggle
    /// is persisted in UserDefaults.
    @Published var keepSessionWorkflow: Bool = {
        let d = UserDefaults.standard
        // Absent key == never set == default to session-scoped behavior (ON).
        return d.object(forKey: "deepMode.keepSessionWorkflow") == nil
            ? true
            : d.bool(forKey: "deepMode.keepSessionWorkflow")
    }() {
        didSet {
            UserDefaults.standard.set(keepSessionWorkflow, forKey: "deepMode.keepSessionWorkflow")
            // [T-deep-mode-session-workflow] Audit H1: turning the rollback
            // switch OFF mid-workflow must destroy the pending session state,
            // otherwise phase/steps/snapshot/busy linger and the capsule keeps
            // rendering (the master switch is still on). resetWorkflow() also
            // clears savedWorkflowState and the round/verify budgets, so this
            // becomes a graceful, residue-free exit to the LEGACY behavior.
            if !keepSessionWorkflow {
                resetWorkflow()
                workflowBusy = false
            }
        }
    }

    /// [T-deep-mode-session-workflow] P2: Active workflow gating = total deep
    /// switch AND the session-workflow rollback switch.
    ///
    /// `deepModeEnabled` is the master switch; `keepSessionWorkflow` lets the
    /// operator disable the session behavior independently (Fallback mode).
    /// Both must hold for the session-scoped path (interjection preservation,
    /// pause snapshot / resume restore, and the activity indicator) to apply.
    /// Total-switch safe: when the master switch is off this is always false,
    /// so every affected path degrades to the pre-refactor behavior.
    /// Internal (not private) so the progress-capsule view can gate on it.
    var sessionWorkflowEnabled: Bool {
        deepModeEnabled && keepSessionWorkflow
    }

    /// [T-deep-mode-session-workflow] P2: Activity indicator for the progress
    /// capsule. True while the agent loop (a "round") is actively executing —
    /// model reasoning or tool calls such as shell/file — and false when the
    /// turn settles into an idle/awaiting state. The UI can render a
    /// pulse/small-spin on the capsule while this is true so a long-running
    /// shell call does not look like a frozen "0/x". Set to false immediately
    /// on round exit via `defer`. Gated so it never flickers outside an active
    /// session workflow.
    @Published var workflowBusy: Bool = false

    /// [T-deep-mode-workflow] Pending one-shot task that fades the completed
    /// tracker out after a short all-green "完成过渡". Cancelled on master-switch
    /// teardown so a disabled deep mode never lets a stray delay mutate state.
    var workflowFinishTask: Task<Void, Never>?

    /// [T-deep-mode-goal-runner] Remaining auto-continuation budget for Layer C.
    /// Decremented once per auto-round, reset to `GoalRunner.maxAutoRounds` on a
    /// fresh user send, on a `done` sentinel, on reaching the cap, and on
    /// session load. Not @Published: nothing renders it directly today; it is
    /// only consulted at the turn's end and logged for diagnostics.
    var goalRunnerRoundsLeft: Int = GoalRunner.maxAutoRounds

    /// [T-deep-mode-strip-sentinel] Sentinel resolved at text-capture time (in
    /// the agent loop, right before the final assistant text is flushed/persisted).
    /// The visible text is stripped of the `<<GOAL_STATE>>` line at that same
    /// point, so the auto-continue step at turn end reads this stash instead of
    /// re-parsing `block.content` (which no longer carries the marker).
    var pendingGoalSentinel: GoalRunner.ParseResult? = nil

    // MARK: - Phase 2: VerifyGate

    /// [T-deep-mode-verify-gate] Remaining self-verification rounds for Phase 2.
    /// Decremented each time we re-enter `.executing` from a failed verify,
    /// reset on fresh user send / session load / workflow reset. Not @Published:
    /// nothing renders it directly; it is only consulted at verify-turn end.
    var verifyRoundsLeft: Int = VerifyGate.maxVerifyRounds

    /// [T-deep-mode-verify-gate] Verify sentinel resolved at text-capture time,
    /// same pattern as `pendingGoalSentinel`. The `<<VERIFY_STATE>>` line is
    /// stripped from the visible text; the parsed result is stashed here for
    /// the verify-result handler at turn end.
    var pendingVerifySentinel: VerifyGate.ParseResult? = nil

    // MARK: - Phase F: SpecGate

    /// [T-deep-mode-phase-f] Spec-gate public state. `.awaitingReview(files:)`
    /// drives the spec-review panel; `.approved`+ is reached when the user
    /// approves and the workflow finishes. Always gated on
    /// `deepModeEnabled && specModeEnabled`; memory-only, never persisted —
    /// toggling either switch off leaves zero residue.
    @Published var specGateState = SpecGate.State.idle

    /// [T-deep-mode-phase-f] The spec artifacts produced on the latest
    /// spec-writing turn, surfaced in the review panel. Only consulted while
    /// Spec mode is active; cleared on reset / disable.
    @Published var pendingSpecFiles: [SpecGate.SpecFile] = []

    /// [T-deep-mode-phase-f] Whether the last spec-writing turn emitted the
    /// SPEC_STATE sentinel. Resolved at text-capture time alongside the other
    /// sentinels; consumed by `maybeProcessSpecResult` at turn end.
    var pendingSpecSentinel = false

    /// [T-deep-mode-phase-f] Remaining reject→regenerate edit rounds for the
    /// current workflow. Bounded so a reject/edit loop can't run forever.
    var specEditRoundsLeft = SpecGate.maxEditRounds

    /// [T-deep-mode-phase-f] Convenience: is the Spec gate live right now?
    /// True only when BOTH the master switch and the Spec-mode toggle are on.
    private var specActive: Bool { SpecGate.isActive(deepModeEnabled: deepModeEnabled) }

    // MARK: - Phase 2: ClarifyGate

    /// [T-deep-mode-clarify-gate] Clarification gate state for Phase 2.
    /// `.awaitingClarification` when the gate detected ambiguity in the user's
    /// request and raised a question before planning begins. Always gated on
    /// `deepModeEnabled`; memory-only, never persisted.
    @Published var clarifyState: ClarifyGate.State = .idle

    // MARK: - P2 Cognitive: C9 Cognitive Load Monitor

    /// [T-deep-mode-cognitive-p2-c9] Real-time cognitive load state. Updated
    /// during `runAgentLoop` by merging the model's self-assessed sentinel
    /// with client-computed metrics (context saturation, tool count, etc.).
    /// The UI renders a warning banner when level >= .high.
    /// Total-switch safe: reset to `.empty` in `deepModeDidDisableCleanup()`.
    @Published var cognitiveLoadState: CognitiveLoadState = .empty

    /// [T-deep-mode-cognitive-p2-c9] The model's self-assessed load signal
    /// from the last turn's sentinel. Kept separately so the UI can show
    /// both the model's and the client's assessment.
    var lastModelLoadSignal: CognitiveLoadSignal?

    // MARK: - P2 Cognitive: C10 Dynamic Autonomy Exit

    /// [T-deep-mode-cognitive-p2-c10] When the model emits
    /// `<<GOAL_STATE>> need_more_context: <reason>`, the auto-continuation
    /// loop stops and this state is set. The UI renders a "needs input" prompt.
    /// Reset to nil in `deepModeDidDisableCleanup()` and on fresh send.
    @Published var needMoreContextState: String? = nil

    /// [T-deep-mode-plan-gate] User approved the pending plan. Re-send an
    /// execution prompt through the normal `send()` path so it inherits every
    /// existing guard (context check, persistence, session tracking, run loop).
    /// After `send()` (which resets the workflow as part of its fresh-send
    /// path) re-enters the executing phase with the captured steps, so the
    /// progress tracker survives the confirm round-trip.
    ///
    /// [T-deep-mode-floating-panel] `selection` carries the user's multi-path
    /// choice from the floating confirm panel (empty = use the recommended
    /// path, so unchecking all is still safe). When the user picked specific
    /// paths, the execution prompt is rebuilt to mention only those paths and
    /// the step tracker is re-parsed from the merged selected path bodies, so
    /// the user's choice actually drives what gets executed. Passing a value
    /// overrides `selectedPathIndexes`; when nil, the stored property is read
    /// (the host just calls `confirmPlan()`).
    func confirmPlan(selection: Set<Int>? = nil) {
        guard case .awaitingApproval(let pendingPlanText, let paths, _) = planGateState else { return }
        let chosen = selection ?? selectedPathIndexes
        let capturedSteps: [WorkflowStep]
        let executionPrompt: String

        if !paths.isEmpty, !chosen.isEmpty {
            // Multi-path plan with explicit user selection: merge the bodies
            // of the chosen paths into one execution instruction.
            let selectedPaths = paths.filter { chosen.contains($0.index) }
            let mergedPlan = selectedPaths.map(\.body).joined(separator: "\n\n")
            capturedSteps = mergedPlan.isEmpty
                ? workflowSteps
                : WorkflowPlanParser.parseSteps(from: mergedPlan)
            let labels = selectedPaths.map { "路径 \($0.index)（\($0.title)）" }.joined(separator: "、")
            executionPrompt = AppLocalized("计划已确认。请严格按所选路径（\(labels)）执行，不要再输出计划，直接开始。")
        } else {
            capturedSteps = workflowSteps
            executionPrompt = AppLocalized("计划已确认。请严格按上述计划执行，不要再输出计划，直接开始。")
        }
        // [T-deep-mode-cognitive-p2-c14] C14: Save the active project context
        // when a plan is confirmed, so future sessions know what the user
        // was last working on. Total-switch safe: this code path is only
        // reachable when deepModeEnabled (PlanGate is gated on it).
        if deepModeEnabled {
            // Extract the first meaningful line of the plan as the project context.
            let firstLine = pendingPlanText.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty && !$0.hasPrefix("```") } ?? String(pendingPlanText.prefix(100))
            try? CrossSessionContextStore.setActiveProject(firstLine, sessionId: sessionId)
            logger.info("[CrossSession] C14: active project context saved")
        }
        planGateState = .idle
        selectedPathIndexes = []
        inputText = executionPrompt
        send()
        // [T-deep-mode-workflow] `send()` can early-return before committing
        // (context near/exhausted shows a dialog, read-only mode, still
        // processing). Only enter `.executing` when the message actually went
        // through — otherwise an "执行中" bar would linger with no real run.
        guard !showCompactBeforeSendPrompt && !showContextExhaustedPrompt else { return }
        beginExecution(restoring: capturedSteps)
    }

    /// [T-deep-mode-plan-gate] User wants to adjust the plan: park the plan
    /// text in the composer and close the gate. The user edits and sends it as
    /// a normal message. The workflow is reset — editing a plan is a return to
    /// the idle pre-task state, not an execution instruction.
    func editPlan() {
        guard case .awaitingApproval(let planText, _, _) = planGateState else { return }
        planGateState = .idle
        selectedPathIndexes = []
        resetWorkflow()
        inputText = planText
    }

    /// [T-deep-mode-plan-gate] Dismiss the pending plan without acting.
    func cancelPlan() {
        planGateState = .idle
        resetWorkflow()
    }

    // MARK: - Phase 2: ClarifyGate actions

    /// [T-deep-mode-clarify-gate] Skip the clarification step and proceed
    /// directly with the original request. Used when the user clicks "直接执行"
    /// on the clarification banner — they don't need to clarify, they just want
    /// the agent to make a reasonable guess and get on with it.
    func skipClarification() {
        guard case .awaitingClarification(_, let original) = clarifyState else { return }
        clarifyState = .idle
        inputText = original
        // Set a flag so send() knows to skip the ambiguity check this time.
        skipClarifyCheck = true
        send()
    }

    /// [T-deep-mode-clarify-gate] Cancel the pending clarification — close the
    /// banner, restore the original text to the composer, and do NOT send.
    func cancelClarification() {
        guard case .awaitingClarification(_, let original) = clarifyState else { return }
        clarifyState = .idle
        inputText = original
    }

    /// [T-deep-mode-clarify-gate] When true, send() skips the ambiguity check
    /// for the current message. Set by `skipClarification()` so the user can
    /// bypass the gate on demand. Reset to false after each send.
    /// Internal access (same as goalRunnerRoundsLeft / pendingGoalSentinel) so
    /// cross-file extensions (Persistence) can reset it on session load.
    var skipClarifyCheck = false

    /// [T-deep-mode-workflow] Reset the Phase 1 workflow state machine to its
    /// "off" shape: idle phase, no steps. Idempotent and safe to call even when
    /// deep mode is off — it is the single place that guarantees the toggle-off
    /// contract leaves zero residue.
    func resetWorkflow() {
        // [T-deep-mode-workflow] Cancel any pending fade-out so a delayed reset
        // from a previously completed workflow can't wipe a new run's state.
        // (Was previously only done in beginExecution(); resetWorkflow is the
        // canonical "return to idle" entry point so it should own this cleanup.)
        workflowFinishTask?.cancel()
        // [T-deep-mode-workflow] Audit M2: defensively clear the activity
        // indicator here too — this is the canonical "return to idle" entry
        // point, so it must not leave a stale busy pulse behind.
        workflowBusy = false
        // [T-deep-mode-resume-opt] Clear saved state on reset
        savedWorkflowState = nil
        workflowPhase = .idle
        workflowSteps = []
        // [T-deep-mode-floating-panel] Multi-path selection is per-workflow:
        // clear it on reset so a choice can never bleed into the next run.
        selectedPathIndexes = []
        // [T-deep-mode-verify-gate] Phase 2: verify budget and sentinel are
        // also per-workflow; resets alongside the workflow state machine.
        verifyRoundsLeft = VerifyGate.maxVerifyRounds
        pendingVerifySentinel = nil
        // [T-deep-mode-phase-f] Phase F spec state is per-workflow; clear it on
        // reset so a prior run's review / sentinel can't bleed into the next.
        specGateState = .idle
        pendingSpecFiles = []
        pendingSpecSentinel = false
        specEditRoundsLeft = SpecGate.maxEditRounds
        // [fix] Also clear the goal sentinel for consistency. While callers
        // already re-check deepModeEnabled / message errors before reading it,
        // leaving a stale sentinel across a reset is a latent hazard if a
        // future caller forgets the guard.
        pendingGoalSentinel = nil
    }

    /// [T-deep-mode-workflow] Enter the executing phase and light up the first
    /// pending step. Gated on the master switch: if deep mode is somehow off,
    /// fall back to a hard reset so the state machine can never run unbounded.
    /// Also falls back when the plan parsed zero recognizable steps — there is
    /// nothing to track, so we stay idle rather than render an empty "0/0" bar.
    private func beginExecution(restoring steps: [WorkflowStep]) {
        guard deepModeEnabled, !steps.isEmpty else {
            resetWorkflow()
            return
        }
        // [T-deep-mode-workflow] A fresh execution invalidates any pending fade
        // from a previous completed task, so a stale delayed reset can never
        // wipe the new run's tracker.
        workflowFinishTask?.cancel()
        // [T-deep-mode-cognitive-p1] C7: Reset the retrospective flag for the
        // new workflow — each workflow gets one retrospective at completion.
        retrospectiveHasRun = false
        // [T-deep-mode-cognitive-p1] C7 fix: Also clear isRetrospectiveRunning
        // in case a previous retrospective was interrupted mid-execution.
        isRetrospectiveRunning = false
        workflowPhase = .executing
        var s = steps
        if let i = s.firstIndex(where: { $0.status == .pending }) {
            s[i].status = .active
        }
        workflowSteps = s
    }

    /// [T-deep-mode-workflow] Advance the step tracker by one: mark the current
    /// active step done and promote the next pending step to active. Coarse but
    /// deterministic heuristic — each goal-runner auto-continue round is treated
    /// as roughly one plan step. Never advances outside the executing phase and
    /// never beyond the parsed step list.
    private func advanceWorkflowStep() {
        guard workflowPhase == .executing, !workflowSteps.isEmpty else { return }
        var steps = workflowSteps
        if let activeIdx = steps.firstIndex(where: { $0.status == .active }) {
            steps[activeIdx].status = .done
        }
        if let nextIdx = steps.firstIndex(where: { $0.status == .pending }) {
            steps[nextIdx].status = .active
        }
        workflowSteps = steps
    }

    /// [T-deep-mode-session-workflow] Advanced event-level progress refresh.
    /// Called once per completed tool result (in the batch stitch loop) so a
    /// long multi-tool step advances the capsule in near-real time instead of
    /// reading as a frozen "0/x".
    ///
    /// Guard guarantees we NEVER flip the last remaining step to `.done` via a
    /// tool event:
    ///   * `workflowPhase == .executing` (same guard as `advanceWorkflowStep`),
    ///   * `sessionWorkflowEnabled` (master switch AND rollback switch, so this
    ///     refinement is also a graceful lever that can be turned off),
    ///   * more than one non-done step remains (if only one is left, this is a
    ///     no-op).
    /// Final completion of the last step stays owned by the `.done` sentinel →
    /// `completeWorkflow`, so the `.verifying` entry is never triggered by tool
    /// events alone and GoalCompletionEvaluator cannot see a spurious all-done.
    private func advanceStepOnToolEvent() {
        guard sessionWorkflowEnabled,
              workflowPhase == .executing,
              workflowSteps.filter({ $0.status != .done }).count > 1 else { return }
        advanceWorkflowStep()
    }

    /// [T-deep-mode-workflow] Clear the tracker when an execution turn stops on
    /// its own (no continuation signal, or the auto-continue cap is reached).
    /// No-op unless a workflow is actually executing, so it can't disturb the
    /// planning gate or a trivial `.idle` turn.
    private func finishWorkflow() {
        guard workflowPhase == .executing else { return }
        workflowFinishTask?.cancel()
        resetWorkflow()
    }

    /// [T-deep-mode-workflow] Task fully done (`done` sentinel): flip every step
    /// to `.done` and enter the `.verifying` phase. In Phase 1 this was a brief
    /// fade-out; in Phase 2 it is a real self-check phase — the client injects
    /// a mandatory verify prompt and the model must confirm with
    /// `<<VERIFY_STATE>> passed` before the workflow actually finishes.
    private func completeWorkflow() async {
        guard workflowPhase == .executing else {
            resetWorkflow()
            return
        }
        var steps = workflowSteps
        for i in steps.indices { steps[i].status = .done }
        workflowSteps = steps
        workflowPhase = .verifying
        // [T-deep-mode-verify-gate] Phase 2: kick off the self-verification
        // round. If verify budget is already exhausted, fall back to the
        // Phase 1 behavior (instant finish) — zero blockage, zero risk.
        guard verifyRoundsLeft > 0 else {
            // [T-deep-mode-s2-1] Log warning when verification budget is exhausted
            logger.warning("[VerifyGate] verify budget exhausted — finishing without verification (S2-1)")
            logger.info("[VerifyGate] verify budget exhausted — finishing without verification")
            scheduleWorkflowFinish()
            return
        }
        await beginVerification()
    }

    /// [T-deep-mode-verify-gate] Phase 2: inject a self-verification prompt
    /// and recurse into `runAgentLoop()`. The model is asked to re-read its
    /// results, run/preview/compare, and report `passed` or `failed`.
    /// Gated on `deepModeEnabled` at the call-site; this method assumes the
    /// caller already checked.
    private func beginVerification() async {
        guard deepModeEnabled else { return }
        guard workflowPhase == .verifying else { return }
        verifyRoundsLeft -= 1
        let used = VerifyGate.maxVerifyRounds - verifyRoundsLeft
        logger.info("[VerifyGate] beginning self-verification \(used)/\(VerifyGate.maxVerifyRounds)")

        let cont = AgentMessage(role: .user, parts: [
            .text("<system-reminder>深度模式自检阶段：执行已完成，请现在严格复查你的工作。请重新阅读所有改动的文件、运行或预览结果、对照原始需求检查是否完全正确。如果一切正常，回复 <<VERIFY_STATE>> passed；如果发现问题，说明问题在哪里、为什么错、以及如何修复，并回复 <<VERIFY_STATE>> failed: <问题简述>。不要输出新的计划块，直接开始复查。</system-reminder>")
        ])
        let ci = agentHistory.count
        agentHistory.append(cont)
        if let pid = await persistAgentMessage(cont), ci < agentHistory.count {
            agentHistory[ci].dbMessageId = pid
        }

        do {
            try await runAgentLoop()
        } catch is CancellationError {
            logger.info("[VerifyGate] verification cancelled")
            handleUserCancelledCleanup()
        } catch {
            logger.error("[VerifyGate] verification error: \(String(describing: error))")
        }
    }

    /// [T-deep-mode-verify-gate] Phase 2: process the result of a verification
    /// turn. Called at turn end when `workflowPhase == .verifying`.
    ///   • `passed` → schedule the finish fade-out (workflow truly done).
    ///   • `failed` → re-enter `.executing` so the model can fix the issues.
    ///   • no sentinel / unknown → treat as passed (fail-safe: don't block).
    private func maybeProcessVerifyResult(afterMsgIdx msgIdx: Int) async {
        logger.info("[WorkflowLog] maybeProcessVerifyResult() - workflowPhase=verifying pendingSentinel=(pendingVerifySentinel != nil ? String(describing: pendingVerifySentinel!) : \"nil\")")
        guard deepModeEnabled else { return }
        guard workflowPhase == .verifying else { return }
        guard messages.indices.contains(msgIdx) else { return }
        guard messages[msgIdx].error == nil else {
            logger.info("[VerifyGate] skipped — turn has error")
            scheduleWorkflowFinish()
            return
        }
        guard !canResume else {
            logger.info("[VerifyGate] skipped — turn resumable")
            scheduleWorkflowFinish()
            return
        }

        guard let result = pendingVerifySentinel else {
            // [T-deep-mode-verify-gate] Fail-safe: no sentinel or unrecognized
            // token → treat as passed and finish. This degrades gracefully to
            // Phase 1 behavior instead of blocking the user.
            // [T-deep-mode-s1-2] Log warning when sentinel is missing
            logger.warning("[VerifyGate] no verify sentinel — treating as passed (fail-safe) — possible missed verification round")
            logger.info("[VerifyGate] no verify sentinel — treating as passed (fail-safe)")
            scheduleWorkflowFinish()
            return
        }

        switch result {
        case .passed:
            logger.info("[VerifyGate] verification passed")
            // [T-deep-mode-phase-f] If Spec mode is live, verification passing
            // no longer finishes immediately — enter the spec-writing phase so
            // the model formalizes the work into spec docs for user review.
            // Otherwise keep the original behavior (finish now).
            if specActive {
                await beginSpecWriting()
            } else {
                scheduleWorkflowFinish()
            }
        case .failed(let reason):
            if verifyRoundsLeft > 0 {
                // [T-deep-mode-s2-2] Log coupling state between VerifyGate and GoalRunner
                logger.info("[VerifyGate] verification failed — re-entering execution to fix (rounds left: \(verifyRoundsLeft), goalRoundsLeft: \(goalRunnerRoundsLeft))")
                logger.info("[VerifyGate] verification failed — re-entering execution to fix (rounds left: \(verifyRoundsLeft))")
                // Flip the last step back to active so the progress tracker
                // shows "still working" instead of "all done".
                workflowPhase = .executing
                var steps = workflowSteps
                if let lastDoneIdx = steps.lastIndex(where: { $0.status == .done }) {
                    steps[lastDoneIdx].status = .active
                }
                workflowSteps = steps
                // [T-deep-mode-verify-gate] Top up the GoalRunner budget by 1
                // if it's exhausted, so the fix round has at least one continue
                // available. Without this, a task that used all 3 goal rounds
                // before "falsely reporting done" would be stuck after verify
                // failure — the model would output pending but couldn't continue.
                if goalRunnerRoundsLeft <= 0 {
                    goalRunnerRoundsLeft = 1
                    logger.info("[VerifyGate] topped up goalRunner budget to 1 for fix round")
                }
                // Inject a "fix it" continue prompt and recurse.
                // [T-deep-mode-cognitive-p2-c13] Instead of a plain "fix it"
                // prompt, inject a root-cause analysis prompt that asks the
                // model to: (1) analyze the fundamental reason for failure,
                // (2) fix it, (3) generate a reusable avoidance rule wrapped
                // in <<ROOT_CAUSE_RULE>> sentinels. After the fix turn
                // completes, the rule is extracted and appended to
                // deep-rules.md. Total-switch safe: only reachable when
                // deepModeEnabled (guard at maybeProcessVerifyResult entry).
                let fixReason = reason ?? "发现问题需要修复"
                let cont = AgentMessage(role: .user, parts: [
                    .text(ErrorRootCauseAnalyzer.rootCausePrompt(failureReason: fixReason))
                ])
                let ci = agentHistory.count
                agentHistory.append(cont)
                if let pid = await persistAgentMessage(cont), ci < agentHistory.count {
                    agentHistory[ci].dbMessageId = pid
                }
                do {
                    try await runAgentLoop()
                    // [T-deep-mode-cognitive-p2-c13] After the fix turn
                    // completes, extract the root-cause rule from the
                    // model's last assistant response and append it to
                    // deep-rules.md. The rule is wrapped in
                    // <<ROOT_CAUSE_RULE>> sentinels. Total-switch safe:
                    // only reachable when deepModeEnabled.
                    if let lastMsg = messages.last,
                       case .text = lastMsg.blocks.last?.kind,
                       let lastText = lastMsg.blocks.last?.content,
                       let rule = ErrorRootCauseAnalyzer.extractRule(from: lastText) {
                        ErrorRootCauseAnalyzer.appendAutoRule(rule)
                        logger.info("[RootCauseAnalyzer] C13: extracted and appended auto-rule: \(rule.prefix(80))")
                    }
                } catch is CancellationError {
                    logger.info("[VerifyGate] fix-round cancelled")
                    handleUserCancelledCleanup()
                } catch {
                    logger.error("[VerifyGate] fix-round error: \(String(describing: error))")
                }
            } else {
                logger.info("[VerifyGate] verification failed but out of rounds — finishing anyway")
                scheduleWorkflowFinish()
            }
        }
    }

    /// [T-deep-mode-workflow] Schedule the fade-out of a completed tracker after
    /// a short delay. Cancels any prior pending fade first so repeated completion
    /// can't schedule duplicate mutations. The `deepModeEnabled` re-check at fire
    /// time guarantees the toggle-off contract isn't violated by a stray delay.
    private func scheduleWorkflowFinish() {
        workflowFinishTask?.cancel()
        workflowFinishTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            guard let self, self.deepModeEnabled else { return }
            self.resetWorkflow()
            // [T-deep-mode-cognitive-p1] C7 fix: Wait for the main agent loop
            // to fully finish before running the retrospective. The 900ms delay
            // above usually suffices, but if the loop is still cleaning up
            // (error handling, DB writes, queued prompts), isProcessing would
            // still be true — calling runAgentLoop() again would cause
            // reentrancy. Wait up to 5 seconds for the loop to release, then
            // proceed. If it doesn't release (stuck), skip the retrospective
            // for this workflow — the retrospectiveHasRun flag ensures we
            // don't double-run on the next finish.
            var waitCount = 0
            while self.isProcessing && waitCount < 50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                waitCount += 1
            }
            if self.isProcessing {
                logger.warning("[Retrospective] C7 skipped — isProcessing still true after 5s wait")
                return
            }
            await self.maybeRunRetrospective()
        }
    }

    // MARK: - Phase F: Spec Writing & Review flow

    /// [T-deep-mode-phase-f] Enter the spec-writing phase after verification
    /// passes (only when Spec mode is live). Injects a spec-generation prompt
    /// and recurses into `runAgentLoop()` so the model can write spec.md /
    /// checklist.md / tasks.md and append `<<SPEC_STATE>>`. Fail-safe: if the
    /// gate guard fails, fall back to a normal workflow finish (zero blockage).
    private func beginSpecWriting() async {
        guard specActive else { scheduleWorkflowFinish(); return }
        guard workflowPhase == .verifying else { scheduleWorkflowFinish(); return }
        workflowPhase = .specWriting
        pendingSpecSentinel = false
        pendingSpecFiles = []
        specEditRoundsLeft = SpecGate.maxEditRounds
        logger.info("[SpecGate] Phase F — entered spec-writing")
        let cont = AgentMessage(role: .user, parts: [
            .text("<system-reminder>深度模式规格化阶段：你刚刚完成执行并通过自检。现在请把已完成的成果正式化为一套规格文档。用 file_write（create_dirs=true）写出三个文件：spec.md（目标 / 范围内外 / 功能清单 / 验收标准）、checklist.md（对照验收标准的检查清单）、tasks.md（任务拆分，独立的可并行任务用 [PARALLEL] 标注）。直接基于你实际完成的工作来写，不要发明新的需求。三个文件都写完、且只用这一个回复序完成后，在回复最末尾另起一行补上：\n<<SPEC_STATE>>\n本阶段只写这三份规格文档，不要开始任何新的执行工作。</system-reminder>")
        ])
        let ci = agentHistory.count
        agentHistory.append(cont)
        if let pid = await persistAgentMessage(cont), ci < agentHistory.count {
            agentHistory[ci].dbMessageId = pid
        }
        do {
            try await runAgentLoop()
        } catch is CancellationError {
            logger.info("[SpecGate] spec-writing cancelled")
            handleUserCancelledCleanup()
        } catch {
            logger.error("[SpecGate] spec-writing error: \(String(describing: error))")
        }
    }

    /// [T-deep-mode-phase-f] Process the end of a spec-writing turn. Called at
    /// turn end when `workflowPhase == .specWriting`. Harvests the produced
    /// spec files and, on the sentinel or with detected docs, pauses in
    /// `.specReviewing` for the user's approve / edit / reject.
    ///   • sentinel present / docs detected → enter `.specReviewing`.
    ///   • no sentinel and no docs (or a failed / resumable turn) → fail-safe
    ///     finish so the capsule never hangs.
    private func maybeProcessSpecResult(afterMsgIdx msgIdx: Int) async {
        logger.info("[WorkflowLog] maybeProcessSpecResult() - workflowPhase=\(workflowPhase)")
        guard specActive else { return }
        guard workflowPhase == .specWriting else { return }
        guard messages.indices.contains(msgIdx),
              messages[msgIdx].error == nil,
              !canResume else {
            scheduleSpecFinishFallback()
            return
        }

        let detected = SpecGate.detectFiles(in: messages[msgIdx].blocks)
        if !detected.isEmpty {
            pendingSpecFiles = detected
            specGateState = .awaitingReview(files: detected)
            workflowPhase = .specReviewing
            logger.info("[SpecGate] spec docs produced (\(detected.count)) — awaiting review")
        } else if pendingSpecSentinel {
            // Sentinelled but no product files captured; still let the user
            // review the (possibly persisted) docs rather than block silently.
            specGateState = .awaitingReview(files: [])
            workflowPhase = .specReviewing
            logger.info("[SpecGate] spec sentinel present but no docs detected — awaiting review")
        } else {
            // No sentinel and no files: the spec turn produced nothing useful.
            logger.warning("[SpecGate] no spec docs and no sentinel — finishing (fail-safe)")
            scheduleSpecFinishFallback()
        }
    }

    /// [T-deep-mode-phase-f] Fail-safe finish when a spec-writing turn cannot
    /// proceed (error, resumable, or produced nothing). Clears spec state and
    /// finishes the workflow instead of hanging the capsule.
    private func scheduleSpecFinishFallback() {
        specGateState = .idle
        pendingSpecFiles = []
        pendingSpecSentinel = false
        scheduleWorkflowFinish()
    }

    /// [T-deep-mode-phase-f] User approved the generated spec docs. Transition
    /// through `.specApproved` and finish the workflow.
    func specApprove() {
        guard specActive else { return }
        guard workflowPhase == .specReviewing else { return }
        specGateState = .approved
        workflowPhase = .specApproved
        pendingSpecFiles = []
        pendingSpecSentinel = false
        logger.info("[SpecGate] user approved spec — finishing workflow")
        scheduleWorkflowFinish()
    }

    /// [T-deep-mode-phase-f] User wants to edit / regenerate the spec docs.
    /// Bounded by `specEditRoundsLeft`. Re-injects the spec prompt and
    /// re-enters writing. When the budget is exhausted, treat as approved.
    func specEdit() {
        guard specActive else { return }
        guard workflowPhase == .specReviewing else { return }
        guard specEditRoundsLeft > 0 else { specApprove(); return }
        specEditRoundsLeft -= 1
        specGateState = .idle
        pendingSpecSentinel = false
        workflowPhase = .specWriting
        logger.info("[SpecGate] user requested spec edit (rounds left: \(specEditRoundsLeft))")
        Task { await injectSpecEditPromptAndRun() }
    }

    /// [T-deep-mode-phase-f] User rejected the spec / wants to abandon Spec
    /// mode for this workflow. Finish without further execution (docs stay on
    /// disk if they were written, but the workflow closes).
    func specReject() {
        guard specActive else { return }
        guard workflowPhase == .specReviewing else { return }
        specGateState = .idle
        pendingSpecFiles = []
        pendingSpecSentinel = false
        logger.info("[SpecGate] user rejected spec — finishing workflow")
        resetWorkflow()
    }

    /// [T-deep-mode-phase-f] Inject an edit prompt for the spec docs and recurse
    /// into `runAgentLoop()`. Reuses the same sentinel contract.
    private func injectSpecEditPromptAndRun() async {
        guard specActive, workflowPhase == .specWriting else {
            scheduleWorkflowFinish()
            return
        }
        let cont = AgentMessage(role: .user, parts: [
            .text("<system-reminder>规格文档需要修改。请根据用户刚才的修改意见，用 file_write 重新写入需要调整的 spec.md / checklist.md / tasks.md，然后在这个回复最末尾另起一行补上：\n<<SPEC_STATE>>\n（本阶段只写规格文档，不要开始新的执行工作。）</system-reminder>")
        ])
        let ci = agentHistory.count
        agentHistory.append(cont)
        if let pid = await persistAgentMessage(cont), ci < agentHistory.count {
            agentHistory[ci].dbMessageId = pid
        }
        do {
            try await runAgentLoop()
        } catch is CancellationError {
            logger.info("[SpecGate] spec edit cancelled")
            handleUserCancelledCleanup()
        } catch {
            logger.error("[SpecGate] spec edit error: \(String(describing: error))")
        }
    }

    /// [T-deep-mode-workflow] Invoked on a master-switch change. When deep mode
    /// is now OFF, tear down every Phase 1 / deep-mode UI state so the UI and
    /// behavior return byte-for-byte to the pre-deep-mode shape. Non-destructive
    /// no-op when deep mode is ON.
    func deepModeDidDisableCleanup() {
        guard !deepModeEnabled else { return }
        workflowFinishTask?.cancel()
        planGateState = .idle
        resetWorkflow()
        goalRunnerRoundsLeft = GoalRunner.maxAutoRounds
        pendingGoalSentinel = nil
        // [T-deep-mode-clarify-gate] Phase 2: clarification gate also resets
        // immediately when the master switch goes off — no residual banner.
        clarifyState = .idle
        skipClarifyCheck = false
        // [T-deep-mode-cognitive-p1] C7: Clear the retrospective flag so it
        // doesn't carry over to a future deep-mode re-enable. Also clears the
        // C8 uncertainty flag for the same reason. Total-switch safe: both are
        // in-memory only and never persisted.
        retrospectiveHasRun = false
        isRetrospectiveRunning = false
        didInjectUncertaintyCheckThisRun = false
        // [T-deep-mode-perf-fragment-cache] Clear the cached deep-mode fragment
        // so nothing survives a toggle-off (cache re-keyed anyway, but explicit
        // for the total-switch contract).
        _cachedDeepModeFragment = nil
        _cachedDeepModeFragmentKey = nil
        _cachedRulesModTime = -1  // [T-perf-deepmode-modtime-ttl]
        _cachedRulesModTimeTS = 0
        // [T-deep-mode-cognitive-p2-c9] C9: Reset cognitive load state to
        // empty so no warning banner survives the off switch.
        cognitiveLoadState = .empty
        lastModelLoadSignal = nil
        // [T-deep-mode-cognitive-p2-c10] C10: Reset the need-more-context
        // state so no "needs input" prompt survives the off switch.
        needMoreContextState = nil
        // [T-deep-mode-cognitive-p2-c14] C14: Clear the active project pointer
        // in the cross-session store. Historical summaries are preserved
        // (passive data, no behavioral impact when deep mode is off).
        try? CrossSessionContextStore.clearActiveProject()
    }

    /// [T-deep-mode-goal-runner] Layer C hook, called exactly once per completed
    /// runAgentLoop turn (right after the per-block markdown cache). Reads the
    /// goal sentinel from the just-finished turn and, when deep mode is on and
    /// the sentinel says `pending`, injects a synthetic continue message and
    /// recurses into a fresh `runAgentLoop()` — bounded by `goalRunnerRoundsLeft`.
    ///
    /// Fail-safe and non-blocking by construction:
    ///   • no sentinel / unrecognized token → no-op (parse returns nil).
    ///   • plan gate still waiting → no-op (a plan is not an execution turn).
    ///   • errored or resumable turn → no-op (never auto-continue a broken turn).
    ///   • cap reached → reset budget and stop.
    private func maybeAutoContinueGoal(afterMsgIdx msgIdx: Int) async {
        guard deepModeEnabled else {
            goalRunnerRoundsLeft = GoalRunner.maxAutoRounds
            // [T-deep-mode-diagnose] Deep mode off is the #1 silent-skip cause.
            // One info line per turn makes it impossible to confuse "toggle off"
            // with a code deficiency again.
            logger.info("[GoalRunner] skipped — deep mode off")
            return
        }
        // [T-deep-mode-cognitive-p1] C7 fix: If the retrospective's runAgentLoop
        // is running, do NOT auto-continue — the review text might coincidentally
        // contain a <<GOAL_STATE>> sentinel, which would trigger an unintended
        // auto-continue chain inside the retrospective. The retrospective is a
        // single-turn reflection, not a new task execution. Clear any sentinel
        // that was parsed from the review text so it can't linger.
        if isRetrospectiveRunning {
            logger.info("[GoalRunner] skipped — retrospective in progress (C7 guard)")
            pendingGoalSentinel = nil
            return
        }
        // A pending plan is awaiting user confirmation — don't auto-continue.
        guard case .idle = planGateState else {
            logger.info("[GoalRunner] skipped — plan gate not idle (\(planGateState))")
            return
        }
        // [T-deep-mode-verify-gate] Phase 2: don't auto-continue during the
        // verification phase — that phase is driven by VerifyGate's own sentinel,
        // not GoalRunner's. A verify turn may incidentally mention goal state
        // (e.g. "still pending because I need to fix X") and we don't want that
        // to trigger a GoalRunner continue inside a verify round.
        guard workflowPhase != .verifying else {
            logger.info("[GoalRunner] skipped — in verifying phase (VerifyGate owns this turn)")
            return
        }
        guard messages.indices.contains(msgIdx) else {
            logger.warning("[GoalRunner] skipped — msgIdx \(msgIdx) out of range")
            return
        }
        if messages[msgIdx].error != nil {
            logger.info("[GoalRunner] skipped — turn has error")
            return
        }
        if canResume {
            logger.info("[GoalRunner] skipped — turn resumable (truncated at tool limit)")
            return
        }
        if userDidCancel {
            logger.info("[GoalRunner] skipped — user cancelled")
            return
        }
        if Task.isCancelled {
            logger.info("[GoalRunner] skipped — task cancelled")
            return
        }

        // [T-deep-mode-strip-sentinel] Read the result resolved at text-capture
        // time. The visible text was already stripped of the `<<GOAL_STATE>>`
        // line before flush/persist, so re-parsing `block.content` here would
        // always miss it.
        guard let result = pendingGoalSentinel else {
            logger.info("[GoalRunner] skipped — no sentinel parsed")
            // [T-deep-mode-workflow] No continuation signal: the execution turn
            // ended on its own. Clear the tracker so it can't linger as "执行中".
            // [T-deep-mode-verify-gate] Phase 2: but don't clear during verifying —
            // that phase has its own lifecycle and shouldn't be wiped by the
            // absence of a goal sentinel (verify turns use the VERIFY sentinel).
            // [T-deep-mode-session-workflow] P1: before wiping, run the client
            // completion evaluator. If every parsed plan step is already done but
            // the model simply forgot to emit `<<GOAL_STATE>> done`, treat the
            // turn as complete (all-green + verifying) instead of hard-resetting
            // to idle — this is the fix for the "capsule disappears after the
            // last shell command" observation. Only when steps genuinely remain
            // (or there is no plan to complete) do we reset.
            if workflowPhase != .verifying {
                let verdict = GoalCompletionEvaluator.evaluate(
                    steps: workflowSteps,
                    broad: false,
                    roundsLeft: goalRunnerRoundsLeft
                )
                if workflowPhase == .executing, verdict == .passed {
                    await completeWorkflow()
                } else {
                    finishWorkflow()
                }
            }
            return
        }

        switch result {
        case .done:
            logger.info("[GoalRunner] done sentinel — resetting auto-continue budget")
            goalRunnerRoundsLeft = GoalRunner.maxAutoRounds
            // [T-deep-mode-session-workflow] P1: cross-check that a `done`
            // claim is credible. If a plan is being tracked and the client-side
            // evaluator says NOT all steps are done, don't trust a premature
            // `done` — nudge the model to finish the remaining steps instead of
            // wrapping early. (Deterministic stop-when-achieved; still bounded
            // by goalRunnerRoundsLeft so it can never loop forever.)
            let verdict = GoalCompletionEvaluator.evaluate(
                steps: workflowSteps,
                broad: false,
                roundsLeft: goalRunnerRoundsLeft
            )
            if workflowSteps.isEmpty {
                // No parsed plan → trust the model's `done` and wrap up.
                await completeWorkflow()
            } else if verdict == .passed {
                // [T-deep-mode-workflow] Task complete: show an all-green completion
                // for a beat, then fade the tracker out (no lingering residue).
                await completeWorkflow()
            } else {
                // Steps remain but model claims done — ask it to keep going once
                // more rather than accepting an incomplete task. Bounded: after
                // decrementing, if budget hit 0 we stop and finish anyway.
                goalRunnerRoundsLeft -= 1
                advanceWorkflowStep()
                let used = GoalRunner.maxAutoRounds - goalRunnerRoundsLeft
                logger.info("[GoalRunner] done claimed but steps remain — continue \(used)/\(GoalRunner.maxAutoRounds)")
                let next = "你在上一条回复中标记任务已完成，但仍有计划步骤尚未执行。请继续完成剩余步骤，全部完成后以 <<GOAL_STATE>> done 结束本回合。"
                let cont = AgentMessage(role: .user, parts: [
                    .text("<system-reminder>深度模式自动续跑：\(next)</system-reminder>")
                ])
                let ci = agentHistory.count
                agentHistory.append(cont)
                do {
                    try await runAgentLoop()
                } catch is CancellationError {
                    logger.info("[GoalRunner] auto-continue (post-done) cancelled")
                    handleUserCancelledCleanup()
                } catch {
                    logger.error("[GoalRunner] auto-continue (post-done) error: \(String(describing: error))")
                }
            }
        // [T-deep-mode-cognitive-p2-c10] Dynamic autonomy exit: the model
        // proactively asks for user input instead of guessing. Stop the
        // auto-continuation loop, surface the reason, and wait for the user.
        case .needMoreContext(let reason):
            logger.info("[GoalRunner] need_more_context sentinel — stopping auto-continue, surfacing to user")
            goalRunnerRoundsLeft = GoalRunner.maxAutoRounds
            needMoreContextState = reason
            // The model's visible text already explains what it needs.
            // We just stop the loop — the user sees the message and can reply.
            finishWorkflow()
        case .pending(let reason):
            guard goalRunnerRoundsLeft > 0 else {
                logger.info("[GoalRunner] auto-continue cap reached — stopping this chain")
                goalRunnerRoundsLeft = GoalRunner.maxAutoRounds
                // [T-deep-mode-cognitive-p0] C5: Fail-switch — when the auto-continue
                // budget is exhausted (3 rounds used without reaching `done`), the
                // model has effectively "failed the same approach 3 times". Instead
                // of silently stopping, inject a fail-switch directive that tells the
                // model to try a fundamentally different strategy on the next user
                // interaction. This is a one-shot injected user message — it does
                // NOT auto-continue (we're out of budget); it only surfaces the
                // recommendation in the conversation so the user sees it and the
                // model's next turn is primed to switch approach.
                // Total-switch safe: this code path is already inside
                // `guard deepModeEnabled` at maybeAutoContinueGoal entry, and the
                // injected message is a normal AgentMessage — no new state, no
                // persistence, no UI.
                let failSwitchMsg = AgentMessage(role: .user, parts: [
                    .text("<system-reminder>深度模式认知提示（C5 失败切换）：已连续尝试 \(GoalRunner.maxAutoRounds) 轮未完成任务。请勿重复同一方法。下次执行时必须切换到完全不同的策略路径，并说明切换理由。如果当前路径是唯一可行路径，请说明为何前 \(GoalRunner.maxAutoRounds) 次未能成功，以及需要用户提供什么才能突破。</system-reminder>")
                ])
                let fci = agentHistory.count
                agentHistory.append(failSwitchMsg)
                // [T-perf-goalrunner-transient] Do NOT persist synthetic
                // fail-switch messages to the DB. They are only needed during
                // the active run; persisting them bloats agentHistory on
                // session reload, causing estimateContextTokens O(n) stalls
                // and loadSession delays. The continuation state
                // (goalRunnerRoundsLeft) is reset on reload, so these messages
                // are useless after reload and only add to context bloat.
                // [T-deep-mode-workflow] Stopping without a `done` sentinel:
                // clear the tracker so it can't linger as "执行中".
                finishWorkflow()
                return
            }
            goalRunnerRoundsLeft -= 1
            // [T-deep-mode-workflow] Each auto-continue round advances the step
            // tracker one position so the user sees live progress.
            advanceWorkflowStep()
            let used = GoalRunner.maxAutoRounds - goalRunnerRoundsLeft
            logger.info("[GoalRunner] pending sentinel — auto-continue \(used)/\(GoalRunner.maxAutoRounds)")

            // Synthetic continue turn: lives only in agentHistory, produces no
            // user bubble (the `<system-reminder>` prefix makes isUserBubbleEntry
            // treat it as non-visible). Mirrors resume()'s stop-continue message.
            let next = reason ?? "继续完成剩余步骤"
            let cont = AgentMessage(role: .user, parts: [
                .text("<system-reminder>深度模式自动续跑：目标尚未完成。\(next)。请继续执行剩余步骤，不要重复已完成的工作；全部完成后以 <<GOAL_STATE>> done 结束本回合。</system-reminder>")
            ])
            let ci = agentHistory.count
            agentHistory.append(cont)
            // [T-perf-goalrunner-transient] Do NOT persist synthetic
            // auto-continuation messages to the DB. They are only needed
            // during the active run for the agent loop; persisting them bloats
            // agentHistory on session reload, compounding estimateContextTokens
            // O(n) traversal cost and loadSession DB-query overhead. The
            // continuation state (goalRunnerRoundsLeft) is reset to
            // maxAutoRounds on reload, so a persisted continuation message
            // without the matching round state would be an orphan that the
            // model can't act on — it just inflates the context window.

            // Recurse: the next runAgentLoop() reuses every existing backstop —
            // maxAgentTurns per round, ToolLoopDetector, in-loop compaction.
            // Bounded by goalRunnerRoundsLeft, so this cannot loop forever.
            do {
                try await runAgentLoop()
            } catch is CancellationError {
                logger.info("[GoalRunner] auto-continue cancelled")
                handleUserCancelledCleanup()
            } catch {
                logger.error("[GoalRunner] auto-continue error: \(String(describing: error))")
                // Never wedge the turn: swallow and stop continuing.
            }
        }
    }
    /// only the rules that are relevant to the current turn.
    // [T-perf-scope-cache] Cache for buildDeepModeScopeContext() result.
    // The scope context depends on the last user message + recent 10 messages'
    // file path mentions. Between send() and runAgentLoop entry, messages don't
    // change, so the cache hits and skips the regex traversal.
    var _cachedScopeContext: DeepModeScopeContext?
    var _cachedScopeLastUserMessage: String = ""

    /// [T-deep-mode-perf-fragment-cache] Cache for the computed
    /// `deepModeFragment` string (the large multi-KB deep-agent behavior
    /// fragment). It is recomputed on every send/resume/fallback/auto-continue
    /// turn today (AIChatViewModel.swift deepModeFragment), hitting expensive
    /// paths (scope-context regex traversal + rule glob NSPredicate builds +
    /// multi-KB string concat) each time. Caching it keyed on its true inputs
    /// (level + memory flag + scope signature + rules file mod-time) makes all
    /// the within-turn recomputations O(1) cache hits.
    ///
    /// Total-switch safe: this cache is only ever READ inside `deepModeFragment`,
    /// which is only invoked under `if deepModeEnabled`. When the switch is off
    /// the fragment is never read and the cache is never touched; we additionally
    /// clear it in `deepModeDidDisableCleanup()` so no state survives a toggle-off.
    var _cachedDeepModeFragment: String?
    var _cachedDeepModeFragmentKey: String?
    /// [T-perf-deepmode-modtime-ttl] TTL-cached rules file mod time. The old code
    /// called DeepModeStore.rulesFileModTime() (a file system stat) on every
    /// single deepModeFragment access — including cache hits — adding I/O latency
    /// to the main thread. We now cache the result for 2 seconds, so the 3–8
    /// inference calls within a turn only stat the file once.
    var _cachedRulesModTime: Double = -1
    var _cachedRulesModTimeTS: CFAbsoluteTime = 0

    private func buildDeepModeScopeContext() -> DeepModeScopeContext {
        // [T-perf-scope-cache] Return cached result when the last user message
        // hasn't changed (same send flow → same scope context → no recomputation).
        let lastUserMessage = messages
            .last(where: { $0.role == .user })?.content ?? ""

        if let cached = _cachedScopeContext,
           lastUserMessage == _cachedScopeLastUserMessage {
            return cached
        }

        // Extract file paths from recent messages (last 10 messages)
        let recentMessages = messages.suffix(10)
        var mentionedPaths: Set<String> = []
        for msg in recentMessages {
            let paths = Self.extractFilePaths(from: msg.content)
            mentionedPaths.formUnion(paths)
            // Also extract from assistant blocks (tool_use descriptions, etc.)
            for block in msg.blocks {
                let blockPaths = Self.extractFilePaths(from: block.content)
                mentionedPaths.formUnion(blockPaths)
            }
        }

        let ctx = DeepModeScopeContext(
            mentionedFilePaths: Array(mentionedPaths),
            userInputLowercased: lastUserMessage.lowercased()
        )
        _cachedScopeContext = ctx
        _cachedScopeLastUserMessage = lastUserMessage
        return ctx
    }

    // [T-deep-mode-scope-perf] Precompiled regexes — compiled ONCE per process.
    //
    // Before: the bare-filename scan looped over 41 extensions and called
    // `NSRegularExpression(pattern:)` INSIDE the loop on every invocation, then
    // ran each of those 42 regexes over the full text. Because
    // `buildDeepModeScopeContext()` runs this over the last 10 messages and
    // every block inside them, one scope build performed thousands of ICU regex
    // compilations plus thousands of full-text scans — measured as 1.2-4.5s of
    // main-thread hang in long DeepMode sessions (HangDetector stack:
    // extractFilePaths <- buildDeepModeScopeContext <- deepModeFragment).
    //
    // Now: one alternation covers all extensions, so a scan costs 2 regexes
    // (0 compilations) instead of 42 compilations + 42 scans.
    private static let slashPathRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"[^\s]*/[^\s]*"#, options: [])

    private static let bareFilenameRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"[\w\-.]+\.(?:markdown|storyboard|swiftpm|podspec|bash|zsh|swift|tsx|jsx|scss|html|yaml|toml|json|plist|php|css|xml|yml|ini|cfg|txt|env|java|cpp|hpp|sql|xib|rb|go|rs|sh|ts|js|py|kt|mm|md|m|c|h)\b"#,
        options: [.caseInsensitive])

    /// Upper bound on how much of a single text is scanned for file paths.
    /// DeepMode tool results routinely reach hundreds of KB; paths buried deep
    /// in a giant log dump are useless for rule scoping, and scanning them made
    /// the cost scale with accumulated output size — so it got worse the longer
    /// a session ran.
    private static let maxPathScanCharacters = 8_192

    /// Extract potential file paths / filenames from text using heuristics.
    /// Matches:
    ///   - Paths containing slashes: /foo/bar.swift, src/main.py
    ///   - Bare filenames with known extensions: file.swift, script.py
    private static func extractFilePaths(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var paths: Set<String> = []

        // [T-deep-mode-scope-perf] Only scan a bounded prefix. DeepMode tool
        // results can be hundreds of KB; without this cap the cost of a scope
        // build scaled with accumulated output size, so it degraded the longer
        // a session ran.
        let scanned: String
        if text.count > Self.maxPathScanCharacters {
            scanned = String(text.prefix(Self.maxPathScanCharacters))
        } else {
            scanned = text
        }
        guard !scanned.isEmpty else { return [] }

        let nsRange = NSRange(scanned.startIndex..., in: scanned)

        // Pattern 1: paths with slashes (e.g. /a/b/c.swift, src/foo/bar.py)
        // Match sequences of non-whitespace that contain at least one /
        // and end with a known extension or a filename-like component.
        Self.slashPathRegex?.enumerateMatches(in: scanned, options: [], range: nsRange) { match, _, _ in
            guard let match = match,
                  let range = Range(match.range, in: scanned) else { return }
            var path = String(scanned[range])
            // Trim trailing punctuation that's unlikely to be part of a path
            while path.last?.isPunctuation == true && path.last != "/" && path.last != "." {
                path.removeLast()
            }
            if !path.isEmpty {
                paths.insert(path)
            }
        }

        // Pattern 2: bare filenames with common code extensions.
        // One combined regex (see bareFilenameRegex) replaces the previous
        // per-extension loop that recompiled 41 regexes on every call.
        Self.bareFilenameRegex?.enumerateMatches(in: scanned, options: [], range: nsRange) { match, _, _ in
            guard let match = match,
                  let range = Range(match.range, in: scanned) else { return }
            paths.insert(String(scanned[range]))
        }

        return Array(paths)
    }

    /// [T-deep-mode] Extra "deep agent" behavior fragment injected just before
    /// the memory footer when the global 深度龙虾Ai toggle is on. It upgrades
    /// the agent from the default "act immediately" posture to a
    /// plan → execute → verify loop modelled on TRAE's autonomous workflow,
    /// WITHOUT touching `baseSystemPrompt` (which sits on a type-check
    /// boundary and must not be edited).
    ///
    /// Phase 3 evolution: rules are scoped to the current conversation context
    /// (file paths mentioned + user input keywords) rather than always injecting
    /// the full rule set. This reduces token waste and keeps the prompt focused.
    ///
    /// [T-ios-orphan-scan-perf] Incremental orphan scan cursor. Tracks how far
    /// into agentHistory we have already verified tool-use/result pairing.
    /// On each runAgentLoop entry we only scan from this cursor forward,
    /// reducing O(n*m) to O(d*m) where d is the number of new messages
    /// since the last scan. Reset to 0 on resume (partial re-scan needed).
    var orphanScanCursor = 0

    /// [T-perf-orphan-incremental] Cumulative set of toolResult IDs from the
    /// clean prefix (0..<orphanScanCursor). The old code re-scanned the entire
    /// clean prefix for toolResult IDs on every send — twice (Phase 1 + Phase 2).
    /// This set lets us skip both prefix scans: we just merge it into the
    /// working set in O(1). Reset alongside orphanScanCursor.
    var orphanScanPrefixToolResultIds = Set<String>()

    private var deepModeFragment: String {
        // [T-deep-mode-perf-fragment-cache] Cache hit fast-path. The fragment
        // is a pure function of: deep-mode level, memory flag, the scope context
        // (itself cached/derived from the last user message), and the rules
        // file mod-time. When none of those changed since the last build, reuse
        // the cached string instead of re-running the scope regex traversal +
        // rule glob NSPredicate builds + multi-KB concat.
        let scopeCtx = buildDeepModeScopeContext()
        let level = deepModeLevel
        // [T-perf-deepmode-modtime-ttl] Only stat the rules file once every 2s.
        // The old code called rulesFileModTime() on every access — a file system
        // stat that blocked the main thread even on cache hits. Within a turn
        // (3–8 inference calls) the file can't change, so this is safe.
        let now = CFAbsoluteTimeGetCurrent()
        if now - _cachedRulesModTimeTS > 2.0 {
            _cachedRulesModTime = DeepModeStore.rulesFileModTime() ?? -1
            _cachedRulesModTimeTS = now
        }
        // [T-perf-deepmode-cachekey-hash] Use a hash of the user input instead
        // of the full text. The old key embedded the entire user message, which
        // made key comparison O(n) on every access. A hash is O(1) and captures
        // the same validity signal: different messages → different hash → miss.
        let inputHash = scopeCtx.userInputLowercased.hashValue
        let cacheKey = "\(level.rawValue)|\(memoryEnabled)|\(inputHash)|\(scopeCtx.mentionedFilePaths.joined())|\(_cachedRulesModTime)"
        if let cached = _cachedDeepModeFragment, _cachedDeepModeFragmentKey == cacheKey {
            return cached
        }
        var s = "\n\nDeep Agent Mode (深度龙虾Ai) is ENABLED (intensity: \(level.rawValue)). Adopt a deliberate, senior-engineer working style for this turn:\n"
        // [T-deep-mode-rules-phase3] Behavior rules are scoped to current context.
        // Phase 3: only rules matching the current scope (file globs + keywords
        // + alwaysApply) are injected, replacing the old flat full-list injection.
        s += DeepModeStore.rulesFragment(for: scopeCtx) + "\n"
        // [T-deep-mode-plan-gate] Layer B: deterministic plan-gate instruction.
        // For multi-step tasks the model must first emit ONLY a plan inside a
        // fenced ```plan``` code block and issue no tool calls; the client then
        // raises a confirm/edit bar and pauses execution until the user acts.
        // Trivial single-command tasks skip the plan and act immediately.
        s += "PLAN GATE — if a request needs more than one step, your FIRST reply must be ONLY a plan: a fenced ```plan``` code block listing numbered steps, with no tool calls. Stop there and wait for the user to confirm before executing anything. For a trivial single-command task, skip the plan and act immediately.\n"
        // [T-deep-mode-goal-runner] Layer C: deterministic goal sentinel. After
        // executing (a turn that used tools), the model appends exactly one
        // status line; the client auto-continues on `pending` until `done` or
        // the cap. Emitting nothing is always safe (no auto-continuation).
        s += "GOAL AUTO-CONTINUE — at the very END of a turn where you used tools, append exactly one line (and do NOT put other text after it):\n  • <<GOAL_STATE>> done   (the task is fully complete)\n  • <<GOAL_STATE>> pending: <one-line next step>   (still incomplete; the client will auto-continue)\n"
        // [T-deep-mode-verify-gate] Phase 2: deterministic self-verification.
        // When in the verification phase (client injected a verify prompt), the
        // model MUST re-read its own results, run / preview / compare them, and
        // append exactly one VERIFY_STATE line at the very end. The client uses
        // this to decide whether to finish the workflow or loop back to fix.
        s += "SELF-VERIFY — when the client asks you to verify your work, re-read all changed files, run/preview/test the results, and check against the original goal. At the very END of your reply append exactly one line:\n  • <<VERIFY_STATE>> passed   (everything works correctly, matches the requirements)\n  • <<VERIFY_STATE>> failed: <one-line summary of what's wrong + how to fix>   (issues found; the client will let you fix them)\n"
        // [T-deep-mode-memory-proactive-phase3] Phase 3: proactive memory with
        // categories. The agent should classify memories by type (preference /
        // convention / fact / taboo / project) when writing them.
        if memoryEnabled {
            s += "Additionally (fixed behavior, always on in deep mode): REMEMBER PROACTIVELY — at the end of this turn, if the user expressed a long-term preference, convention, project fact, or taboo worth keeping, persist it via memory_write with an appropriate category (preference/convention/fact/taboo/project) and mention it in a single line, rather than waiting to be asked."
        }
        // [T-deep-mode-cognitive-p0] Phase 4.5 P0: cognitive thinking abilities.
        // Five prompt-injected directives that make the agent "think more like a
        // human". All are pure prompt additions inside deepModeFragment, so the
        // master switch controls them implicitly — when deepModeEnabled is off,
        // deepModeFragment is never appended to the system prompt, and none of
        // these directives appear. Zero runtime state, zero UI, zero persistence.
        // These C1-C5 directives are included at ALL levels (low/medium/high).
        s += "\n"
        s += "COGNITIVE ABILITIES (think like a senior engineer, not just execute):\n"
        // C1: Three-layer intent decoding
        s += "1. THREE-LAYER INTENT — Before acting on a request, silently decode three layers: (a) What is the user literally asking? (b) What is the real underlying need behind this request? (c) After this is solved, what will the user likely ask next? Design your solution for layer (b), not just (a). If layers (a) and (b) conflict, address (b) and briefly explain why.\n"
        // C2: Reverse verification
        s += "2. ADVERSARIAL SELF-CHECK — After reaching a conclusion or producing output, actively search for evidence that could DISPROVE your solution. Try to break your own work: what edge case fails? What assumption might be wrong? Only if you cannot find a disproof is the conclusion reliable. State what you tried to break and why it held.\n"
        // C3: First-principles reasoning
        s += "3. FIRST PRINCIPLES — Do not rely on \"this worked last time\". For each non-trivial decision, reason from fundamental constraints (what the platform/language/runtime actually guarantees), not from pattern-matching prior solutions. Past success does not justify current reuse if the fundamentals have changed.\n"
        // C4: Proactive risk anticipation
        s += "4. PROACTIVE RISK FORESIGHT — Before the user asks, identify risks they haven't mentioned. If your plan has potential side effects, breaking changes, performance implications, or security concerns, surface them proactively in one line. Don't wait to be asked \"what could go wrong\" — tell the user first.\n"
        // C5: Fail-three-times-switch-method
        s += "5. FAIL-SWITCH — If the same approach fails 3 consecutive times (same error pattern or same dead-end), STOP and switch to a fundamentally different strategy. Do not attempt a 4th iteration of the same method. State: \"Approach X failed 3 times — switching to Y because Z.\" The auto-continue budget (3 rounds) exists for this: if you've used all 3 rounds without success, the next step must be a different approach, not a retry.\n"
        // [T-deep-mode-level] Medium/High only: C12 multi-path, C9 sentinel,
        // C10 need_more_context, C14 cross-session. Low level skips these
        // for a more natural, less sentinel-heavy conversation experience.
        if level.forcesMultiPath {
            // [T-deep-mode-cognitive-p2-c12] C12: Multi-path parallel thinking.
            s += "6. MULTI-PATH THINKING — When you produce a plan (fenced ```plan``` block), if the task is complex (more than 3 steps, or involves architecture/design decisions), generate AT LEAST 3 candidate paths. Format each path as:\n  ## PATH 1: <short title>\n  <numbered steps>\n  RISK: low|medium|high\n  ## PATH 2: <short title>\n  <numbered steps>\n  RISK: low|medium|high\n  ## PATH 3: <short title>\n  <numbered steps>\n  RISK: low|medium|high\n  RECOMMENDED: PATH <N>\n  Briefly explain why you recommend this path over the others (1-2 sentences). For trivial tasks (≤3 steps, no design decisions), use a standard single-path plan as before.\n"
        }
        if level.enablesRootCause {
            // [T-deep-mode-cognitive-p2-c13] C13: Error → root cause → strategy
            s += "7. ROOT CAUSE LEARNING — When verification fails and you receive a root-cause analysis prompt, do NOT just fix the surface symptom. Analyze the FUNDAMENTAL reason it went wrong (wrong assumption? missing step? platform constraint?), fix it, then produce a single reusable rule that would prevent this class of error. Wrap the rule in <<ROOT_CAUSE_RULE>> ... <<ROOT_CAUSE_RULE>> tags. The rule will be auto-saved to your behavior rules for future sessions.\n"
        }
        if level.forcesCognitiveLoadSentinel {
            // [T-deep-mode-cognitive-p2-c9] C9: Cognitive load real-time monitoring.
            s += "8. COGNITIVE LOAD MONITORING — At the END of each turn where you used tools, assess your cognitive load and append exactly one line:\n  • <<COGNITIVE_LOAD>> low    (on track, confident, context is clear)\n  • <<COGNITIVE_LOAD>> medium  (some complexity, but manageable)\n  • <<COGNITIVE_LOAD>> high: <one-line note>   (losing track, context getting long, multiple failures)\n  • <<COGNITIVE_LOAD>> critical: <one-line note>   (context near limit, severe confusion, need to step back)\n  Be honest — under-reporting load leads to degraded output quality. If the client also detects high load from its own metrics, it will warn the user.\n"
        }
        if level.enablesNeedMoreContext {
            // [T-deep-mode-cognitive-p2-c10] C10: Dynamic autonomy exit.
            s += "9. DYNAMIC AUTONOMY EXIT — If you are in an auto-continue loop and discover you need information you don't have (ambiguous requirements, missing file access, need a design decision only the user can make), do NOT guess. Instead emit:\n  • <<GOAL_STATE>> need_more_context: <one-line description of what you need>\n  The client will STOP the auto-continuation loop and surface your question to the user. This is preferable to 3 rounds of increasingly-wrong assumptions.\n"
        }
        if level.enablesCrossSession {
            // [T-deep-mode-cognitive-p2-c14] C14: Unified cross-mode context.
            s += "10. CROSS-SESSION CONTEXT — When you complete a meaningful workflow (not a trivial single-step task), append a one-line summary of what was accomplished. The client will persist this as cross-session context so future sessions can pick up where you left off. Also, when you start a new workflow, briefly state the current project context so the client can persist it as the active project.\n"
        }
        if level.registersSequentialThinking {
            // [T-deep-mode-cognitive-p2-c11] C11: On-demand sequential thinking.
            s += "11. ON-DEMAND SEQUENTIAL THINKING — You have a `sequential_thinking` tool. Call it when you encounter a sub-problem that genuinely needs structured multi-step deduction (architecture decisions, complex debugging, algorithm design). The tool returns a hypothesis→verification→conclusion framework you fill in. Do NOT call it for simple tasks (2-3 step problems). Do NOT call it as a replacement for planning — it's for mid-execution thinking when you hit a wall or a fork in the road. If your cognitive load is high, the tool will suggest fewer steps to keep you focused.\n"
        }
        // [T-deep-mode-skill-accumulate] Phase B B2: Skill accumulation hint.
        // Teaches the model to notice a RECURRING task pattern and propose a
        // reusable skill, instead of only acting on explicit skill requests.
        // Pure prompt addition inside deepModeFragment — fully governed by
        // the master switch (never injected when deep mode is off).
        s += "13. SKILL ACCUMULATION — If about the 3rd time in this session you're handling the SAME type of task (a recurring workflow: producing a docx report, generating a slide deck, the same class of code fix), that workflow is a candidate for a reusable skill. Mention it to the user in one line and offer to create one using the skill format. Do NOT propose a skill on the first or second occurrence — only when a reliable pattern has clearly emerged.\n"
        // [T-deep-mode-phase-d] Phase D: Inline-visualization guidance. Teaches
        // the model when and how to use the render_widget tool. Pure prompt
        // addition inside deepModeFragment — governed by the master switch.
        s += "14. VISUALIZATION — You have a `render_widget` tool that renders an SVG diagram/chart or an isolated HTML widget INLINE in the chat (not saved as a file). Use it when a visual communicates better than prose: for flowcharts and architecture/sequence diagrams, comparison tables, small data charts, or interactive demos. Provide well-formed inline SVG for 'diagram'/'chart'/'comparison' and self-contained HTML (inline <script> allowed, NO external network assets) for 'interactive'. Keep it compact and readable; width auto-fits the container. Fall back to normal markdown text when prose or a table is clearer. Do NOT use render_widget for content that is better as a real saved file the user can open elsewhere.\n"
        // [T-deep-mode-phase-e] Phase E: Scheduled-automation guidance. Teaches
        // the model when and how to use the schedule_task tool. Pure prompt
        // addition inside deepModeFragment — governed by the master switch.
        // The tool is only registered in deep mode; created tasks stay
        // manageable in Settings regardless of the switch.
        s += "15. SCHEDULED AUTOMATION — You have a `schedule_task` tool that creates a repeating AI action (run daily / weekdays / on specific days at a set time). Use it when the user asks to set up anything recurring: '每天 9 点生成日报', '每个工作日早上整理邮件', '每周一运行安全检查'. Parse the natural-language request into the structured arguments: a short `label`, a fully self-contained `prompt` (the task starts in a FRESH chat, so include all necessary context), a 24-hour `time` (HH:MM), and a `repeat` mode (daily / weekdays / custom + days). After creating, tell the user the next-fire time and that they can manage the task in [Settings → Agent Runtime → Scheduled Tasks](minis://settings/scheduled-tasks). The task runs on a best-effort schedule via a local notification + open-time catch-up; a missed fire is caught the next time the app is opened, never silently dropped.\n"
        // [T-deep-mode-phase-f] Phase F: Spec-mode guidance. Injected ONLY when
        // the Spec toggle is on (deep-mode fragment is already gated on the
        // master switch, so `SpecGate.modeEnabled && deepModeEnabled` together
        // gate this). Pure prompt addition — zero runtime state.
        if SpecGate.modeEnabled {
            s += "16. SPECIFICATION (SPEC) MODE — an OPTIONAL phase AFTER verification passes. Only activate when BOTH deep mode is on AND Spec mode is enabled (the client will already have entered the spec-writing phase and told you to start). Formalize the completed work into THREE documents with file_write (create_dirs=true): spec.md (goal / scope-in / scope-out / feature list / acceptance criteria), checklist.md (a verification checklist derived from the acceptance criteria), tasks.md (task breakdown, marking independent tasks with [PARALLEL]). Keep each document precise, structured markdown; reuse the actual work you just did — do NOT invent new requirements. At the END of your turn, after all three files are written, append exactly one line:\n  <<SPEC_STATE>>\nDo NOT start new execution work during the spec-writing phase — only write the three specification documents.\n"
        }
        _cachedDeepModeFragment = s
        _cachedDeepModeFragmentKey = cacheKey
        return s
    }

    // MARK: - P1 Cognitive Abilities (C6/C7/C8)

    /// [T-deep-mode-cognitive-p1] C7: Guard flag ensuring the retrospective runs
    /// at most once per workflow completion. Set when the retrospective begins,
    /// cleared when a new workflow starts (beginExecution). Total-switch safe:
}
