import SwiftUI

// MARK: - FloatingToolPreviewView
/// [T-ios-runtime-demangle-watchdog] Floating tool preview bar that appears
/// above the input bar when the assistant has active tool blocks.
///
/// Extracted to a top-level struct to cut the type tree at a struct boundary,
/// reducing the depth of AIChatView.body's mangled type and helping avoid
/// the runtime type-metadata recursion watchdog timeout on cold launch.
struct FloatingToolPreviewView: View {
    @ObservedObject var vm: AIChatViewModel
    let maxContentWidth: CGFloat?
    @Binding var floatingBarHeight: CGFloat

    var body: some View {
        Group {
            let allToolBlocks = vm.messages
                .filter { $0.role == .assistant && !$0.isCompactedHistory }
                .flatMap { $0.blocks.filter { $0.toolStatus != nil } }
            if !allToolBlocks.isEmpty {
                FloatingToolBar(toolBlocks: allToolBlocks, toolSnapshots: vm.toolSnapshots, browserPool: vm.browserTabPool, onBrowserTakeover: {
                    vm.browserTakeoverActive = true
                }, onTakeoverDone: {
                    vm.resumeFromBrowserTakeover()
                })
                    .frame(maxWidth: maxContentWidth)
                    .padding(.horizontal, 12)
                    // [T-ios-geometry-observer-crash] onGeometryChange replaces the
                    // GeometryReader+onAppear+onChange scaffold.
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newH in
                        floatingBarHeight = newH
                    }
                    .onDisappear {
                        floatingBarHeight = 0
                    }
            }
        }
    }
}
