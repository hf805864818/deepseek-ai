package com.openminis.app.agent

import android.util.Log
import java.io.File
import java.util.concurrent.atomic.AtomicReference
import kotlin.system.measureTimeMillis

// MARK: - DeepModeStore
/**
 * Persistent behavior-rule file for 深度龙虾Ai (Deep Agent Mode).
 *
 * Phase 3 evolution: `deep-rules.md` uses a multi-section YAML frontmatter
 * format where each rule is a `---`-delimited section with metadata
 * (id / description / alwaysApply / globs / keywords) and a Markdown body.
 * This mirrors `SoulStore`'s frontmatter pattern for consistency.
 *
 * The file lives in the memory directory alongside `GLOBAL.md` so it is
 * covered by the same filesystem lifecycle.
 *
 * Backward compatibility: a legacy flat-file (no frontmatter) is parsed as
 * a single `alwaysApply: true` rule, so existing user files keep working.
 */
class DeepModeStore(private val memoryDir: File) {

    companion object {
        private const val TAG = "DeepModeStore"
        private const val RULES_FILE = "deep-rules.md"
        private const val CACHE_TTL_MS = 5000L // 5s TTL, same as iOS [T-perf-stat-cache]
    }

    // MARK: - File location

    val rulesFile: File
        get() = File(memoryDir, RULES_FILE)

    // MARK: - Default rules (Phase 3 scoped format)

    /**
     * Default scoped rules seeded on first run. The five core behavior rules
     * are preserved verbatim (as `alwaysApply: true`) so a fresh install
     * behaves identically to the pre-Phase-3 hard-coded fragment. Additional
     * scoped rules (Android / Python / shell conventions) demonstrate the
     * scope system but only activate when the context matches.
     */
    val defaultRulesBody: String = """
---
id: core-plan-first
alwaysApply: true
description: "Plan before executing non-trivial tasks"
---
1. PLAN FIRST — for non-trivial tasks, state a short numbered plan before acting, then execute it. Skip the plan for trivial single-command tasks.

---
id: core-consult-skills
alwaysApply: true
description: "Consult available skills first"
---
2. CONSULT SKILLS FIRST — check <available_skills> above and follow any matching skill's workflow before improvising a process.

---
id: core-execute-transparently
alwaysApply: true
description: "Prefer concrete tool calls over describing intentions"
---
3. EXECUTE TRANSPARENTLY — prefer concrete tool calls over describing intentions; let the user follow each step.

---
id: core-self-verify
alwaysApply: true
description: "Self-verify results before declaring success"
---
4. SELF-VERIFY — after finishing, re-read the result and fix any errors; do not declare success blindly.

---
id: core-deliver-summary
alwaysApply: true
description: "End with a concise summary of changes"
---
5. DELIVER & SUMMARIZE — end with a concise summary of what changed and anything the user should know.

---
id: android-kotlin-conventions
globs: ["*.kt", "*.kts", "*.java", "*.xml"]
keywords: ["android", "kotlin", "java", "jetpack", "compose", "viewmodel", "apk"]
description: "Android/Kotlin development conventions"
---
Android / Kotlin conventions (apply when working on Android or Kotlin code):
- Use Kotlin coroutines (suspend/Flow) over Executors/Callbacks where possible.
- Follow Kotlin API Design Guidelines (clear names, consistent types, immutable data).
- Prefer data classes and sealed classes for model data.
- Always collect Flows with lifecycle-aware collectors (Lifecycle.repeatOnLifecycle).
- Dispatch UI updates to the main thread; never block the main thread with I/O.
- Use ViewModel + StateFlow for screen state, never mutate UI state from background threads.

---
id: python-conventions
globs: ["*.py"]
keywords: ["python", "pip", "django", "flask", "pandas", "numpy"]
description: "Python development conventions"
---
Python conventions (apply when working on Python code):
- Follow PEP 8 for style (4-space indent, snake_case, 79-char lines).
- Use type hints for function signatures.
- Prefer f-strings over .format() or % formatting.
- Use virtual environments for dependency management.

---
id: shell-safety
globs: ["*.sh", "*.bash", "*.zsh"]
keywords: ["shell", "bash", "script", "terminal", "command line", "linux"]
description: "Shell script safety conventions"
---
Shell safety conventions (apply when writing shell scripts):
- Start scripts with set -euo pipefail for strict error handling.
- Quote variable expansions: "${'$'}var" not ${'$'}var.
- Use printf instead of echo for predictable output.
- Check return codes; don't assume commands succeed silently.
"""

    // MARK: - Cache
    //
    // [T-perf-stat-cache] Thread-safe cached rules with file modification time check.
    // Invalidates cache when the file is modified on disk.
    // 5s TTL avoids synchronous disk stat on the main thread during every send.

    private data class CacheEntry(
        val rules: List<DeepModeRule>,
        val modTime: Long,
        val timestamp: Long,
    )

    private val cacheRef = AtomicReference<CacheEntry?>(null)

    // MARK: - File management

    /**
     * Create `deep-rules.md` with the default scoped rules if it does not
     * already exist. Safe to call on every launch — never overwrites.
     */
    fun ensureExists() {
        val file = rulesFile
        if (file.exists()) return
        try {
            memoryDir.mkdirs()
            file.writeText(defaultRulesBody.trimIndent())
            Log.d(TAG, "Created default deep-rules.md at ${file.absolutePath}")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to create deep-rules.md: ${e.message}")
        }
    }

    /**
     * Load and parse all rules from `deep-rules.md` with caching.
     *
     * Phase 3.4 fix: avoids repeated disk reads and parsing by caching
     * the parsed rules in memory and only re-reading when the file changes.
     */
    fun loadRules(): List<DeepModeRule> {
        ensureExists()

        val now = System.currentTimeMillis()
        val cached = cacheRef.get()

        // Fast path: within TTL, return cached rules without touching disk.
        if (cached != null && now - cached.timestamp < CACHE_TTL_MS) {
            return cached.rules
        }

        val file = rulesFile
        val currentModTime = file.lastModified()

        // Cache hit with mod-time verification
        if (cached != null && cached.modTime == currentModTime && currentModTime > 0) {
            cacheRef.set(cached.copy(timestamp = now))
            return cached.rules
        }

        // File changed or cold cache — reload
        val elapsed = measureTimeMillis {
            val content = try {
                file.readText()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to read deep-rules.md, using defaults: ${e.message}")
                defaultRulesBody.trimIndent()
            }

            val rules = if (content.isBlank()) {
                DeepModeRuleParser.parse(defaultRulesBody.trimIndent())
            } else {
                DeepModeRuleParser.parse(content)
            }

            cacheRef.set(
                CacheEntry(
                    rules = rules,
                    modTime = currentModTime,
                    timestamp = now,
                )
            )
        }

        val rules = cacheRef.get()?.rules ?: emptyList()
        Log.d(TAG, "loadRules: ${rules.size} rules (${elapsed}ms)")
        return rules
    }

    /** Load rules filtered to the given scope context. */
    fun matchingRules(context: DeepModeScopeContext): List<DeepModeRule> {
        return DeepModeRuleParser.matchingRules(loadRules(), context)
    }

    /**
     * Last-known modification time of the rules file (drives cache keying
     * so a rules-file edit invalidates any higher-level cached fragment).
     * Returns null if the file isn't accessible yet.
     */
    fun rulesFileModTime(): Long? {
        return cacheRef.get()?.modTime?.takeIf { it > 0 }
    }

    /**
     * Build the rules fragment string for injection into the system prompt.
     *
     * Phase 3 behavior (deep mode on): only matching rules are injected,
     * each prefixed with its description for clarity.
     */
    fun rulesFragment(context: DeepModeScopeContext): String {
        val rules = matchingRules(context)
        if (rules.isEmpty()) return ""

        val lines = mutableListOf<String>()
        lines.add("Behavior rules (scoped to current context — only matching rules shown):")
        for (rule in rules) {
            if (rule.description.isNotEmpty()) {
                lines.add("— ${rule.description}")
            }
            lines.add(rule.body)
        }
        return lines.joinToString("\n")
    }

    /**
     * Read the current `deep-rules.md` body as a single flat string.
     *
     * Kept for backward compatibility. New code should prefer
     * `loadRules()` or `matchingRules()` for scoped behavior.
     */
    fun loadRulesBody(): String {
        ensureExists()
        return try {
            rulesFile.readText()
        } catch (e: Exception) {
            defaultRulesBody.trimIndent()
        }
    }

    /**
     * Replace the entire rules file content.
     * Used by the settings UI / in-app editor.
     */
    fun saveRulesBody(content: String) {
        try {
            memoryDir.mkdirs()
            rulesFile.writeText(content)
            cacheRef.set(null) // invalidate cache
            Log.d(TAG, "Saved deep-rules.md (${content.length} chars)")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to save deep-rules.md: ${e.message}")
        }
    }

    /** Invalidate the cache (call after external file edits). */
    fun invalidateCache() {
        cacheRef.set(null)
    }
}
