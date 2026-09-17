package com.openminis.app.agent

/**
 * Client-driven workflow tracking types for 深度龙虾Ai deep mode.
 *
 * These mirror the iOS `WorkflowState.swift` primitives (WorkflowPhase,
 * WorkflowStep) so the Android UI can show a live execution progress
 * capsule with a done/total count and per-step checkmarks.
 *
 * TOTAL-SWITCH SAFE: every consumer MUST gate on `deepModeEnabled`. These
 * types are in-memory only and are never persisted, so toggling the master
 * switch off leaves zero residue in behavior, state, or UI.
 */
enum class WorkflowPhase { IDLE, PLANNING, EXECUTING, VERIFYING }

enum class WorkflowStepStatus { PENDING, ACTIVE, DONE }

data class WorkflowStep(
    /** 1-based index matching the plan's numbered list order. */
    val id: Int,
    val title: String,
    var status: WorkflowStepStatus = WorkflowStepStatus.PENDING,
    /** True when the plan step carried a [PARALLEL] tag (informational). */
    val isParallel: Boolean = false,
)

/**
 * Parses plan text into an ordered list of numbered steps.
 * Pure function: no side effects, safe to call on any thread.
 */
object WorkflowPlanParser {

    /** Extract step titles from plan text. Accepts a fenced ```plan``` block
     * and a bare numbered/bulleted list. Deduplicates on title and collapses
     * empty lines so prose around the list does not produce junk items. */
    fun parseSteps(planText: String): List<WorkflowStep> {
        var text = planText
        // Strip a ```plan ... ``` fence if present.
        val lowered = text.lowercase()
        val fenceStart = lowered.indexOf("```plan")
        if (fenceStart >= 0) {
            val endSearch = text.indexOf("```", startIndex = fenceStart + "```plan".length)
            text = if (endSearch >= 0) {
                text.substring(fenceStart + "```plan".length, endSearch)
            } else {
                text.substring(fenceStart + "```plan".length)
            }
        }

        val steps = mutableListOf<WorkflowStep>()
        val seen = mutableSetOf<String>()

        for (rawLine in text.lines()) {
            val line = rawLine.trim()
            if (line.isEmpty()) continue
            val title = stepTitle(line) ?: continue
            val isParallel = title.contains("[PARALLEL]", ignoreCase = true)
            var cleanTitle = title
            if (isParallel) {
                cleanTitle = title
                    .replace("[PARALLEL]", "", ignoreCase = true)
                    .trim()
            }
            val cleanKey = cleanTitle.lowercase()
            if (!seen.add(cleanKey)) continue
            steps.add(WorkflowStep(id = steps.size + 1, title = cleanTitle, isParallel = isParallel))
        }
        return steps
    }

    /** Returns the cleaned title for a line that reads like a list item, else null. */
    private fun stepTitle(line: String): String? {
        var rest = line
        // Numbered list: "1." , "12)", "3、" with optional spaces.
        val numbered = Regex("^\\s*\\d{1,3}\\s*[.)、]\\s*").find(rest)
        val bullet = Regex("^\\s*[-*•·]\\s*").find(rest)
        if (numbered != null) {
            rest = rest.substring(numbered.range.last + 1)
        } else if (bullet != null) {
            rest = rest.substring(bullet.range.last + 1)
        } else {
            return null
        }
        val title = rest.trim()
        if (title.isEmpty()) return null
        return if (title.length > 120) title.take(120) else title
    }
}