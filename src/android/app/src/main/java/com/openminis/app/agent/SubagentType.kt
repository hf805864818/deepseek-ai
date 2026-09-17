package com.openminis.app.agent

// [T-subagent-type] Phase C C1: The specialized role a subagent is asked to
// perform. The parent's `task_dispatch` call names a type; the subagent then
// receives a typed system-prompt hint that tunes its tool emphasis and the
// shape of its returned summary. Total-switch safe: only ever referenced from
// the `task_dispatch` branch, which is reachable only when deepModeEnabled.
//
// Mirrors iOS `SubagentType` (SubagentSession.swift).
enum class SubagentType(val value: String) {
    GENERAL("general"),
    RESEARCH("research"),
    ANALYZE("analyze"),
    IMPLEMENT("implement"),
    FIX("fix");

    /// A short system-prompt hint injected into the subagent's system prompt,
    /// telling it how to behave and what shape of output to return.
    /// Mirrors iOS `SubagentType.systemPromptHint`.
    val systemPromptHint: String
        get() = when (this) {
            GENERAL ->
                "You are a GENERAL-PURPOSE subagent. Adapt your approach to the task: gather what you need, do the work, and return a concise, structured summary."
            RESEARCH ->
                "You are a RESEARCH subagent. Prioritize reading files, searching the codebase, and gathering factual evidence. Return findings as a concise bulleted list with source references (file paths), not open-ended prose."
            ANALYZE ->
                "You are an ANALYSIS subagent. Break the subject into parts, compare options, weigh trade-offs, and flag risks. Return a structured assessment with clear conclusions, not just a description."
            IMPLEMENT ->
                "You are an IMPLEMENTATION subagent. Prioritize making concrete file edits. After editing, verify your changes (read back / run) before summarizing. Return a short summary of files changed and what each change does."
            FIX ->
                "You are a FIX subagent. Prioritize diagnosing the ROOT CAUSE before patching. Apply a targeted fix, then verify it resolves the issue. Return a summary of the root cause, the fix, and how you verified it."
        }

    companion object {
        /** The enum values as strings, used for the `subagent_type` tool param. */
        val enumValues: List<String> = entries.map { it.value }

        /** Fall back to [GENERAL] for unknown/missing values. Mirrors iOS `SubagentType(rawValue:) ?? .general`. */
        fun fromValue(raw: String): SubagentType =
            entries.firstOrNull { it.value == raw } ?: GENERAL
    }
}