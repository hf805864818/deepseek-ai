package com.openminis.app.agent

import org.json.JSONObject

/**
 * Spec-confirmation gate for 深度龙虾Ai (Deep Agent Mode) — Phase F (Spec 模式).
 *
 * Sits on top of PlanGate / VerifyGate: after a workflow passes verification,
 * if the optional Spec Mode switch is ON (`deepModeEnabled && specModeEnabled`),
 * the client enters a SPEC_WRITING phase where the model formalizes the work
 * into three documents via `file_write`:
 *   - spec.md      (goal / scope / feature list / acceptance criteria)
 *   - checklist.md (verification checklist)
 *   - tasks.md     (task breakdown, marking parallel tasks with [PARALLEL])
 * The model then appends the `<<SPEC_STATE>>` sentinel; the client harvests the
 * three product paths and moves to SPEC_REVIEWING so the user can review.
 *
 * State contract:
 *   IDLE → (verify passed + spec mode on) → SPEC_WRITING (WorkflowPhase)
 *   SPEC_WRITING + SPEC_STATE sentinel → AWAITING_REVIEW (this gate)
 *   AWAITING_REVIEW → approve → APPROVED
 *   AWAITING_REVIEW → reject → IDLE (workflow finishes, no execution)
 *   AWAITING_REVIEW → edit → back to SPEC_WRITING (bounded by MAX_EDIT_ROUNDS)
 *
 * Fail-safe: if the model never emits the sentinel, the writing loop is bounded
 * by MAX_AGENT_TURNS, and reviewing is only entered when the sentinel appears.
 * Everything is memory-only and gated on `deepModeEnabled && specModeEnabled`,
 * so disabling either switch leaves zero residue and the 4-state plan →
 * execute → verify → idle workflow is completely unchanged.
 */
object SpecGate {

    /** Fenced / inline marker the deep-mode fragment tells the model to append
     * at the END of the spec-writing turn. */
    const val SPEC_MARKER = "<<SPEC_STATE>>"

    /** Hard cap on spec regeneration rounds per workflow. */
    const val MAX_EDIT_ROUNDS = 2

    /** Product artifact roles. */
    const val ROLE_SPEC = "spec"
    const val ROLE_CHECKLIST = "checklist"
    const val ROLE_TASKS = "tasks"

    /** Product artifact file names, in canonical (stable) order. */
    private val PRODUCT_FILE_NAMES = listOf("spec.md", "checklist.md", "tasks.md")

    enum class State {
        IDLE,
        AWAITING_REVIEW,
        APPROVED,
    }

    /** A detected spec product artifact path + its role. */
    data class SpecFile(
        val role: String,
        val name: String,
        val path: String,
    )

    /** Canonical file name for a role. Empty for unknown roles. */
    fun fileNameForRole(role: String): String = when (role) {
        ROLE_SPEC -> "spec.md"
        ROLE_CHECKLIST -> "checklist.md"
        ROLE_TASKS -> "tasks.md"
        else -> ""
    }

    /** Map a product file name to its role, or null if it isn't a spec product. */
    fun roleForFileName(name: String): String? = when (name.lowercase()) {
        "spec.md" -> ROLE_SPEC
        "checklist.md" -> ROLE_CHECKLIST
        "tasks.md" -> ROLE_TASKS
        else -> null
    }

    /**
     * Harvest the spec product paths from the file_write calls of the current
     * agent-loop run. Each entry is a `(toolName, toolArgsJson)` pair; only
     * `file_write` calls whose `path` ends in a product file name are kept.
     * Duplicates by role keep the LAST occurrence (latest write wins).
     */
    fun detectSpecFiles(writes: List<Pair<String, String>>): List<SpecFile> {
        val byRole = LinkedHashMap<String, SpecFile>()
        for ((toolName, argsJson) in writes) {
            if (toolName != "file_write") continue
            val args = try {
                JSONObject(argsJson)
            } catch (_: Exception) {
                continue
            }
            val path = args.optString("path", "").trim()
            if (path.isBlank()) continue
            val role = roleForFileName(path.substringAfterLast('/'))
            if (role != null) {
                byRole[role] = SpecFile(
                    role = role,
                    name = fileNameForRole(role),
                    path = path,
                )
            }
        }
        // Return in canonical order (spec, checklist, tasks).
        val out = mutableListOf<SpecFile>()
        for (name in PRODUCT_FILE_NAMES) {
            val role = roleForFileName(name) ?: continue
            byRole[role]?.let { out.add(it) }
        }
        return out
    }

    /**
     * Return text with the trailing `<<SPEC_STATE>>` line stripped.
     * Returns null if no sentinel was found.
     */
    fun textWithoutSentinel(text: String): String? {
        val idx = text.lastIndexOf(SPEC_MARKER, ignoreCase = true)
        if (idx < 0) return null
        // Walk back to the start of the line containing the marker.
        var lineStart = idx
        while (lineStart > 0 && text[lineStart - 1] != '\n') {
            lineStart--
        }
        return text.substring(0, lineStart).trimEnd()
    }

    /**
     * System prompt fragment explaining the spec-writing mechanism.
     * Injected into the deep-mode fragment only when Spec Mode is enabled.
     */
    val systemPromptFragment: String
        get() = """
SPECIFICATION (SPEC) MODE — an OPTIONAL phase after verification passes. Only activate it when BOTH deep mode is on AND the user has Spec Mode enabled (the client will already have entered SPEC_WRITING and told you to start):

1. Formalize the completed work into THREE documents with file_write (create_dirs=true):
   • spec.md — goal, scope (in / out), feature list, acceptance criteria
   • checklist.md — a checkable verification checklist derived from the acceptance criteria
   • tasks.md — the task / step breakdown, marking independent (parallel) tasks with [PARALLEL]
2. Keep each document precise and structured markdown. Reuse the actual work you just did — do not invent new requirements.
3. At the END of your turn, after all three files are written, append exactly one line:
   <<SPEC_STATE>>
Do NOT start new execution work during SPEC_WRITING — only write the three specification documents.
"""
}