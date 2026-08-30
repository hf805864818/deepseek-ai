package com.openminis.app.agent

/**
 * Plan-confirmation gate for 深度龙虾Ai (Deep Agent Mode) — Layer B.
 *
 * When deep mode is on and the agent's first reply to a multi-step task is a
 * plan-only turn (no tool calls, plan wrapped in the fenced `plan` block the
 * deep-mode fragment instructs it to emit), the UI raises a confirm/edit bar
 * instead of silently proceeding.
 *
 * Fail-safe: if the model ignores the instruction and starts acting immediately,
 * `detectPlan` returns null and the state stays idle — a missed gate degrades to
 * the pre-existing "start right away" behavior, never to a stuck state.
 */
object PlanGate {

    enum class State {
        IDLE,
        AWAITING_APPROVAL,
    }

    /** Fenced-block marker the deep-mode fragment tells the model to wrap its plan in. */
    const val PLAN_MARKER = "```plan"

    /**
     * Detect a plan-only turn. Returns the plan text when the turn has no
     * tool calls AND its visible text contains the plan marker; null otherwise.
     */
    fun detectPlan(text: String, hasToolCalls: Boolean): String? {
        if (hasToolCalls) return null
        if (text.isBlank()) return null
        if (!text.contains(PLAN_MARKER, ignoreCase = true)) return null
        return text
    }

    /**
     * System prompt fragment explaining the planning phase.
     * Injected only when deep mode is enabled.
     */
    val systemPromptFragment: String
        get() = """
PLANNING PHASE — on the FIRST turn of a multi-step task, BEFORE calling any tools, output your plan wrapped in a fenced code block:

\`\`\`plan
1. <step 1>
2. <step 2>
...
\`\`\`

Then STOP — do not call any tools on this turn. The client will show the plan to the user for approval. Execution begins only after the user approves.

Rules:
- Only emit a plan on the FIRST turn of a new task. On follow-up turns, go straight to execution.
- The plan block must be the main content of the turn — no tool calls, just the plan and brief context.
- Be specific: list concrete steps, not vague intentions.
- For simple one-step tasks (e.g. "read this file"), skip the plan and go straight to execution.
"""
}
