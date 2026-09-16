import SwiftUI

// MARK: - InputBottomRowView
/// [T-ios-runtime-demangle-watchdog] Bottom toolbar row of the input bar
/// (+ / slash / edit-exit / mic / send buttons).
///
/// Extracted to a top-level struct to cut a deep branch from AIChatView's
/// type tree. This row contains many conditional subviews (Menu, Button,
/// HStack with Spacers) that would otherwise add significant depth to
/// inputBar's mangled type, contributing to the runtime demangle
/// watchdog timeout on cold launch.
struct InputBottomRowView: View {
    @ObservedObject var vm: AIChatViewModel
    
    // State bindings
    @Binding var inputFocused: Bool
    @Binding var showAttachmentMenu: Bool
    @Binding var showCamera: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showDocumentPicker: Bool
    
    // State values
    let voiceInputActive: Bool
    let canSend: Bool
    let canEnqueue: Bool
    
    // Managers
    var speechManager: SpeechRecognitionManager
    var voiceOutput: VoiceOutputState
    
    // Callbacks
    let onSend: () -> Void
    let onEnqueue: () -> Void
    let onMicTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            attachmentMenuButton
            slashMenuButton
            if vm.editingMessageIndex != nil { editExitButton }
            Spacer()
            if voiceInputActive, vm.editingMessageIndex == nil {
                readAloudToolbarToggle
                Spacer()
            }
            micButtonContainer
            sendButton
        }
    }
    
    // MARK: - Attachment Menu Button
    @ViewBuilder
    private var attachmentMenuButton: some View {
        let icon = Image(systemName: "plus")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(ChatColors.secondaryText)
            .frame(width: 34, height: 34)
            .accessibilityLabel(Text("Add attachment", comment: "VoiceOver label for the attachment button"))
            .background(ChatColors.inputIconBg)
            .clipShape(Circle())
            .overlay(Circle().stroke(ChatColors.inputIconBorder, lineWidth: 0.5))
        
        if #available(iOS 17, *) {
            Menu {
                Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera") }
                Button { showPhotoPicker = true } label: { Label("Choose Photos & Videos", systemImage: "photo.on.rectangle") }
                Button { showDocumentPicker = true } label: { Label("Add File", systemImage: "doc") }
            } label: {
                icon
            }
        } else {
            Button { showAttachmentMenu = true } label: {
                icon
            }
            .buttonStyle(.plain)
            .confirmationDialog("Add Attachment", isPresented: $showAttachmentMenu) {
                Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera") }
                Button { showPhotoPicker = true } label: { Label("Choose Photos & Videos", systemImage: "photo.on.rectangle") }
                Button { showDocumentPicker = true } label: { Label("Add File", systemImage: "doc") }
            }
        }
    }
    
    // MARK: - Slash Menu Button
    private var slashMenuButton: some View {
        Button {
            if vm.showSlashMenu {
                vm.dismissSlashMenu()
            } else {
                vm.showSlashMenuOverInput()
                inputFocused = true
            }
        } label: {
            Text("/")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .italic()
                .foregroundStyle(ChatColors.secondaryText)
                .frame(width: 34, height: 34)
                .background(ChatColors.inputIconBg)
                .clipShape(Circle())
                .overlay(Circle().stroke(ChatColors.inputIconBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Edit Exit Button
    private var editExitButton: some View {
        Button {
            vm.cancelEdit()
        } label: {
            Text("Exit Edit Mode", comment: "Cancel message editing")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ChatColors.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ChatColors.inputIconBg)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(ChatColors.inputIconBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Read Aloud Toolbar Toggle
    private var readAloudToolbarToggle: some View {
        let on = voiceOutput.isEnabled
        let muted = voiceOutput.isMuted
        return Button {
            if on && !muted {
                voiceOutput.isMuted = true
            } else if on && muted {
                vm.speakEnabled = false
                VoiceOutputPreferences.isEnabled = false
            } else {
                voiceOutput.isMuted = false
                vm.speakEnabled = true
                VoiceOutputPreferences.isEnabled = true
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: (on && !muted) ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text("Read replies", comment: "Voice TTS toggle (compact)")
                    .font(.subheadline)
            }
            .foregroundStyle(on ? Color.accentColor : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(on ? Color.accentColor.opacity(0.15)
                                  : Color.secondary.opacity(0.10))
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(
            on ? (muted
                    ? AppLocalized("On, muted", comment: "VoiceOver value for the read-replies toggle when enabled but muted")
                    : AppLocalized("On", comment: "VoiceOver value for the read-replies toggle when enabled"))
               : AppLocalized("Off", comment: "VoiceOver value for the read-replies toggle when disabled")
        ))
        .accessibilityHint(Text("Toggles reading replies aloud", comment: "VoiceOver hint for the read-replies toggle"))
    }
    
    // MARK: - Mic Button Container
    private var micButtonContainer: some View {
        MicButton(speechManager: speechManager, inputFocused: $inputFocused, onTap: onMicTap, isVoiceActive: voiceInputActive)
    }
    
    // MARK: - Send Button
    @ViewBuilder
    private var sendButton: some View {
        if vm.isProcessing && canEnqueue {
            Button { onEnqueue() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(ChatColors.sendButton)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel(Text("Add to queue", comment: "VoiceOver label for the send button while a reply is generating"))
            .accessibilityHint(Text("Queues this message to send after the current reply finishes", comment: "VoiceOver hint for the queue button"))
        } else if vm.isProcessing {
            Button { vm.cancel() } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Stop generating", comment: "VoiceOver label for the stop button"))
            .accessibilityHint(Text("Stops the reply that is being generated", comment: "VoiceOver hint for the stop button"))
        } else {
            Button { onSend() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(canSend ? ChatColors.sendButton : ChatColors.sendButtonDisabled)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSend)
            .accessibilityLabel(Text("Send message", comment: "VoiceOver label for the send button"))
            .accessibilityHint(Text("Sends the current message", comment: "VoiceOver hint for the send button"))
        }
    }
}
