import SwiftUI
import UIKit

// MARK: - Nav Bar Modifiers

struct NavTitleFrameModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // [NavTitleTopClip 2026-07-23] The principal titleView aligns to the
            // liquid-glass navbar's ~44pt band. Give it 46pt centered so tall
            // title glyphs (semibold 16pt + CJK/caps ascenders) render in full.
            //
            // [NavTitleTransitionClip 2026-07-23] Do NOT `.clipped()`. During a
            // push/pop transition the system interpolates the principal item's
            // frame/scale/alpha; a hard clip rectangle cuts the mid-transition
            // frames along the 46pt box far more aggressively than the steady
            // state (users saw the title sliced to half a line during the
            // animation). The 46pt frame only *sizes* the item for band
            // alignment — the 3-row stack's natural height already fits within
            // it at steady state (spacing -2, ~44pt), so there is nothing to clip
            // away, and letting transition frames render uncropped restores the
            // standard system title transition.
            content
                .frame(height: 46, alignment: .center)
        } else {
            content
        }
    }
}

struct NavBarStyleModifier: ViewModifier {
    @Binding var topSafeAreaInset: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // iOS 26: extend content behind nav bar so liquid-glass has
            // something to show through; the collection view's
            // contentInsetAdjustmentBehavior = .automatic keeps messages
            // starting below the bar.
            content
                .ignoresSafeArea(.container, edges: .top)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        } else {
            // iOS 16–18: opaque navbar background
            content
                .toolbarBackground(ChatColors.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .overlay(alignment: .top) {
                    // [T-ios-geometry-observer-crash] onGeometryChange replaces
                    // the GeometryReader scaffold (async-renderer SIGTRAP — see
                    // the floating-bar site). The proxy measures the same
                    // Color.clear the reader wrapped; ignoresSafeArea/frame
                    // stay outside it exactly as before, and the action's
                    // initial fire covers the old onAppear seed.
                    Color.clear
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.safeAreaInsets.top
                        } action: { topSafeAreaInset = $0 }
                        .ignoresSafeArea()
                        .frame(height: 0)
                }
        }
    }
}

// MARK: - Chat Trailing "…" Menu

/// [T-ios-trailing-menu-streaming-stability] The chat page's "…" menu,
/// extracted from AIChatView into an Equatable child so an OPEN menu stays
/// stable during streaming. AIChatView.body re-evaluates on every streaming
/// tick (the whole view observes the view model); with the Menu declared
/// inline, each tick pushed rebuilt menu content into the presented UIMenu,
/// which could reshuffle/reset it right as the user tapped — the reported
/// mis-taps on menu items mid-stream.
///
/// `.equatable()` at the call site makes SwiftUI diff with `==` below, which
/// compares ONLY the values that change what the menu displays — none of
/// which mutate during a stream — so streaming ticks stop invalidating this
/// subtree entirely. Action closures are recreated by every parent body pass
/// but never change behavior, so they're deliberately excluded from `==`.
/// [T-ios-navbar-principal-streaming-stability] Generic value-keyed equatable
/// wrapper. SwiftUI skips re-evaluating `content` while `key` compares equal —
/// the same guard ChatTrailingMenu gets from its custom `==`, made reusable
/// for views (like the navbar titleView) that are too entangled with local
/// @State/onChange plumbing to extract wholesale. The content closure is
/// recreated every parent pass but is excluded from equality, exactly like
/// ChatTrailingMenu's action closures. Internal @State / onReceive updates
/// inside `content` still fire on their own — only parent-driven invalidation
/// is gated. Anything the content READS from the parent/vm must therefore be
/// represented in `key`, or its changes will not render.
#if DEBUG
/// [T-ios-navbar-principal-streaming-stability] Eval counters proving (or
/// disproving) that the toolbar equatable gates actually hold during
/// streaming. toolbarPass ≈ one per streaming tick (counted in navTitleKey,
/// which the toolbar builder computes every pass); titleEval / menuEval
/// should stay ~1 while a stream runs IF the gates work. Grep: [NavbarEval].
enum NavbarEvalStats {
    static var toolbarPass = 0
    static var titleEval = 0
    static var menuEval = 0
    static let logger = AppLogger(category: "NavbarEval")
}
#endif

struct EquatableByValue<Key: Equatable, Content: View>: View, Equatable {
    let key: Key
    @ViewBuilder let content: () -> Content

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }

    @ViewBuilder
    var body: some View {
        #if DEBUG
        let _ = {
            NavbarEvalStats.titleEval += 1
            NavbarEvalStats.logger.info("[NavbarEval] titleEval=\(NavbarEvalStats.titleEval) (toolbarPass=\(NavbarEvalStats.toolbarPass))")
        }()
        #endif
        content()
    }
}

/// [T-ios-navbar-principal-streaming-stability] Every display input the navbar
/// principal titleView renders, snapshotted as an Equatable key. While this is
/// unchanged (the entire streaming case), SwiftUI proves the principal toolbar
/// item unchanged and does NOT re-push the navigation bar's item set — which
/// was what kept rebuilding the OPEN "..." UIMenu each token even after
/// 59b31441 equatable-guarded the trailing menu itself: the guard covered the
/// trailing subtree, but the un-guarded principal item invalidated the whole
/// bar every tick, and UIKit refreshes the presented menu when bar items are
/// re-set (items shifting under the user's finger → mis-taps).
struct NavTitleKey: Equatable {
    let sessionTitle: String?
    let canEditTitle: Bool
    let soulName: String
    let modelName: String
    let isGroupBound: Bool
    /// [T-codex-fast-mode] Circular ⚡ badge before the model name while
    /// Fast Mode is enabled on a Codex OAuth model.
    let showFastBolt: Bool
    let resolvedText: String?
    let hasBinding: Bool
    let hasProviders: Bool
    let showThinkingBadge: Bool
    let thinkingLevelName: String
    let fallbackTrigger: Int
    /// The fallback-pulse @State lives on AIChatView but is RENDERED inside
    /// the gated titleView — each discrete set (6 over ~1.75s) must pierce
    /// the gate or the red pulse freezes at its first frame.
    let fallbackPulse: Double
    /// [T-ios-navtitle-blur-stuck-after-unlock] Face ID lock state — the
    /// title's `.blur(radius: titleIsVisuallyLocked ? 8 : 0)` renders inside
    /// the gated toolbar content, so the unlock transition must pierce the
    /// gate too. Without this field the chat body unblurred on unlock while
    /// the navbar title stayed frozen at blur 8 (user report 2026-07-24).
    let titleLocked: Bool
}

/// [T-ios-navbar-toolbar-host] Combined display key for the WHOLE toolbar:
/// the principal title's inputs plus the trailing menu's eight displayed
/// values. While this is unchanged, ChatToolbarHost.body — and therefore the
/// ToolbarContent builder — never re-runs.
struct ChatToolbarKey: Equatable {
    let navTitle: NavTitleKey
    let messagesEmpty: Bool
    let hasSession: Bool
    let isForcePulling: Bool
    let iCloudSyncEnabled: Bool
    let memoryEnabled: Bool
    let speakEnabled: Bool
    let showEnhancedCacheToggle: Bool
    let enhancedCacheEnabled: Bool
    /// [T-codex-fast-mode] Menu row shown only for Codex OAuth models.
    let showFastModeToggle: Bool
    let fastModeEnabled: Bool
}

/// [T-ios-navbar-toolbar-host] Zero-footprint host that owns the navigation
/// toolbar. Attached via .background on the chat content, so it sits inside
/// the NavigationStack destination (toolbar registers from any descendant),
/// occupies no layout, and — being Equatable on the toolbar's displayed
/// inputs — its body (the ToolbarContent builder) only re-runs when something
/// the toolbar actually shows changes. Streaming ticks leave the key equal,
/// the builder never re-runs, the bridge gets no new ToolbarContent to push,
/// and the OPEN native SwiftUI Menu stays untouched. Content closures are
/// recreated by every parent pass (excluded from ==, same pattern as
/// EquatableByValue/ChatTrailingMenu) so a key change always renders through
/// the freshest parent state.
struct ChatToolbarHost<Title: View, Trailing: View>: View, Equatable {
    let key: ChatToolbarKey
    @ViewBuilder let title: () -> Title
    @ViewBuilder let trailing: () -> Trailing

    static func == (lhs: Self, rhs: Self) -> Bool {
        let eq = lhs.key == rhs.key
        #if DEBUG
        if !eq {
            // Name the exact field that broke equality so a false-negative
            // key can be pinned from device logs.
            var diffs: [String] = []
            if lhs.key.navTitle != rhs.key.navTitle {
                let l = lhs.key.navTitle, r = rhs.key.navTitle
                if l.sessionTitle != r.sessionTitle { diffs.append("sessionTitle") }
                if l.canEditTitle != r.canEditTitle { diffs.append("canEditTitle") }
                if l.soulName != r.soulName { diffs.append("soulName") }
                if l.modelName != r.modelName { diffs.append("modelName") }
                if l.isGroupBound != r.isGroupBound { diffs.append("isGroupBound") }
                if l.resolvedText != r.resolvedText { diffs.append("resolvedText") }
                if l.hasBinding != r.hasBinding { diffs.append("hasBinding") }
                if l.hasProviders != r.hasProviders { diffs.append("hasProviders") }
                if l.showThinkingBadge != r.showThinkingBadge { diffs.append("showThinkingBadge") }
                if l.thinkingLevelName != r.thinkingLevelName { diffs.append("thinkingLevelName") }
                if l.fallbackTrigger != r.fallbackTrigger { diffs.append("fallbackTrigger") }
                if l.fallbackPulse != r.fallbackPulse { diffs.append("fallbackPulse") }
                if l.titleLocked != r.titleLocked { diffs.append("titleLocked") }
            }
            if lhs.key.messagesEmpty != rhs.key.messagesEmpty { diffs.append("messagesEmpty") }
            if lhs.key.hasSession != rhs.key.hasSession { diffs.append("hasSession") }
            if lhs.key.isForcePulling != rhs.key.isForcePulling { diffs.append("isForcePulling") }
            if lhs.key.iCloudSyncEnabled != rhs.key.iCloudSyncEnabled { diffs.append("iCloudSyncEnabled") }
            if lhs.key.memoryEnabled != rhs.key.memoryEnabled { diffs.append("memoryEnabled") }
            if lhs.key.speakEnabled != rhs.key.speakEnabled { diffs.append("speakEnabled") }
            if lhs.key.showEnhancedCacheToggle != rhs.key.showEnhancedCacheToggle { diffs.append("showEnhancedCacheToggle") }
            if lhs.key.enhancedCacheEnabled != rhs.key.enhancedCacheEnabled { diffs.append("enhancedCacheEnabled") }
            if lhs.key.showFastModeToggle != rhs.key.showFastModeToggle { diffs.append("showFastModeToggle") }
            if lhs.key.fastModeEnabled != rhs.key.fastModeEnabled { diffs.append("fastModeEnabled") }
            NavbarEvalStats.logger.info("[NavbarEval] host == FALSE diffs=[\(diffs.joined(separator: ","))]")
        }
        #endif
        return eq
    }

    var body: some View {
        #if DEBUG
        let _ = {
            NavbarEvalStats.titleEval += 1
            NavbarEvalStats.logger.info("[NavbarEval] toolbarHostEval=\(NavbarEvalStats.titleEval) (toolbarPass=\(NavbarEvalStats.toolbarPass))")
        }()
        #endif
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .toolbar {
                ToolbarItem(placement: .principal) { title() }
                ToolbarItem(placement: .topBarTrailing) { trailing() }
            }
    }
}

/// [T-ios-navbar-uikit-menu] UIKit-owned replacement for ChatTrailingMenu.
///
/// Instrumented device run (NavbarEval, 2026-07-17 19:35): during a streaming
/// reply the toolbar builder ran 34 times while BOTH equatable gates held
/// (titleEval=3, menuEval=2) — yet the presented menu still refreshed. The
/// leak is below SwiftUI: the toolbar bridge re-pushes the navigation item's
/// bar buttons every host pass even when the content views compare equal, and
/// UIKit refreshes/re-anchors a presented UIMenu whenever its bar's items are
/// re-set. No amount of view-level Equatable can stop that.
///
/// Fix: own the button AND the menu in UIKit. The UIViewRepresentable's
/// UIButton instance survives SwiftUI updates, the presented UIMenu is
/// anchored to that stable instance, and updateUIView only touches
/// `button.menu` when the DISPLAYED state actually changed — a no-op SwiftUI
/// pass physically cannot reach the menu. Field names/order are identical to
/// ChatTrailingMenu so the call site only swaps the type name. The DEBUG
/// request-count rows use UIDeferredMenuElement.uncached to stay fresh at
/// each open, matching the SwiftUI Menu's lazy content read.
/// [T-ios-navbar-toolbar-host] Native SwiftUI "..." menu, restored. The
/// UIKit ChatTrailingMenuButton below remains as the proven fallback (it
/// verifiably stops the mid-stream refresh but loses the system's round
/// Liquid-Glass chrome); with the toolbar now hosted in the equatable-gated
/// ChatToolbarHost the ToolbarContent is never rebuilt during streaming, so
/// the native Menu — and its native appearance — should be stable. Item set
/// mirrors the UIKit buildMenu exactly (incl. Compact Messages + the divider
/// between Clear Chat and the iCloud actions from T-chat-menu-compact-entry).
struct ChatTrailingMenu: View, Equatable {
    let messagesEmpty: Bool
    let hasSession: Bool
    let isForcePulling: Bool
    let iCloudSyncEnabled: Bool
    let memoryEnabled: Bool
    let speakEnabled: Bool
    let showEnhancedCacheToggle: Bool
    let enhancedCacheEnabled: Bool
    /// [T-codex-fast-mode] Mirrors ChatTrailingMenuButton.
    let showFastModeToggle: Bool
    let fastModeEnabled: Bool

    let onNewChat: () -> Void
    let onCompact: () -> Void
    let onClearChat: () -> Void
    let onForceSync: () -> Void
    let onForcePull: () -> Void
    let onOpenTerminal: () -> Void
    let onOpenBrowser: () -> Void
    let onBrowseFiles: () -> Void
    let onSkills: () -> Void
    let onMCPs: () -> Void
    let onMemories: () -> Void
    let setSpeakEnabled: (Bool) -> Void
    let setEnhancedCache: (Bool) -> Void
    let setFastMode: (Bool) -> Void
    let onTokenUsage: () -> Void
    let onCopyRequests: () -> Void
    let onCopySessionData: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.messagesEmpty == rhs.messagesEmpty
            && lhs.hasSession == rhs.hasSession
            && lhs.isForcePulling == rhs.isForcePulling
            && lhs.iCloudSyncEnabled == rhs.iCloudSyncEnabled
            && lhs.memoryEnabled == rhs.memoryEnabled
            && lhs.speakEnabled == rhs.speakEnabled
            && lhs.showEnhancedCacheToggle == rhs.showEnhancedCacheToggle
            && lhs.enhancedCacheEnabled == rhs.enhancedCacheEnabled
            && lhs.showFastModeToggle == rhs.showFastModeToggle
            && lhs.fastModeEnabled == rhs.fastModeEnabled
    }

    var body: some View {
        #if DEBUG
        let _ = {
            NavbarEvalStats.menuEval += 1
            NavbarEvalStats.logger.info("[NavbarEval] menuEval=\(NavbarEvalStats.menuEval) (toolbarPass=\(NavbarEvalStats.toolbarPass))")
        }()
        #endif
        return Menu {
            Button { onNewChat() } label: {
                Label(AppLocalized("New Chat"), systemImage: "square.and.pencil")
            }

            Divider()

            // [T-chat-menu-compact-entry] Compact above Clear Chat.
            Button { onCompact() } label: {
                Label(AppLocalized("Compact Messages"), systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .disabled(messagesEmpty)

            Button(role: .destructive) { onClearChat() } label: {
                Label(AppLocalized("Clear Chat"), systemImage: "trash")
            }
            .disabled(messagesEmpty)

            Divider()

            // iCloud sync actions: iOS 17+ (v2 sync engine) AND the user's
            // iCloud Sync toggle on.
            if #available(iOS 17.0, *), iCloudSyncEnabled {
                Button { onForceSync() } label: {
                    Label(AppLocalized("Force iCloud Sync"), systemImage: "icloud.and.arrow.up")
                }
                .disabled(!hasSession || isForcePulling)

                Button { onForcePull() } label: {
                    Label(AppLocalized("Force Pull Messages"), systemImage: "icloud.and.arrow.down")
                }
                .disabled(!hasSession || isForcePulling)

                Divider()
            }

            Button { onOpenTerminal() } label: {
                Label(AppLocalized("Open Terminal"), systemImage: "terminal")
            }

            Button { onOpenBrowser() } label: {
                Label(AppLocalized("Open Browser"), systemImage: "globe")
            }

            Button { onBrowseFiles() } label: {
                Label(AppLocalized("Browse Chat Files"), systemImage: "folder")
            }

            Divider()

            Button { onSkills() } label: {
                Label(AppLocalized("Skills in Session"), systemImage: "puzzlepiece.extension")
            }

            Button { onMCPs() } label: {
                Label(AppLocalized("MCPs in Session"), systemImage: "wrench.and.screwdriver")
            }

            if memoryEnabled {
                Button { onMemories() } label: {
                    Label(AppLocalized("Memories in Session"), systemImage: "brain.head.profile")
                }
            }

            Toggle(isOn: Binding(
                get: { speakEnabled },
                set: { setSpeakEnabled($0) }
            )) {
                Label(AppLocalized("Speak Responses"), systemImage: "speaker.wave.2")
            }

            // [T-codex-fast-mode-menu-group] Model-control toggles in their
            // own divider-separated section (mirrors the UIKit buildMenu).
            if showEnhancedCacheToggle || showFastModeToggle {
                Divider()

                if showEnhancedCacheToggle {
                    Toggle(isOn: Binding(
                        get: { enhancedCacheEnabled },
                        set: { setEnhancedCache($0) }
                    )) {
                        Label(AppLocalized("Enhanced Cache"), systemImage: "clock.arrow.circlepath")
                    }
                }

                if showFastModeToggle {
                    Toggle(isOn: Binding(
                        get: { fastModeEnabled },
                        set: { setFastMode($0) }
                    )) {
                        Label(AppLocalized("Enable Fast Mode"), systemImage: "bolt.fill")
                    }
                }
            }

            Divider()

            Button { onTokenUsage() } label: {
                Label(AppLocalized("Token Usage"), systemImage: "number")
            }

            #if DEBUG
            Divider()

            Button { onCopyRequests() } label: {
                let n = LastAPIRequestBody.shared.getAll().count
                Label("Copy Requests (\(n))", systemImage: "arrow.up.doc")
            }

            Button { onCopySessionData() } label: {
                Label("Copy Session Data", systemImage: "tray.and.arrow.up")
            }
            #endif
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ChatColors.primaryText)
        }
        // [T-ios-voiceover-labels] Matches the label the UIKit ellipsis button
        // elsewhere in this file already sets, so both read the same.
        .accessibilityLabel(Text("More options", comment: "VoiceOver label for the overflow menu button"))
    }
}

/// [T-ios-navbar-uikit-menu] PROVEN FALLBACK, currently unused: swaps in for
/// ChatTrailingMenu at the trailingMenu call site if the ChatToolbarHost
/// approach ever regresses. Verified on-device (2026-07-17) to stop the
/// mid-stream menu refresh; its remaining flaw was appearance (no native
/// round glass chrome — mitigated here by sizeThatFits reporting the
/// button's intrinsic size so the system container wraps it like a plain
/// toolbar icon).
struct ChatTrailingMenuButton: UIViewRepresentable {
    let messagesEmpty: Bool
    let hasSession: Bool
    let isForcePulling: Bool
    let iCloudSyncEnabled: Bool
    let memoryEnabled: Bool
    let speakEnabled: Bool
    let showEnhancedCacheToggle: Bool
    let enhancedCacheEnabled: Bool
    /// [T-codex-fast-mode] Shown only when the active model's provider is a
    /// Codex OAuth instance (OpenAI OAuth, no custom base).
    let showFastModeToggle: Bool
    let fastModeEnabled: Bool

    let onNewChat: () -> Void
    let onCompact: () -> Void
    let onClearChat: () -> Void
    let onForceSync: () -> Void
    let onForcePull: () -> Void
    let onOpenTerminal: () -> Void
    let onOpenBrowser: () -> Void
    let onBrowseFiles: () -> Void
    let onSkills: () -> Void
    let onMCPs: () -> Void
    let onMemories: () -> Void
    let setSpeakEnabled: (Bool) -> Void
    let setEnhancedCache: (Bool) -> Void
    let setFastMode: (Bool) -> Void
    let onTokenUsage: () -> Void
    let onCopyRequests: () -> Void
    let onCopySessionData: () -> Void

    /// The displayed-state snapshot — the ONLY trigger for a menu rebuild.
    struct Key: Equatable {
        let messagesEmpty: Bool
        let hasSession: Bool
        let isForcePulling: Bool
        let iCloudSyncEnabled: Bool
        let memoryEnabled: Bool
        let speakEnabled: Bool
        let showEnhancedCacheToggle: Bool
        let enhancedCacheEnabled: Bool
        let showFastModeToggle: Bool
        let fastModeEnabled: Bool
    }

    private var key: Key {
        Key(messagesEmpty: messagesEmpty, hasSession: hasSession,
            isForcePulling: isForcePulling, iCloudSyncEnabled: iCloudSyncEnabled,
            memoryEnabled: memoryEnabled, speakEnabled: speakEnabled,
            showEnhancedCacheToggle: showEnhancedCacheToggle,
            enhancedCacheEnabled: enhancedCacheEnabled,
            showFastModeToggle: showFastModeToggle,
            fastModeEnabled: fastModeEnabled)
    }

    final class Coordinator {
        var lastKey: Key?
        var parent: ChatTrailingMenuButton
        init(parent: ChatTrailingMenuButton) { self.parent = parent }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.setImage(UIImage(systemName: "ellipsis", withConfiguration: cfg), for: .normal)
        button.tintColor = UIColor(ChatColors.primaryText)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = AppLocalized("More options")
        button.menu = Self.buildMenu(key: key, coordinator: context.coordinator)
        context.coordinator.lastKey = key
        return button
    }

    /// Report the button's intrinsic size so the toolbar proposes an
    /// icon-sized footprint and the system wraps it in the same round glass
    /// as a plain toolbar icon (a representable otherwise accepts the full
    /// proposed width -> stretched capsule, the 2026-07-17 regression).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        uiView.intrinsicContentSize
    }

    func updateUIView(_ button: UIButton, context: Context) {
        // Closures capture view state -- refresh them every pass so actions
        // always see the latest values (excluded from the rebuild decision,
        // exactly like ChatTrailingMenu's ==).
        context.coordinator.parent = self
        guard context.coordinator.lastKey != key else { return }
        context.coordinator.lastKey = key
        button.menu = Self.buildMenu(key: key, coordinator: context.coordinator)
        #if DEBUG
        NavbarEvalStats.menuEval += 1
        NavbarEvalStats.logger.info("[NavbarEval] uikitMenuRebuild=\(NavbarEvalStats.menuEval) (toolbarPass=\(NavbarEvalStats.toolbarPass))")
        #endif
    }

    private static func buildMenu(key: Key, coordinator: Coordinator) -> UIMenu {
        var groups: [UIMenuElement] = []

        groups.append(UIMenu(options: .displayInline, children: [
            UIAction(title: AppLocalized("New Chat"),
                     image: UIImage(systemName: "square.and.pencil")) { _ in coordinator.parent.onNewChat() },
        ]))

        // [T-chat-menu-compact-entry] Compact sits ABOVE Clear Chat in its own
        // group with the destructive clear; the iCloud actions moved to a
        // separate inline group so a divider lands between Clear Chat and the
        // sync rows (user-requested layout).
        groups.append(UIMenu(options: .displayInline, children: [
            UIAction(title: AppLocalized("Compact Messages"),
                     image: UIImage(systemName: "arrow.down.right.and.arrow.up.left"),
                     attributes: key.messagesEmpty ? [.disabled] : []) { _ in coordinator.parent.onCompact() },
            UIAction(title: AppLocalized("Clear Chat"),
                     image: UIImage(systemName: "trash"),
                     attributes: key.messagesEmpty ? [.destructive, .disabled] : [.destructive]) { _ in coordinator.parent.onClearChat() },
        ]))

        // Same gate as before: iOS 17+ (v2 sync engine) AND the user's
        // iCloud Sync toggle on.
        if #available(iOS 17.0, *), key.iCloudSyncEnabled {
            let disabled: UIMenuElement.Attributes = (!key.hasSession || key.isForcePulling) ? [.disabled] : []
            groups.append(UIMenu(options: .displayInline, children: [
                UIAction(title: AppLocalized("Force iCloud Sync"),
                         image: UIImage(systemName: "icloud.and.arrow.up"),
                         attributes: disabled) { _ in coordinator.parent.onForceSync() },
                UIAction(title: AppLocalized("Force Pull Messages"),
                         image: UIImage(systemName: "icloud.and.arrow.down"),
                         attributes: disabled) { _ in coordinator.parent.onForcePull() },
            ]))
        }

        groups.append(UIMenu(options: .displayInline, children: [
            UIAction(title: AppLocalized("Open Terminal"),
                     image: UIImage(systemName: "terminal")) { _ in coordinator.parent.onOpenTerminal() },
            UIAction(title: AppLocalized("Open Browser"),
                     image: UIImage(systemName: "globe")) { _ in coordinator.parent.onOpenBrowser() },
            UIAction(title: AppLocalized("Browse Chat Files"),
                     image: UIImage(systemName: "folder")) { _ in coordinator.parent.onBrowseFiles() },
        ]))

        var sessionGroup: [UIMenuElement] = [
            UIAction(title: AppLocalized("Skills in Session"),
                     image: UIImage(systemName: "puzzlepiece.extension")) { _ in coordinator.parent.onSkills() },
            UIAction(title: AppLocalized("MCPs in Session"),
                     image: UIImage(systemName: "wrench.and.screwdriver")) { _ in coordinator.parent.onMCPs() },
        ]
        if key.memoryEnabled {
            sessionGroup.append(UIAction(title: AppLocalized("Memories in Session"),
                                         image: UIImage(systemName: "brain.head.profile")) { _ in coordinator.parent.onMemories() })
        }
        sessionGroup.append(UIAction(title: AppLocalized("Speak Responses"),
                                     image: UIImage(systemName: "speaker.wave.2"),
                                     state: key.speakEnabled ? .on : .off) { _ in
            coordinator.parent.setSpeakEnabled(!key.speakEnabled)
        })
        groups.append(UIMenu(options: .displayInline, children: sessionGroup))

        // [T-codex-fast-mode-menu-group] Model-control toggles (they shape how
        // the MODEL is invoked, unlike the session-scoped rows above) live in
        // their own inline group so dividers separate them on both sides.
        var modelControlGroup: [UIMenuElement] = []
        if key.showEnhancedCacheToggle {
            modelControlGroup.append(UIAction(title: AppLocalized("Enhanced Cache"),
                                              image: UIImage(systemName: "clock.arrow.circlepath"),
                                              state: key.enhancedCacheEnabled ? .on : .off) { _ in
                coordinator.parent.setEnhancedCache(!key.enhancedCacheEnabled)
            })
        }
        // [T-codex-fast-mode] Only for Codex OAuth models. Injects
        // service_tier=priority (the wire value codex_cli_rs sends for its
        // Fast mode) into Codex requests while enabled; 2x credit burn.
        if key.showFastModeToggle {
            modelControlGroup.append(UIAction(title: AppLocalized("Enable Fast Mode"),
                                              image: UIImage(systemName: "bolt.fill"),
                                              state: key.fastModeEnabled ? .on : .off) { _ in
                coordinator.parent.setFastMode(!key.fastModeEnabled)
            })
        }
        if !modelControlGroup.isEmpty {
            groups.append(UIMenu(options: .displayInline, children: modelControlGroup))
        }

        var tailGroup: [UIMenuElement] = [
            UIAction(title: AppLocalized("Token Usage"),
                     image: UIImage(systemName: "number")) { _ in coordinator.parent.onTokenUsage() },
        ]
        #if DEBUG
        tailGroup.append(UIDeferredMenuElement.uncached { completion in
            let n = LastAPIRequestBody.shared.getAll().count
            completion([
                UIAction(title: "Copy Requests (\(n))",
                         image: UIImage(systemName: "arrow.up.doc")) { _ in coordinator.parent.onCopyRequests() },
                UIAction(title: "Copy Session Data",
                         image: UIImage(systemName: "tray.and.arrow.up")) { _ in coordinator.parent.onCopySessionData() },
            ])
        })
        #endif
        groups.append(UIMenu(options: .displayInline, children: tailGroup))

        return UIMenu(children: groups)
    }
}
