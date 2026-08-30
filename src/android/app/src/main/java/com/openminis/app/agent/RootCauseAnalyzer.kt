package com.openminis.app.agent

import android.content.Context

// MARK: - RootCauseAnalyzer (C13)
// [T-deep-mode-cognitive-p2-c13] Phase 7 P2: Root cause learning.
//
// When verification fails in aggressive mode, instead of just re-entering
// execution, the client first asks the model to analyze the ROOT cause of the
// failure. The model produces a reusable rule wrapped in <<ROOT_CAUSE_RULE>>
// tags, and the client saves it to CrossSessionContextStore as a learned
// pattern so future sessions benefit from the lesson.
//
// TOTAL-SWITCH SAFE: only triggered from deep-mode code paths (VerifyGate
// failure in AGGRESSIVE level). Rule saving goes through
// CrossSessionContextStore which is already gated on deep mode for reads.

object RootCauseAnalyzer {

    const val RULE_MARKER_START = "<<ROOT_CAUSE_RULE>>"
    const val RULE_MARKER_END = "<<ROOT_CAUSE_RULE>>"

    /**
     * Build the root-cause analysis prompt injected when verify fails in
     * aggressive mode. The model should analyze why things went wrong and
     * produce a reusable rule.
     */
    fun buildAnalysisPrompt(failureReason: String?): String {
        return buildString {
            append(
                "<system-reminder>ROOT CAUSE ANALYSIS (C13): "
            )
            append(
                "Verification just failed. Before fixing, analyze the FUNDAMENTAL " +
                    "reason things went wrong — not just the surface symptom."
            )
            append("\n\n")
            append("Ask yourself:\n")
            append("1. Wrong assumption? What did I believe was true that turned out false?\n")
            append("2. Missing step? Did I skip a necessary step or precondition?\n")
            append("3. Platform/environment constraint? Did something about the environment surprise me?\n")
            append("4. Requirement misunderstanding? Did I misinterpret what was needed?\n")
            append("\n")
            append(
                "Then produce ONE reusable rule that would prevent this CLASS of error " +
                    "in the future. Wrap the rule in these exact tags (on separate lines):"
            )
            append("\n$RULE_MARKER_START\n")
            append("<your rule here>\n")
            append("$RULE_MARKER_END\n\n")
            append(
                "After the rule, explain your fix plan and then end with " +
                    "<<GOAL_STATE>> pending: <fix plan> to continue execution."
            )
            if (!failureReason.isNullOrBlank()) {
                append("\n\nFailure reason from verification: $failureReason")
            }
            append("</system-reminder>")
        }
    }

    /**
     * Extract the root cause rule from model output text.
     * Returns the rule text if found, null otherwise.
     */
    fun extractRule(text: String): String? {
        val startIdx = text.indexOf(RULE_MARKER_START)
        if (startIdx < 0) return null

        val afterStart = text.substring(startIdx + RULE_MARKER_START.length)
        val endIdx = afterStart.indexOf(RULE_MARKER_END)
        if (endIdx < 0) return null

        val rule = afterStart.substring(0, endIdx).trim()
        return rule.ifBlank { null }
    }

    /**
     * Save an extracted root cause rule to cross-session context as a
     * learned pattern. This way future sessions benefit from the lesson.
     */
    fun saveRule(context: Context, rule: String) {
        com.openminis.app.agent.CrossSessionContextStore.appendLearnedPattern(
            context, "根因规则：$rule"
        )
    }
}
