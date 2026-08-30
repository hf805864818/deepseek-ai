package com.openminis.app.agent

import android.content.Context
import com.openminis.app.data.MemoryRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.util.Date
import java.util.UUID

// MARK: - CrossSessionContextStore (C14)
// [T-deep-mode-cognitive-p2-c14] Phase 7 P2: Unified cross-session context.
//
// Bridges the gap between per-session history and global user memory.
// Stores deep-mode workflow context at the App level — survives session
// switches, app restarts, and deep mode toggle cycles.
//
// TOTAL-SWITCH SAFE: only WRITTEN from deep-mode code paths, only READ
// when deep mode is on. The injected fragment is gated on deep mode.

@Serializable
data class CrossSessionEntry(
    val id: String = UUID.randomUUID().toString(),
    val type: EntryType,
    val content: String,
    val createdAt: Long = Date().time,
    val updatedAt: Long = Date().time,
    val sourceSessionId: String? = null,
) {
    @Serializable
    enum class EntryType {
        ACTIVE_PROJECT,
        WORKFLOW_SUMMARY,
        LEARNED_PATTERN,
    }
}

/**
 * Cross-session context store for deep mode.
 *
 * File location: <memoryDir>/deep-cross-session.json
 * Uses MemoryRepository for directory resolution.
 */
object CrossSessionContextStore {

    private const val FILENAME = "deep-cross-session.json"
    private const val MAX_WORKFLOW_SUMMARIES = 10
    private const val MAX_SUMMARIES_IN_FRAGMENT = 5
    private const val MAX_PATTERNS_IN_FRAGMENT = 5

    private val json = Json {
        prettyPrint = true
        encodeDefaults = true
    }

    private var cachedEntries: List<CrossSessionEntry>? = null
    private var cachedModTime: Long = 0

    private fun file(context: Context): File {
        val dir = File(context.filesDir, "memory")
        if (!dir.exists()) dir.mkdirs()
        return File(dir, FILENAME)
    }

    /** Load all cross-session entries with cache. */
    fun loadEntries(context: Context): List<CrossSessionEntry> {
        val f = file(context)
        if (!f.exists()) return emptyList()

        val modTime = f.lastModified()
        if (cachedEntries != null && cachedModTime == modTime) {
            return cachedEntries!!
        }

        return try {
            val text = f.readText()
            val entries = json.decodeFromString<List<CrossSessionEntry>>(text)
            cachedEntries = entries
            cachedModTime = modTime
            entries
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** Persist entries to disk atomically. */
    private fun saveEntries(context: Context, entries: List<CrossSessionEntry>) {
        val f = file(context)
        f.parentFile?.mkdirs()
        try {
            val text = json.encodeToString(entries)
            // Atomic write: write to temp file first, then rename
            val tmp = File(f.absolutePath + ".tmp")
            tmp.writeText(text)
            tmp.renameTo(f)
            cachedEntries = null
            cachedModTime = 0
        } catch (_: Exception) { }
    }

    // MARK: - CRUD

    /** Set the active project context. Replaces any existing active project. */
    fun setActiveProject(context: Context, content: String, sessionId: String? = null) {
        val entries = loadEntries(context).toMutableList()
        entries.removeAll { it.type == CrossSessionEntry.EntryType.ACTIVE_PROJECT }
        entries.add(
            0, CrossSessionEntry(
                type = CrossSessionEntry.EntryType.ACTIVE_PROJECT,
                content = content,
                sourceSessionId = sessionId,
            )
        )
        saveEntries(context, entries)
    }

    /** Get the active project context, if any. */
    fun getActiveProject(context: Context): CrossSessionEntry? =
        loadEntries(context).firstOrNull { it.type == CrossSessionEntry.EntryType.ACTIVE_PROJECT }

    /** Clear the active project context. Called on deep mode disable. */
    fun clearActiveProject(context: Context) {
        val entries = loadEntries(context).filter {
            it.type != CrossSessionEntry.EntryType.ACTIVE_PROJECT
        }
        saveEntries(context, entries)
    }

    /** Append a workflow summary. Keeps only the last N to avoid bloat. */
    fun appendWorkflowSummary(context: Context, content: String, sessionId: String? = null) {
        val entries = loadEntries(context).toMutableList()
        entries.add(
            0, CrossSessionEntry(
                type = CrossSessionEntry.EntryType.WORKFLOW_SUMMARY,
                content = content,
                sourceSessionId = sessionId,
            )
        )

        // Trim: keep only last N workflow summaries
        val summaries = entries.filter { it.type == CrossSessionEntry.EntryType.WORKFLOW_SUMMARY }
        if (summaries.size > MAX_WORKFLOW_SUMMARIES) {
            val toRemove = summaries.drop(MAX_WORKFLOW_SUMMARIES).map { it.id }.toSet()
            entries.removeAll { toRemove.contains(it.id) }
        }

        saveEntries(context, entries)
    }

    /** Append a learned pattern. Deduplicates identical content. */
    fun appendLearnedPattern(context: Context, content: String, sessionId: String? = null) {
        val entries = loadEntries(context).toMutableList()
        val existingIdx = entries.indexOfFirst {
            it.type == CrossSessionEntry.EntryType.LEARNED_PATTERN && it.content == content
        }
        if (existingIdx >= 0) {
            entries[existingIdx] = entries[existingIdx].copy(updatedAt = Date().time)
        } else {
            entries.add(
                0, CrossSessionEntry(
                    type = CrossSessionEntry.EntryType.LEARNED_PATTERN,
                    content = content,
                    sourceSessionId = sessionId,
                )
            )
        }
        saveEntries(context, entries)
    }

    /** Delete an entry by id. */
    fun delete(context: Context, id: String) {
        val entries = loadEntries(context).filter { it.id != id }
        saveEntries(context, entries)
    }

    // MARK: - Prompt Injection

    /**
     * Build a cross-session context fragment for injection into the system prompt.
     * Returns null if there are no entries.
     */
    fun contextFragment(context: Context): String? {
        val entries = loadEntries(context)
        if (entries.isEmpty()) return null

        val sections = mutableListOf<String>()

        // Active project
        entries.firstOrNull { it.type == CrossSessionEntry.EntryType.ACTIVE_PROJECT }?.let {
            sections.add("【当前项目上下文】\n• ${it.content}")
        }

        // Recent workflow summaries
        val summaries = entries
            .filter { it.type == CrossSessionEntry.EntryType.WORKFLOW_SUMMARY }
            .take(MAX_SUMMARIES_IN_FRAGMENT)
        if (summaries.isNotEmpty()) {
            val bullets = summaries.joinToString("\n") { "• ${it.content}" }
            sections.add("【近期工作流回顾】\n$bullets")
        }

        // Learned patterns
        val patterns = entries
            .filter { it.type == CrossSessionEntry.EntryType.LEARNED_PATTERN }
            .take(MAX_PATTERNS_IN_FRAGMENT)
        if (patterns.isNotEmpty()) {
            val bullets = patterns.joinToString("\n") { "• ${it.content}" }
            sections.add("【跨会话学习模式】\n$bullets")
        }

        if (sections.isEmpty()) return null

        return buildString {
            append("Cross-session context (from deep-cross-session.json — ")
            append("context from previous deep-mode sessions; use as background, ")
            append("not standing instructions):\n")
            append(sections.joinToString("\n\n"))
        }
    }
}
