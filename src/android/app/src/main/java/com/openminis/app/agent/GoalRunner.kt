package com.openminis.app.agent

/**
 * Goal auto-continuation for 深度龙虾Ai (Deep Agent Mode) — Layer C.
 *
 * The deep-mode fragment tells the model to end each multi-step turn with a
 * tiny sentinel line, and the client reads that sentinel at the turn's end
 * to decide whether to auto-continue (up to a hard cap) or stop.
 *
 * The sentinel contract:
 *   <<GOAL_STATE>> done                          → task fully complete
 *   <<GOAL_STATE>> pending: <next step>          → incomplete; auto-continue
 *   <<GOAL_STATE>> need_more_context: <reason>   → [C10] stop & ask user
 *
 * Every layer is fail-safe: if the model never emits the sentinel (or writes
 * an unrecognized token), `parse` returns null and nothing continues — control
 * degrades to the pre-existing "one turn, then stop" behavior.
 */
object GoalRunner {

    enum class ParseResult {
        DONE,
        PENDING,
        NEED_MORE_CONTEXT,
    }

    data class ParsedSentinel(
        val result: ParseResult,
        val reason: String? = null,
    )

    const val MARKER = "<<GOAL_STATE>>"

    /** Hard cap on auto-continuation rounds per user prompt. */
    const val MAX_AUTO_ROUNDS = 3

    /**
     * Parse the trailing sentinel from a completed turn's visible text.
     * Returns null when there is no recognized sentinel (no-op).
     * Matches the LAST occurrence so a plan/citation that quotes the marker
     * up-stream doesn't shadow the final status.
     */
    fun parse(text: String): ParsedSentinel? {
        val idx = text.lastIndexOf(MARKER, ignoreCase = true)
        if (idx < 0) return null

        val token = text.substring(idx + MARKER.length)
            .trim()
            .lowercase()

        return when {
            token.startsWith("done") -> ParsedSentinel(ParseResult.DONE)
            token.startsWith("pending") -> {
                val rest = token.removePrefix("pending")
                    .trimStart(':', '：', '-', ' ', '\t', '\n')
                ParsedSentinel(
                    ParseResult.PENDING,
                    reason = rest.ifBlank { null },
                )
            }
            token.startsWith("need_more_context") ||
                token.startsWith("need more context") ||
                token.startsWith("need context") -> {
                val prefix = when {
                    token.startsWith("need_more_context") -> "need_more_context"
                    token.startsWith("need more context") -> "need more context"
                    else -> "need context"
                }
                val rest = token.removePrefix(prefix)
                    .trimStart(':', '：', '-', ' ', '\t', '\n')
                ParsedSentinel(
                    ParseResult.NEED_MORE_CONTEXT,
                    reason = rest.ifBlank { null },
                )
            }
            else -> null
        }
    }

    /**
     * Return text with the trailing <<GOAL_STATE>> line stripped.
     * Returns null if no sentinel was found (text unchanged).
     */
    fun textWithoutSentinel(text: String): String? {
        val idx = text.lastIndexOf(MARKER, ignoreCase = true)
        if (idx < 0) return null

        // Walk back to the start of the line containing the marker
        var lineStart = idx
        while (lineStart > 0 && text[lineStart - 1] != '\n') {
            lineStart--
        }

        // Also trim trailing whitespace before the line
        var result = text.substring(0, lineStart).trimEnd()
        return result
    }

    /**
     * System prompt fragment explaining the GOAL_AUTO_CONTINUE mechanism.
     * Injected only when deep mode is enabled.
     */
    val systemPromptFragment: String
        get() = """
GOAL AUTO-CONTINUE — at the very END of a turn where you used tools, append exactly one line (and do NOT put other text after it):
  • <<GOAL_STATE>> done   (the task is fully complete)
  • <<GOAL_STATE>> pending: <one-line next step>   (still incomplete; the client will auto-continue)

This lets the agent keep working across multiple turns without waiting for the user to press "continue" each time. The client will automatically send a system reminder and start the next round.

Important rules:
- Only emit <<GOAL_STATE>> on turns where you actually called tools. On pure-text reply turns, do NOT include any sentinel.
- When all work is done, emit <<GOAL_STATE>> done and give the user a clear summary.
- Do NOT put other text after the <<GOAL_STATE>> line — it must be the very last line of your reply.
- The hard cap is $MAX_AUTO_ROUNDS auto-continue rounds per user message. Use them wisely.
"""
}
