import SwiftUI
import UIKit

// MARK: - Composer Surface

/// Background + shadow for the composer's outer rounded container.
///
/// **[T-popup-white-patch 7a0e3d62] — the invariant both branches must keep.**
/// The fill is painted INSIDE a rounded shape, never as a rectangular
/// `.background(color)` + `.clipShape(...)` pair. With that older pairing the
/// host CALayer carried a rectangular backing colour which the system
/// text-selection / edit-menu pop animation snapshotted *before* SwiftUI's mask
/// applied, flashing a square of colour around the rounded corners mid-animation.
/// Filling the shape directly leaves the host layer's `backgroundColor` at
/// `.clear`, so the snapshot is already rounded. `clipShape` is still applied so
/// child views (text view, attachment grid) are clipped to the same rect.
///
/// `glassEffect(in:)` composites the material into the shape it is given, for
/// the same reason: it does not set a rectangular layer background, so it
/// preserves the invariant rather than reintroducing the bug. Verified on device
/// by long-pressing composer text to raise the edit menu — see the task notes.
///
/// The two hand-rolled shadows are dropped on the glass path (Liquid Glass
/// renders its own edge and shadow; stacking the old ones reads as a dark halo —
/// the same finding as the FAB conversion). The sub-26 branch keeps the original
/// fill and BOTH shadows byte-for-byte, including the dark-mode-only top shadow
/// that lifts the bar off the message list.
struct ComposerSurface: ViewModifier {
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .clipShape(shape)
        } else {
            content
                .background(shape.fill(ChatColors.inputBg))
                .clipShape(shape)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
                .shadow(color: Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0, alpha: 0.5) : UIColor(white: 0, alpha: 0) }), radius: 8, x: 0, y: -4)
        }
    }
}

// MARK: - Provider Import Prompt

/// Presents the import-vs-attach choice for a shared/opened Provider-export
/// JSON, plus a result alert. Extracted from AIChatView.body so the (already
/// large) body's type-checker stays cheap. [T-ios-json-open-provider-import-prompt]
struct ProviderImportPromptModifier: ViewModifier {
    @Binding var pending: PendingProviderImport?
    @Binding var result: String?
    /// Import the provider from JSON; returns the new instance label on success.
    let onImport: (String) -> String?
    /// Add the (temp-copied) file to the chat as an attachment.
    let onAttach: (URL) -> Void

    func body(content: Content) -> some View {
        content
            // [T-ios-provider-import-prompt-bottom-sheet] Use a real bottom
            // sheet, not .confirmationDialog. On iPad / regular width SwiftUI
            // renders .confirmationDialog (and a UIAlertController .actionSheet)
            // as a SOURCE-ANCHORED POPOVER; with no anchor it floats a centered
            // rounded card over the messages — the "not a system dialog" look
            // the user reported. A `.sheet` with detents is a genuine
            // bottom-pinned sheet on BOTH iPhone and iPad.
            .sheet(item: $pending) { item in
                ProviderImportSheet(
                    onImport: {
                        pending = nil
                        if let label = onImport(item.json) {
                            result = AppLocalized("Imported provider \"\(label)\".")
                        } else {
                            result = AppLocalized("Could not import this provider configuration.")
                        }
                        try? FileManager.default.removeItem(at: item.fileURL)
                    },
                    onAttach: {
                        pending = nil
                        onAttach(item.fileURL)
                    },
                    onCancel: {
                        try? FileManager.default.removeItem(at: item.fileURL)
                        pending = nil
                    }
                )
            }
            .alert(
                AppLocalized("Provider Import"),
                isPresented: Binding(
                    get: { result != nil },
                    set: { if !$0 { result = nil } }
                )
            ) {
                Button(AppLocalized("OK"), role: .cancel) { result = nil }
            } message: {
                Text(result ?? "")
            }
    }
}

// MARK: - Provider Import Bottom Sheet

/// Bottom sheet offering "Import as Provider" vs "Add as Chat Attachment" for a
/// shared/opened Provider-export JSON. A real sheet (not .confirmationDialog)
/// so it pins to the bottom on iPad too, instead of floating a centered popover
/// card. [T-ios-provider-import-prompt-bottom-sheet]
struct ProviderImportSheet: View {
    let onImport: () -> Void
    let onAttach: () -> Void
    let onCancel: () -> Void

    /// Set once the user taps any explicit button, so the `.onDisappear`
    /// safety-cleanup only fires for a genuine swipe-to-dismiss (no choice).
    @State private var chose = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                    .padding(.top, 8)
                Text(AppLocalized("Provider Configuration Detected"))
                    .font(.system(size: 16, weight: .semibold))
                Text(AppLocalized("This JSON file contains a provider configuration. You can import it as a new provider, or attach it to this chat."))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                Button {
                    chose = true
                    onImport()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down.on.square")
                        Text(AppLocalized("Import as Provider"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    chose = true
                    onAttach()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperclip")
                        Text(AppLocalized("Add as Chat Attachment"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(ChatColors.secondaryBg)
                    .foregroundStyle(ChatColors.primaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(role: .cancel) {
                    chose = true
                    onCancel()
                } label: {
                    Text(AppLocalized("Cancel"))
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 16)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .onDisappear {
            // Safety cleanup: if the user swiped to dismiss without choosing,
            // still clean up the temp file.
            if !chose {
                onCancel()
            }
        }
    }
}

// MARK: - Swipe-to-Send Hint

/// Faint "swipe up to send" hint that fades in briefly when the user starts
/// typing their first message in an empty chat. Extracted as a modifier to
/// keep the body's type tree shallow.
struct SwipeToSendHintModifier: ViewModifier {
    @Binding var showHint: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showHint {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Swipe up to send")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(ChatColors.tertiaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(ChatColors.secondaryBg)
                    )
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
    }
}

// MARK: - Nav Bar Modifiers

/// Applies the chat-screen navigation bar chrome: transparent background,
/// correct title colour, and the top safe-area inset reader. Extracted so
/// AIChatView.body stays type-checker friendly.
struct ChatNavBarModifier: ViewModifier {
    @Binding var topSafeAreaInset: CGFloat

    func body(content: Content) -> some View {
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
