import SwiftUI

// MARK: - MessagesAreaView
/// [T-ios-runtime-demangle-watchdog] The message list area — collection view
/// plus empty state overlays, floating scroll buttons, and download button.
///
/// Extracted to a top-level struct to cut the type tree at a struct boundary.
/// Without this, the messages area's deep ZStack + overlay + conditional
/// hierarchy would significantly deepen AIChatView.body's mangled type,
/// contributing to the runtime type-metadata decoder stack overflow /
/// watchdog timeout on cold launch.
struct MessagesAreaView: View {
    @ObservedObject var vm: AIChatViewModel

    // Layout metrics
    let maxContentWidth: CGFloat?
    let floatingBarHeight: CGFloat
    let inputBarHeight: CGFloat
    let hasFloatingPreview: Bool
    let totalSessionCount: Int?

    // State bindings
    @Binding var inputFocused: Bool
    @Binding var compactConfirmMessageId: UUID?
    @Binding var screenshotPreview: ChatScreenshotPreview?
    @Binding var showFileBrowser: Bool
    @Binding var showDownloadsPanel: Bool

    // Callbacks
    let forceSyncMessages: () -> Void
    let handleMinisURLTap: (URL) -> OpenURLAction.Result

    var body: some View {
        ZStack {
            CollectionViewMessageListV3(
                vm: vm,
                inputFocused: inputFocused,
                onRetryMessage: { vm.retryFromMessage($0); vm.forceScrollToBottom.send() },
                onRetryLast: { vm.retry(); vm.forceScrollToBottom.send() },
                onOpenSoulSettings: {
                    guard let url = URL(string: "minis://settings/soul") else { return }
                    _ = handleMinisURLTap(url)
                },
                onEdit: { msgId in
                    vm.editMessage(msgId)
                    inputFocused = true
                },
                onDeleteFrom: { vm.deleteFromMessage($0) },
                onWithdraw: { vm.withdrawQueuedMessage($0) },
                onResume: { vm.resume(); vm.forceScrollToBottom.send() },
                onStop: { vm.stopCurrentCommand() },
                onCompact: { msgId in compactConfirmMessageId = msgId },
                onRevertCompact: { Task { await vm.revertCompact() } },
                onForceSync: forceSyncMessages,
                onScreenshotImage: { image in
                    screenshotPreview = ChatScreenshotPreview(image: image)
                },
                maxContentWidth: maxContentWidth ?? 0,
                floatingBarHeight: floatingBarHeight,
                inputBarHeight: inputBarHeight
            )
            // Empty/loading overlay for tap-to-dismiss-keyboard.
            if vm.messages.isEmpty || vm.isLoadingSession {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { inputFocused = false }
            }
            // Empty-chat onboarding tip.
            if vm.sessionId == nil
                && vm.messages.isEmpty
                && !vm.isLoadingSession
                && (totalSessionCount ?? Int.max) == 0 {
                EmptyChatDirectoryTimeline(onBrowse: { showFileBrowser = true })
                    .padding(.horizontal, 24)
            }
        }
        .overlay(alignment: .bottom) {
            if !vm.messages.isEmpty && !vm.isNearBottom {
                VStack(spacing: 10) {
                    if !vm.isAtFirstTurn {
                        Button {
                            vm.forceScrollToTop.send()
                        } label: {
                            scrollFloatingButtonLabel("arrow.up.to.line")
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    Button {
                        vm.forceScrollToBottom.send()
                    } label: {
                        scrollFloatingButtonLabel("chevron.down")
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                .padding(.trailing, 4)
                .frame(maxWidth: maxContentWidth ?? .infinity, alignment: .trailing)
                .padding(.horizontal, 12)
                .padding(.bottom, inputBarHeight + (hasFloatingPreview ? 80 : 12))
                .animation(.easeInOut(duration: 0.2), value: vm.isNearBottom)
                .animation(.easeInOut(duration: 0.2), value: vm.isAtFirstTurn)
                .animation(.easeInOut(duration: 0.2), value: hasFloatingPreview)
                .capsuleProtectedFrame("scrollButtons")
            }
        }
        .overlay(alignment: .bottom) {
            BrowserDownloadFloatingButton(sessionId: vm.sessionId ?? "") {
                showDownloadsPanel = true
            }
            .padding(.trailing, 4)
            .frame(maxWidth: maxContentWidth ?? .infinity, alignment: .trailing)
            .padding(.horizontal, 12)
            .padding(.bottom, inputBarHeight + (hasFloatingPreview ? 80 : 12) + 92)
            .animation(.easeInOut(duration: 0.2), value: hasFloatingPreview)
            .capsuleProtectedFrame("downloadButton")
        }
    }

    /// Shared label style for the floating scroll buttons (up / down).
    private func scrollFloatingButtonLabel(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 36)
            .background { ScrollToBottomBackground().clipShape(Circle()) }
            .overlay(Circle().stroke(Color.gray.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }
}
