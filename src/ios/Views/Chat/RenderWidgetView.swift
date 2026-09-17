import SwiftUI
import WebKit

/// [T-deep-mode-phase-d] RenderWidgetView — renders an inline visual produced by
/// the `render_widget` tool (Phase D: 对话内可视化).
///
/// The tool returns either raw inline SVG (for diagram / chart / comparison) or a
/// self-contained HTML snippet (for interactive). This view wraps that content in a
/// minimal full document and loads it into a private WKWebView so the diagram renders
/// crisply at any scale and interactive HTML keeps its <script> behavior. It is shown
/// inline in the message stream as a card, NOT saveable as a file.
///
/// Total-switch safe: this view is only reachable from an `AssistantBlock` of kind
/// `.visualization`, and blocks of that kind only exist when `render_widget` was
/// invoked, which in turn only happens in deep mode (the tool is only registered
/// then). When deep mode is off no such blocks are produced.
struct RenderWidgetView: View {
    @ObservedObject var block: AssistantBlock
    @State private var measuredHeight: CGFloat = 0

    private var rawContent: String { block.content }

    /// Best-effort layout estimate used by the collection view's fixed-size
    /// invalidation pass (CollectionViewMessageListV3.swift).
    static func estimatedHeight(for content: String) -> CGFloat {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 120 }
        let isHTML = !trimmed.lowercased().hasPrefix("<svg") && trimmed.lowercased().contains("<html")
        return isHTML ? 380 : 260
    }

    var body: some View {
        VStack(spacing: 0) {
            WidgetWebView(html: Self.documentHTML(for: rawContent))
                .frame(height: measuredHeight > 0 ? measuredHeight : Self.estimatedHeight(for: rawContent))
                .frame(maxWidth: .infinity)
        }
        .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ChatColors.toolBorder.opacity(0.6), lineWidth: 0.5)
        )
        .contextMenu {
            Button {
                UIPasteboard.general.string = block.content
            } label: {
                Label(AppLocalized("Copy Widget Markup"), systemImage: "doc.on.doc")
            }
        }
    }

    /// Wraps raw SVG or HTML fragment as a full self-contained document sized to
    /// the host width, with light styling for a readable inline card.
    private static func documentHTML(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Interactive HTML: assume the caller supplied a full or near-full doc.
        if lower.contains("<html") || lower.contains("<!doctype") {
            return trimmed
        }

        // Raw SVG (or HTML fragment like a <table>/<div>): wrap in a document.
        if lower.hasPrefix("<svg") {
            return """
            <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
            <style>html,body{margin:0;padding:0;background:transparent;}body{display:flex;align-items:center;justify-content:center;min-height:100vh;}
            svg{max-width:100%;height:auto;display:block;}</style></head><body>\(trimmed)</body></html>
            """
        }

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;padding:12px;background:transparent;font-family:-apple-system,'PingFang SC',sans-serif;}
        table{border-collapse:collapse;width:100%;}td,th{border:1px solid #e2e2e2;padding:6px 10px;font-size:13px;text-align:left;}
        th{background:#f4f4f4;}</style></head><body>\(trimmed)</body></html>
        """
    }
}

/// WKWebView bridge that loads the wrapped document and reports its intrinsic
/// content height back so the card can self-size.
private struct WidgetWebView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {}
}