package com.openminis.app.ui.chat

// [T-deep-mode-phase-d] Phase D: Inline visualization (render_widget) renderer
// for Android — iOS parity with RenderWidgetView.swift.
//
// Renders the raw tool content (inline SVG for diagram/chart/comparison, or a
// self-contained HTML fragment for interactive) as an inline WebView card in
// the chat stream. Total-switch safe: this card is only produced for tool
// blocks whose toolName == "render_widget", which only exist when the tool was
// invoked — and the tool is only registered in deep mode.

import android.annotation.SuppressLint
import android.webkit.WebView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView

/**
 * iOS-parity inline card for render_widget tool output. Decides whether the
 * content is SVG or HTML and sizes the WebView accordingly.
 */
@Composable
internal fun WidgetInlineCard(content: String) {
    val context = LocalContext.current
    val (html, height) = remember(content) { buildWidgetDocument(content) }
    val cardBg = Color(0xFFF2F2F7).copy(alpha = 0.6f)

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 6.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(cardBg, RoundedCornerShape(12.dp))
            .border(0.5.dp, Color.Black.copy(alpha = 0.08f), RoundedCornerShape(12.dp)),
        contentAlignment = Alignment.Center,
    ) {
        AndroidView(
            factory = { ctx ->
                @SuppressLint("SetJavaScriptEnabled")
                WebView(ctx).apply {
                    settings.javaScriptEnabled = true
                    isOpaque = false
                    setBackgroundColor(android.graphics.Color.TRANSPARENT)
                    loadDataWithBaseURL(null, html, "text/html", "utf-8", null)
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 120.dp, max = height),
        )
    }
}

/** Wraps raw SVG/HTML fragment into a full self-contained document and picks a height. */
private fun buildWidgetDocument(raw: String): Pair<String, Dp> {
    val trimmed = raw.trim()
    val lower = trimmed.lowercase()
    val isHtmlDoc = lower.contains("<html") || lower.contains("<!doctype")

    val html: String
    val height: Dp
    when {
        isHtmlDoc -> {
            html = trimmed
            height = 380.dp
        }
        lower.startsWith("<svg") -> {
            html = """
            <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
            <style>html,body{margin:0;padding:0;background:transparent;}body{display:flex;align-items:center;justify-content:center;min-height:100vh;}
            svg{max-width:100%;height:auto;display:block;}</style></head><body>$trimmed</body></html>
            """.trimIndent()
            height = 260.dp
        }
        else -> {
            html = """
            <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
            <style>html,body{margin:0;padding:12px;background:transparent;font-family:-apple-system,'PingFang SC',sans-serif;}
            table{border-collapse:collapse;width:100%;}td,th{border:1px solid #e2e2e2;padding:6px 10px;font-size:13px;text-align:left;}
            th{background:#f4f4f4;}</style></head><body>$trimmed</body></html>
            """.trimIndent()
            height = 260.dp
        }
    }
    return html to height
}