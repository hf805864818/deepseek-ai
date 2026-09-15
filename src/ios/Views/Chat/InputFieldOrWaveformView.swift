import SwiftUI

// MARK: - InputFieldOrWaveformView
/// [T-ios-runtime-demangle-watchdog] The input text field or voice
/// waveform area of the composer.
///
/// Extracted to a top-level struct to cut the type tree at a struct
/// boundary. This view contains a 3-way conditional (voice input /
/// recording waveform / text field) plus the composer resize handle,
/// which together form one of the deepest branches inside inputBar.
struct InputFieldOrWaveformView: View {
    @ObservedObject var vm: AIChatViewModel
    
    // Text input binding
    var inputText: Binding<String>
    
    // State bindings
    @Binding var inputFocused: Bool
    @Binding var inputHasSelection: Bool
    @Binding var inputIsScrollable: Bool
    @Binding var inputAtScrollBottom: Bool
    @Binding var transcriptHeight: CGFloat
    
    // State values
    let voiceInputActive: Bool
    let soulName: String
    let composerTextHeight: CGFloat?
    let composerResizeEnabled: Bool
    
    // Composer resize state
    @Binding var composerDragOffset: CGFloat
    @Binding var composerHeightFraction: Double
    
    // Managers
    var speechManager: SpeechRecognitionManager
    var voiceVM: VoiceInputViewModel
    
    // Callbacks
    let onReturnKey: () -> Void
    let onArrowUp: () -> Bool
    let onArrowDown: () -> Bool
    let onTab: () -> Bool
    let onCaretChange: (Int) -> Void
    let onToggleComposerHeight: () -> Void
    let onPersistComposerHeight: (CGFloat) -> Void
    let voiceCorrectionContext: () -> ConversationContext
    
    // Static constants
    private static let composerDefaultHeight: CGFloat = 120
    private static let composerMaxHeight: CGFloat = UIScreen.main.bounds.height * 0.5
    
    var body: some View {
        let topPadding: CGFloat = (vm.attachments.isEmpty && vm.loadingVideoCount == 0) ? 16 : 11
        if voiceInputActive {
            InlineVoiceInputView(
                viewModel: voiceVM,
                inputText: inputText,
                onPasteImage: { image in vm.addImageAttachment(image) },
                onPasteFile: { url in vm.addFileAttachment(from: url) },
                conversationContext: voiceCorrectionContext
            )
        } else if speechManager.state == .recording {
            recordingWaveform(topPadding: topPadding)
        } else {
            let field = PastableTextView(
                text: inputText,
                isFocused: $inputFocused,
                hasSelection: $inputHasSelection,
                isScrollable: $inputIsScrollable,
                isAtScrollBottom: $inputAtScrollBottom,
                placeholder: AppLocalized("Message \(soulName) (@ to mention files)"),
                onPasteImage: { image in vm.addImageAttachment(image) },
                onPasteFile: { url in vm.addFileAttachment(from: url) },
                onReturnKey: onReturnKey,
                onArrowUp: onArrowUp,
                onArrowDown: onArrowDown,
                onTab: onTab,
                onCaretChange: onCaretChange,
                onSelectionReplace: { before, after in
                    Task.detached(priority: .utility) {
                        await VoiceCorrectionRecorder.shared.recordEdit(
                            before: before, after: after,
                            locale: "zh", source: "text_input")
                    }
                },
                desiredCaret: vm.pendingCaret,
                maxHeightOverride: composerTextHeight
            )
            composerBody(field: field, topPadding: topPadding)
        }
    }
    
    // MARK: - Recording Waveform
    private func recordingWaveform(topPadding: CGFloat) -> some View {
        let transcriptMaxHeight: CGFloat = 100
        return VStack(spacing: 6) {
            AudioWaveformView(levels: speechManager.audioLevels)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
            if !speechManager.recognizedText.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(speechManager.recognizedText)
                            .font(.subheadline)
                            .foregroundStyle(ChatColors.secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: TranscriptHeightKey.self, value: geo.size.height)
                            })
                            .id("transcriptTail")
                    }
                    .frame(height: min(max(transcriptHeight, 22), transcriptMaxHeight))
                    .onPreferenceChange(TranscriptHeightKey.self) { transcriptHeight = $0 }
                    .onReceive(speechManager.$recognizedText) { _ in
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo("transcriptTail", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, topPadding)
        .padding(.bottom, 10)
    }
    
    // MARK: - Composer Body
    /// Wraps the text field with its (optional) fixed height and the iPad
    /// drag handle.
    @ViewBuilder
    private func composerBody(field: PastableTextView, topPadding: CGFloat) -> some View {
        Group {
            if let height = composerTextHeight {
                field.frame(height: height)
            } else {
                field.fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, topPadding)
        .padding(.bottom, 10)
        .overlay(alignment: .top) {
            if composerResizeEnabled { composerResizeHandle }
        }
    }
    
    // MARK: - Composer Resize Handle
    /// The grab affordance. Dragging UP makes the composer taller.
    private var composerResizeHandle: some View {
        Capsule()
            .fill(ChatColors.secondaryText.opacity(0.35))
            .frame(width: 36, height: 5)
            .padding(.top, 4)
            .contentShape(Rectangle().inset(by: -12))
            .onTapGesture(count: 2) { onToggleComposerHeight() }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in composerDragOffset = -value.translation.height }
                    .onEnded { value in
                        let resolved = min(
                            max(currentComposerHeight - value.translation.height,
                                Self.composerDefaultHeight),
                            Self.composerMaxHeight)
                        composerDragOffset = 0
                        onPersistComposerHeight(resolved)
                    }
            )
            .accessibilityLabel(AppLocalized("Resize input box"))
            .accessibilityHint(AppLocalized("Drag to resize, double tap to toggle"))
    }
    
    /// The composer's current height, used as the drag's starting point.
    private var currentComposerHeight: CGFloat {
        composerHeightFraction > 0
            ? min(max(UIScreen.main.bounds.height * composerHeightFraction,
                      Self.composerDefaultHeight), Self.composerMaxHeight)
            : Self.composerDefaultHeight
    }
}
