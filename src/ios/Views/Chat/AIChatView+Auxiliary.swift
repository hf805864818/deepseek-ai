import SwiftUI
import UIKit

// MARK: - Move To Session Sheet

struct MoveToSessionSheet: View {
    let currentSessionId: String?
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [ChatSession] = []
    @State private var searchText = ""
    @State private var searchMatchedIds: Set<String>?
    @State private var searchTask: Task<Void, Never>?

    /// Prefix used by ContentView for draft session IDs.
    private static let newSessionPrefix = "__new__"

    private var isSearching: Bool { !searchText.isEmpty }

    private var displayedSessions: [ChatSession] {
        let filtered = sessions.filter { $0.id != currentSessionId }
        guard let matchedIds = searchMatchedIds else { return filtered }
        return filtered.filter { matchedIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !isSearching {
                    Button {
                        let newId = "\(Self.newSessionPrefix)\(UUID().uuidString)"
                        dismiss()
                        onSelect(newId)
                    } label: {
                        Label(AppLocalized("New Chat"), systemImage: "plus.bubble")
                    }
                }

                Section(isSearching ? AppLocalized("Results") : AppLocalized("Recent")) {
                    ForEach(displayedSessions) { session in
                        Button {
                            dismiss()
                            onSelect(session.id)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    highlightedText(
                                        session.title ?? AppLocalized("New Chat"),
                                        font: .system(size: 16, weight: .semibold),
                                        color: Color(UIColor.label)
                                    )
                                    .lineLimit(1)
                                    highlightedText(
                                        session.lastMessage ?? AppLocalized("No messages yet"),
                                        font: .system(size: 14),
                                        color: Color(UIColor.secondaryLabel)
                                    )
                                    .lineLimit(1)
                                }
                                Spacer(minLength: 1)
                                Text(relativeDate(session.updatedAt))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(UIColor.tertiaryLabel))
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: AppLocalized("Search chats..."))
            .onChange(of: searchText) { _ in scheduleSearch() }
            .navigationTitle(AppLocalized("Move to…"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalized("Cancel")) { dismiss() }
                }
            }
        }
        .task {
            sessions = ChatStore.shared.listSessions()
        }
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchMatchedIds = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let results = await ChatStore.shared.searchSessions(query: query)
            if !Task.isCancelled {
                searchMatchedIds = Set(results.map(\.session.id))
            }
        }
    }

    // MARK: - Highlight

    @ViewBuilder
    private func highlightedText(_ text: String, font: Font, color: Color) -> some View {
        if isSearching, let query = Optional(searchText.trimmingCharacters(in: .whitespaces)),
           !query.isEmpty, text.range(of: query, options: .caseInsensitive) != nil {
            buildHighlighted(text, query: query, font: font, color: color)
        } else {
            Text(text).font(font).foregroundStyle(color)
        }
    }

    private func buildHighlighted(_ text: String, query: String, font: Font, color: Color) -> Text {
        let lower = text.lowercased()
        let lowerQ = query.lowercased()
        var result = Text("")
        var current = text.startIndex

        while current < text.endIndex,
              let range = lower.range(of: lowerQ, range: current..<lower.endIndex) {
            if current < range.lowerBound {
                result = result + Text(text[current..<range.lowerBound])
                    .font(font).foregroundColor(color)
            }
            result = result + Text(text[range])
                .font(font).foregroundColor(.accentColor).bold()
            current = range.upperBound
        }
        if current < text.endIndex {
            result = result + Text(text[current..<text.endIndex])
                .font(font).foregroundColor(color)
        }
        return result
    }

    // MARK: - Relative Date

    private func relativeDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let seconds = Int(now.timeIntervalSince(date))
        if calendar.isDateInToday(date) {
            if seconds < 60 {
                return AppLocalized("Just now")
            } else if seconds < 3600 {
                let mins = seconds / 60
                return "\(mins) min ago"
            } else {
                let hrs = seconds / 3600
                return "\(hrs) hr ago"
            }
        } else if calendar.isDateInYesterday(date) {
            return AppLocalized("Yesterday")
        } else {
            let diff = calendar.dateComponents([.day], from: date, to: now)
            if let days = diff.day, days < 7 {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                return formatter.string(from: date)
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - UIView helpers

extension UIView {
    /// Walk the responder chain to find the nearest UIViewController.
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }
}

// MARK: - Face ID Session Lock Overlay
//
// Encapsulates the entire Face ID gate (state + overlay UI + lifecycle
// observers) into a self-contained `View` so that AIChatView's body
// only references it as a single opaque type. This keeps the chat
// body's generic-type depth bounded — earlier inlined attempts pushed
// `__swift_instantiateConcreteTypeFromMangledNameV2` into runtime
// metadata recursion and crashed with EXC_BAD_ACCESS at the stack
// guard region on iOS 26.
struct SessionLockGateOverlay: View {
    let sessionId: String?

    @ObservedObject private var store = SessionLockStore.shared
    @Environment(\.scenePhase) private var scenePhase
    /// True while an LAContext prompt is in flight — suppresses repeated
    /// auto-prompts when the system overlay itself transiently resigns
    /// the chat view.
    @State private var promptInFlight = false
    /// Set after a failed / cancelled prompt so the overlay renders a
    /// tap-to-retry affordance instead of immediately re-prompting.
    @State private var attemptFailed = false

    var body: some View {
        Group {
            if shouldShow {
                gateView
            }
        }
        .onAppear { evaluate(reason: "onAppear") }
        .onDisappear {
            // [T-faceid-lock-on-exit 2026-05-21] "Lock on exit" mode
            // (idleTimeoutSeconds < 0): clear this session's unlock as
            // soon as the chat view leaves the screen (user popped back
            // to the sidebar / pushed a settings page / navigated to
            // another session). Without this, the unlock stamp survives
            // until the app backgrounds, which doesn't match the user's
            // intent of "locking the moment I leave this chat".
            //
            // Positive idle windows are NOT cleared here — they keep
            // the stamp so navigating away and back within the window
            // doesn't re-prompt for Face ID.
            if let sid = sessionId, store.isLocked(sid), store.idleTimeoutSeconds < 0 {
                store.clearUnlock(sid)
                attemptFailed = false
            }
        }
        .onChange(of: scenePhase) { newPhase in
            handleScene(newPhase)
        }
        .onChange(of: sessionId) { _ in
            attemptFailed = false
            promptInFlight = false
            evaluate(reason: "sessionIdChanged")
        }
    }

    private var shouldShow: Bool {
        guard let sid = sessionId, !sid.isEmpty else { return false }
        return store.isVisuallyLocked(sid)
    }

    private var gateView: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
                .overlay {
                    Color(UIColor.systemBackground).opacity(0.4)
                        .ignoresSafeArea()
                }

            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)

                Text("This session is locked")
                    .font(.system(size: 18, weight: .semibold))

                Text(attemptFailed
                     ? "Authentication failed. Tap to try again."
                     : "Tap to unlock with \(BiometricAuth.biometryDisplayName)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    promptForBiometricUnlock()
                } label: {
                    Label(attemptFailed
                          ? AppLocalized("Try again")
                          : AppLocalized("Unlock"),
                          systemImage: "faceid")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(.tint, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 32)
        }
        .contentShape(Rectangle())
        .onTapGesture { promptForBiometricUnlock() }
        .transition(.opacity)
    }

    private func evaluate(reason: String) {
        guard let sid = sessionId, !sid.isEmpty else { return }
        guard store.globalEnabled, BiometricAuth.isAvailable else { return }
        guard store.isLocked(sid) else { return }
        store.relockIfIdleExpired(sid)
        guard !store.isCurrentlyUnlocked(sid) else { return }
        guard !promptInFlight, !attemptFailed else { return }
        promptForBiometricUnlock()
    }

    private func promptForBiometricUnlock() {
        guard let sid = sessionId, !sid.isEmpty else { return }
        guard !promptInFlight else { return }
        promptInFlight = true
        Task { @MainActor in
            let reason = AppLocalized("Unlock this chat session")
            let ok = await BiometricAuth.authenticate(reason: reason)
            promptInFlight = false
            if ok {
                store.noteUnlock(sid)
                attemptFailed = false
            } else {
                attemptFailed = true
            }
        }
    }

    private func handleScene(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            // [T-faceid-lock-background-timeout 2026-05-21] Previously
            // cleared the per-session unlock stamp unconditionally on
            // background/inactive, which made the idle timeout setting
            // (e.g. "10 minutes") behave as if it were "Lock on exit":
            // any backgrounding instantly re-locked the chat. Honor the
            // user's chosen idle window now — only clear the unlock if
            // they explicitly chose "Lock on exit" (idle < 0). For
            // positive idle values the stamp is kept and re-evaluated
            // on .active via evictIdleExpired() + evaluate().
            if let sid = sessionId, store.isLocked(sid) {
                if store.idleTimeoutSeconds < 0 {
                    store.clearUnlock(sid)
                }
                attemptFailed = false
            }
        case .active:
            store.evictIdleExpired()
            evaluate(reason: "scenePhase.active")
        @unknown default:
            break
        }
    }
}

// MARK: - Mic Button (touch-release activation)

/// Mic button that triggers on touch-release (finger lift) to avoid accidental activation.
/// Press highlight is provided via GestureState.
struct MicButton: View {
    @ObservedObject var speechManager: SpeechRecognitionManager
    @Binding var inputFocused: Bool
    /// Opens the voice-input (VAD) panel. The mic button no longer drives the
    /// in-bar SFSpeech live dictation directly — the panel (with the configured
    /// ASR provider, or the offline System fallback) is the single voice entry
    /// point. The SpeechRecognitionManager path stays in place but is no longer
    /// triggered from here.
    var onTap: () -> Void = {}
    /// True while inline voice mode is active — the button flips to a "T" glyph
    /// that switches back to text input.
    var isVoiceActive: Bool = false
    /// Press feedback for the custom-gesture button.
    @State private var micPressed = false

    private static let diameter: CGFloat = 34

    var body: some View {
        // NOT a Button: SwiftUI's Button has a generous system touch-slop / touch-
        // up tolerance that fires when the finger lifts slightly outside, or moves
        // a little during a scroll/drag — which made this toggle very easy to
        // mis-tap. We use a DragGesture(minimumDistance: 0) and only activate when
        // BOTH the press and release land inside the circle AND movement is tiny.
        // In voice mode: a keyboard glyph = switch back to text input. The keyboard
        // glyph is wider than the mic, so render it ~4pt smaller for parity.
        Image(systemName: isVoiceActive ? "keyboard" : "mic")
            .font(.system(size: isVoiceActive ? 15 : 18, weight: .medium))
            .foregroundStyle(ChatColors.secondaryText)
            .frame(width: Self.diameter, height: Self.diameter)
            .background(ChatColors.inputIconBg)
            .clipShape(Circle())
            .overlay(Circle().stroke(ChatColors.inputIconBorder, lineWidth: 0.5))
            .scaleEffect(micPressed ? 0.9 : 1.0)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        micPressed = Self.isInside(value.location)
                    }
                    .onEnded { value in
                        let started = Self.isInside(value.startLocation)
                        let ended = Self.isInside(value.location)
                        let moved = hypot(value.translation.width, value.translation.height)
                        micPressed = false
                        guard started, ended, moved < 10 else { return }
                        inputFocused = false
                        onTap()
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isVoiceActive
                ? Text("Switch to text input", comment: "Mic button exits voice mode")
                : Text("Voice input", comment: "Mic button opens voice panel"))
    }

    /// Whether a point (in the button's local space) is within the visible circle.
    private static func isInside(_ p: CGPoint) -> Bool {
        let r = diameter / 2
        let dx = p.x - r, dy = p.y - r
        return (dx * dx + dy * dy) <= r * r
    }
}

// MARK: - Speech Language Picker Sheet

struct SpeechLanguagePickerSheet: View {
    @ObservedObject var speechManager: SpeechRecognitionManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredLocales: [Locale] {
        if searchText.isEmpty { return speechManager.availableLocales }
        let query = searchText.lowercased()
        return speechManager.availableLocales.filter { loc in
            let name = speechManager.displayName(for: loc).lowercased()
            let id = loc.identifier.lowercased()
            return name.contains(query) || id.contains(query)
        }
    }

    /// Indices where the preferred/non-preferred boundary lies for section headers.
    private var preferredCodes: Set<String> {
        Set(Locale.preferredLanguages.map { Locale(identifier: $0).language.languageCode?.identifier ?? "" })
    }

    var body: some View {
        NavigationStack {
            List {
                let preferred = filteredLocales.filter { preferredCodes.contains($0.language.languageCode?.identifier ?? "") }
                let others = filteredLocales.filter { !preferredCodes.contains($0.language.languageCode?.identifier ?? "") }

                if !preferred.isEmpty {
                    Section(AppLocalized("Preferred", comment: "Section header for preferred speech languages")) {
                        ForEach(preferred, id: \.identifier) { loc in
                            languageRow(loc)
                        }
                    }
                }

                if !others.isEmpty {
                    Section(AppLocalized("All Languages", comment: "Section header for all speech languages")) {
                        ForEach(others, id: \.identifier) { loc in
                            languageRow(loc)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: Text("Search Languages", comment: "Search field placeholder for speech language picker"))
            .navigationTitle(Text("Voice Language", comment: "Navigation title for speech language picker"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalized("Done", comment: "Dismiss speech language picker")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func languageRow(_ loc: Locale) -> some View {
        Button {
            speechManager.setLanguage(loc)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(speechManager.displayName(for: loc))
                        .foregroundStyle(.primary)
                    Text(loc.identifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if loc.identifier == speechManager.locale.identifier {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Compact Summary Sheet

struct CompactSummarySheet: View {
    let summary: String
    /// Optional revert action. When provided, a "Revert Compact" button is shown
    /// below the summary; tapping it invokes the closure (typically wired to
    /// AIChatViewModel.revertCompact()) and dismisses the sheet.
    var onRevert: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var showRevertConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SelectableTextView(text: summary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                if onRevert != nil {
                    Divider()
                    Button(role: .destructive) {
                        showRevertConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Revert Compact")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Compact Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = summary
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .foregroundStyle(copied ? .green : .secondary)
                    }
                }
            }
            .alert("Revert this compact?", isPresented: $showRevertConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Revert", role: .destructive) {
                    let action = onRevert
                    dismiss()
                    action?()
                }
            } message: {
                Text("The summary will be discarded and the messages it covered will become active again. This may push the conversation past the model's context window — if that happens, long-press a message to re-compact from that point.")
            }
        }
        .presentationDetents([.large])
    }
}

/// UITextView wrapper for efficient rendering of long selectable text.
struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = .systemFont(ofSize: 14)
        tv.textColor = .label
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.showsVerticalScrollIndicator = true
        tv.alwaysBounceVertical = true
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }
    }
}

// MARK: - Token Usage Sheet

struct TokenUsageSheet: View {
    @ObservedObject var vm: AIChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let s = vm.sessionTokenStats

                Section("Context") {
                    StatRow(label: "Context Used", value: formatted(s.context), icon: "text.alignleft")
                    if let window = vm.currentModelContextWindow {
                        StatRow(label: "Context Window", value: formatted(window), icon: "arrow.left.and.right")
                    }
                    if let maxOut = vm.currentModelMaxOutputTokens {
                        StatRow(label: "Max Output", value: formatted(maxOut), icon: "arrow.up.to.line")
                    }
                }

                if let thinkingInfo = vm.currentModelThinkingInfo {
                    Section("Thinking") {
                        StatRow(label: "Thinking", value: thinkingInfo.enabled ? "On" : "Off", icon: "lightbulb", customIcon: Image("ThinkingIcon"))
                        if thinkingInfo.enabled {
                            StatRow(label: "Level", value: thinkingInfo.level, icon: "slider.horizontal.3")
                        }
                        StatRow(label: "Supported", value: thinkingInfo.supported ? "Yes" : "No", icon: "checkmark.circle")
                    }
                }

                Section("Tokens (Session Total)") {
                    let inputTotal = s.input + s.cacheRead + s.cacheWrite
                    StatRow(label: "Input (incl. cache)", value: formatted(inputTotal), icon: "arrow.down.circle")
                    StatRow(label: "Output", value: formatted(s.output), icon: "arrow.up.circle")
                }

                Section("Cache (Session Total)") {
                    StatRow(label: "Cache Read", value: formatted(s.cacheRead), icon: "arrow.triangle.2.circlepath")
                    StatRow(label: "Cache Write", value: formatted(s.cacheWrite), icon: "square.and.arrow.down")
                    // [T-ios-token-usage-cache-hit-rate] Cache hit rate = cache read
                    // over total input (incl. cache) — the same denominator as the
                    // "Input (incl. cache)" row above (input + cacheRead + cacheWrite).
                    // Shows how much of this session's input was served from cache.
                    let totalInput = s.input + s.cacheRead + s.cacheWrite
                    if totalInput > 0 && s.cacheRead > 0 {
                        let hitRate = Double(s.cacheRead) / Double(totalInput) * 100
                        StatRow(label: "Cache Hit Rate", value: String(format: "%.1f%%", hitRate), icon: "percent")
                    }
                }

                Section("Speed") {
                    let speed = vm.sessionOutputTokensPerSecond
                    StatRow(label: "Output Speed", value: speed > 0 ? String(format: "%.1f tok/s", speed) : "—", icon: "speedometer")
                }

                Section("Agent Loop") {
                    StatRow(label: "Total Loops", value: "\(s.loopCount)", icon: "repeat")
                }
            }
            .navigationTitle("Session Token Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formatted(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

struct StatRow: View {
    let label: LocalizedStringKey
    let value: String
    let icon: String
    var customIcon: Image?

    var body: some View {
        HStack {
            if let customIcon {
                Label {
                    Text(label)
                } icon: {
                    customIcon
                        .resizable()
                        .frame(width: 14, height: 14)
                }
            } else {
                Label(label, systemImage: icon)
            }
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Empty Chat Directory Timeline

/// Onboarding view rendered in the center of a New Chat (no messages yet).
/// Shows the per-session vs cross-session directory layout under
/// `/var/minis/` as a 2-column folder grid so the user understands what's
/// available before typing.
///
/// Source-of-truth for the descriptions: AIChatViewModel.swift system-prompt
/// directory listing (`Shared directory /var/minis/ ...`). Keep them aligned
/// when either side changes.
struct EmptyChatDirectoryTimeline: View {
    var onBrowse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ChatColors.secondaryText)
                Text("Workspace layout")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ChatColors.secondaryText)
            }
            Text("Each chat gets its own **workspace**, **attachments**, **offloads**, and **browser** folders — wiped when the session ends.")
                .font(.system(size: 12))
                .foregroundStyle(ChatColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("All chats share **shared**, **skills**, **memory**, and **mounts** — persistent across sessions.")
                .font(.system(size: 12))
                .foregroundStyle(ChatColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(action: onBrowse) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Browse Chat Files")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(ChatColors.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(ChatColors.secondaryBg)
                    )
                    .overlay(
                        Capsule().stroke(ChatColors.toolBorder, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 460, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ChatColors.secondaryBg.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ChatColors.toolBorder, lineWidth: 0.5)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}


// MARK: - Session Loading Card

/// Three-dot carousel indicator: dots pulse in a staggered wave. The single
/// loading language for the session-entry path (loading card, in-place reload,
/// kernel boot) — replaces every system ProgressView spinner there, so the
/// old "菊花" never appears after / alongside the new loading UI.
struct LoadingDotsView: View {
    var dotSize: CGFloat = 10
    var color: Color = .accentColor
    @State private var animating = false

    var body: some View {
        HStack(spacing: dotSize * 0.7) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(animating ? 1.0 : 0.55)
                    .opacity(animating ? 0.95 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.16),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

/// Loading placeholder shown while ENTERING a session whose messages haven't
/// loaded yet — replaces the bare system spinner for that first-open moment
/// (black screen → lone spinner → content snap). Just the bare three-dot
/// carousel, centered — no card container or label (visual-simplification
/// feedback: the rounded material box + "Loading conversation…" text read as
/// too heavy). The container's transition fades/scales it out when loading
/// completes. Reload paths with content on screen never show this — see the
/// isLoadingSession overlay in AIChatView.
struct SessionLoadingCard: View {
    var body: some View {
        LoadingDotsView(dotSize: 8)
            .frame(height: 24)
    }
}

/// [voice-correction §6] Build the conversation context for a correction: the last user
/// message and the agent reply that followed it.
///
/// Reads the in-memory `messages` the chat is already rendering — §12.1 explicitly forbids
/// a DB query here, since this runs on the correction path. Both halves are truncated by
/// `ConversationContextTruncator` (500-char soft cap, extended to the next sentence
/// terminator so a quoted fragment never ends mid-sentence).
///
/// This is what lets correction work on a FRESH INSTALL. With both learned tables empty and
/// no context, the prompt has no evidence at all and the model correctly refuses to change
/// anything — which is exactly why the suggestion icon never appeared on a new device.
func voiceCorrectionContext(from messages: [ChatMessage]) -> ConversationContext {
    // Budgeted builder (2026-07-16): sentence-split + segment + rarity-rank the
    // recent turns, expanding the message count under a 5k-char budget, instead
    // of the original "last user + reply, first 500 chars each". §12.1 still
    // holds — this reads only the in-memory messages the chat is rendering.
    // Only real conversation turns feed the context. compactDivider and
    // systemInfo rows would otherwise be classified as "assistant" and leak
    // UI copy into the rare-terms digest.
    let source = messages
        .filter { $0.role == .user || $0.role == .assistant }
        .map { msg -> CorrectionSourceMessage in
            // Assistant turns keep their prose in `blocks` (text blocks), not
            // in `content` — reading only `content` silently dropped every AI
            // reply from the correction context. `content` can also hold a
            // stale FRAGMENT alongside full blocks (observed: a 34-char title
            // while the reply lived in blocks), so for assistant turns the
            // text blocks are the source of truth and `content` is only the
            // fallback. Tool/thinking/info blocks stay out — their payloads
            // are commands and traces, not conversational vocabulary.
            var text = msg.content
            if msg.role == .assistant, !msg.blocks.isEmpty {
                let blockText = msg.blocks
                    .filter { $0.kind == .text }
                    .map(\.content)
                    .joined(separator: "\n")
                if !blockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    text = blockText
                }
            }
            return CorrectionSourceMessage(role: msg.role == .user ? .user : .assistant,
                                           text: TypedVocabularyBuilder.stripAttachmentMarkup(text))
        }
    return CorrectionContextBuilder.build(messages: source)
}

/// [T-browser-download-ux-v2] Sheet item for "Show in Files" from the
/// downloads panel: opens the file browser rooted at the session workspace
/// and highlights this filename.
struct DownloadLocateTarget: Identifiable {
    let filename: String
    var id: String { filename }
}
