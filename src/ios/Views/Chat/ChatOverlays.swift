import SwiftUI

// MARK: - KernelBootOverlayView
/// [T-ios-runtime-demangle-watchdog] Full-screen overlay shown while the
/// kernel is booting or has failed to boot.
///
/// Extracted to a top-level struct to cut the type tree at a struct boundary.
/// Without this, the switch/case + ZStack + VStack hierarchy would add
/// several levels of depth to AIChatView.body's mangled type, contributing
/// to the runtime type-metadata demangle watchdog timeout on cold launch.
struct KernelBootOverlayView: View {
    let status: KernelStatus

    var body: some View {
        Group {
            switch status {
            case .booting:
                ZStack {
                    ChatColors.background
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        LoadingDotsView(dotSize: 9, color: ChatColors.secondaryText)
                            .frame(height: 20)
                        Text("Booting Kernel")
                            .font(.subheadline)
                            .foregroundStyle(ChatColors.secondaryText)
                    }
                }
                .transition(.opacity)
            case .failed(let msg):
                ZStack {
                    ChatColors.background
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                        Text(msg)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .transition(.opacity)
            default:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: status)
    }
}
