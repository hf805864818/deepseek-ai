package com.openminis.app.agent

/**
 * Self-verification / reflection loop for 深度龙虾Ai — Phase 2.
 *
 * After the model reports `done` on an execution turn, the client forces a
 * self-check phase — run / preview / compare results — and only considers the
 * workflow truly complete when verification passes. If it fails, control
 * returns to execution so the model can fix the issues.
 *
 * Sentinel contract (appended by the model at the END of a verify turn):
 *   <<VERIFY_STATE>> passed                          → verification OK → finish
 *   <<VERIFY_STATE>> failed: <reason + fix plan>     → issues found → re-execute
 *
 * Fail-safe by design:
 *   • No sentinel / unrecognized token → treat as passed (degrade gracefully)
 *   • Verify round budget (default 2) + maxAgentTurns backstop → can't loop forever
 *   • Everything gated on deepModeEnabled; memory-only state, never persisted
 */
object VerifyGate {

    enum class ParseResult {
        PASSED,
        FAILED,
    }

    data class ParsedSentinel(
        val result: ParseResult,
        val reason: String? = null,
    )

    const val MARKER = "<<VERIFY_STATE>>"

    /** Hard cap on verification rounds per workflow. */
    const val MAX_VERIFY_ROUNDS = 2

    /**
     * Parse the trailing verification sentinel from a completed turn's visible
     * text. Returns null when there is no recognized sentinel (degrade to
     * Phase 1 finish). Matches the LAST occurrence.
     */
    fun parse(text: String): ParsedSentinel? {
        val idx = text.lastIndexOf(MARKER, ignoreCase = true)
        if (idx < 0) return null

        val token = text.substring(idx + MARKER.length)
            .trim()
            .lowercase()

        return when {
            token.startsWith("passed") || token.startsWith("pass") || token.startsWith("ok") ->
                ParsedSentinel(ParseResult.PASSED)
            token.startsWith("failed") || token.startsWith("fail") -> {
                val rest = token.removePrefix("failed").removePrefix("fail")
                    .trimStart(':', '：', '-', ' ', '\t', '\n')
                ParsedSentinel(
                    ParseResult.FAILED,
                    reason = rest.ifBlank { null },
                )
            }
            else -> null
        }
    }

    /**
     * Return text with the trailing sentinel line stripped.
     * Returns null if no sentinel was found.
     */
    fun textWithoutSentinel(text: String): String? {
        if (parse(text) == null) return null

        val idx = text.lastIndexOf(MARKER, ignoreCase = true)
        if (idx < 0) return null

        // Walk back to the start of the line containing the marker
        var lineStart = idx
        while (lineStart > 0 && text[lineStart - 1] != '\n') {
            lineStart--
        }

        return text.substring(0, lineStart).trimEnd()
    }

    /**
     * System prompt fragment explaining the self-verification mechanism.
     * Injected only when deep mode is enabled.
     */
    val systemPromptFragment: String
        get() = """
SELF-VERIFICATION — after you finish ALL execution work and emit <<GOAL_STATE>> done, the client will automatically start a verification round. In that round:

1. Review your work: check outputs, run tests, preview results, verify correctness.
2. At the END of the verification turn, append exactly one line:
   • <<VERIFY_STATE>> passed   (everything checks out)
   • <<VERIFY_STATE>> failed: <one-line summary of issues + fix plan>   (problems found — client will re-enter execution)

Verification rules:
- Only use tools during verification to ACTUALLY verify things (run code, read files, check output). Do NOT just write text saying it's fine.
- If you find issues, be specific about what's wrong and how you'll fix it.
- The hard cap is $MAX_VERIFY_ROUNDS verification rounds per workflow. Use them well.
- If verification fails, the client re-enters execution mode — fix the issues, then you'll get another verification round.
"""
}
