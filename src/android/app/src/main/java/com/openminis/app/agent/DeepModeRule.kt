package com.openminis.app.agent

// MARK: - DeepModeRule
// Phase 3: Scoped behavior rule for 深度龙虾Ai.
//
// Each rule has a YAML frontmatter block (delimited by `---`) that carries
// metadata (id / description / alwaysApply / globs / keywords) followed by
// a free-form Markdown body. This mirrors SoulStore's frontmatter pattern
// so the parser style is consistent across the codebase.
//
// Rules are matched against a "scope context" (file paths mentioned in the
// conversation + keywords from the user's input). A rule applies when:
//   - alwaysApply == true, OR
//   - any glob pattern matches a file path in scope, OR
//   - any keyword appears in the user's latest message.

/** A single scoped rule parsed from deep-rules.md. */
data class DeepModeRule(
    val id: String,
    val description: String,
    val alwaysApply: Boolean,
    val globs: List<String>,
    val keywords: List<String>,
    val body: String,
) {
    companion object {
        const val FRONTMATTER_DELIMITER = "---"
    }
}

/**
 * Scope context used to determine which rules apply to the current turn.
 * Mirrors iOS `DeepModeScopeContext`.
 */
data class DeepModeScopeContext(
    /** File paths mentioned in the conversation (from tool results, user input, etc.). */
    val filePaths: List<String> = emptyList(),
    /** Keywords extracted from the user's latest message (lowercased). */
    val userKeywords: List<String> = emptyList(),
    /** Current DeepMode intensity level — gates which rules are visible. */
    val level: DeepModeLevel = DeepModeLevel.STANDARD,
)

// MARK: - Parser

object DeepModeRuleParser {

    /**
     * Parse the full content of deep-rules.md into an array of scoped rules.
     *
     * Backward-compatible: if the file has no frontmatter at all (legacy
     * format), the entire content is treated as a single rule with
     * `alwaysApply: true` and an auto-generated id.
     */
    fun parse(content: String): List<DeepModeRule> {
        val trimmed = content.trimIndent().trim()
        if (trimmed.isEmpty()) return emptyList()

        // Legacy format: no leading frontmatter → treat whole file as one always-apply rule.
        if (!trimmed.startsWith("---")) {
            return listOf(
                DeepModeRule(
                    id = "legacy-default",
                    description = "Legacy flat rules (pre-Phase-3 format)",
                    alwaysApply = true,
                    globs = emptyList(),
                    keywords = emptyList(),
                    body = trimmed,
                )
            )
        }

        // Split on `---` frontmatter boundaries.
        val lines = trimmed.lines()
        val rules = mutableListOf<DeepModeRule>()
        var i = 0
        val n = lines.size

        while (i < n) {
            // Find opening ---
            if (lines[i].trim() != "---") {
                i++
                continue
            }
            i++ // skip opening ---

            // Collect frontmatter lines until closing ---
            val frontmatterLines = mutableListOf<String>()
            while (i < n && lines[i].trim() != "---") {
                frontmatterLines.add(lines[i])
                i++
            }
            if (i >= n) break // malformed — no closing ---
            i++ // skip closing ---

            // Collect body lines until next --- or EOF
            val bodyLines = mutableListOf<String>()
            while (i < n && lines[i].trim() != "---") {
                bodyLines.add(lines[i])
                i++
            }

            val frontmatter = parseFrontmatter(frontmatterLines)
            val body = bodyLines.joinToString("\n").trimEnd()

            if (body.isNotEmpty() || frontmatter.id.isNotEmpty()) {
                rules.add(
                    DeepModeRule(
                        id = frontmatter.id.ifEmpty { "rule-${rules.size}" },
                        description = frontmatter.description,
                        alwaysApply = frontmatter.alwaysApply,
                        globs = frontmatter.globs,
                        keywords = frontmatter.keywords,
                        body = body,
                    )
                )
            }
        }

        return rules
    }

    /** Filter rules to only those matching the given scope context. */
    fun matchingRules(rules: List<DeepModeRule>, context: DeepModeScopeContext): List<DeepModeRule> {
        return rules.filter { rule ->
            if (rule.alwaysApply) return@filter true

            // Check glob matches against file paths
            for (glob in rule.globs) {
                for (path in context.filePaths) {
                    if (globMatches(glob, path)) return@filter true
                }
            }

            // Check keyword matches against user input keywords (case-insensitive)
            val userKeywordsLower = context.userKeywords.map { it.lowercase() }
            for (kw in rule.keywords) {
                if (userKeywordsLower.any { it.contains(kw.lowercase()) || kw.lowercase().contains(it) }) {
                    return@filter true
                }
            }

            false
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private data class Frontmatter(
        val id: String = "",
        val description: String = "",
        val alwaysApply: Boolean = false,
        val globs: List<String> = emptyList(),
        val keywords: List<String> = emptyList(),
    )

    private fun parseFrontmatter(lines: List<String>): Frontmatter {
        var id = ""
        var description = ""
        var alwaysApply = false
        var globs = emptyList<String>()
        var keywords = emptyList<String>()

        for (rawLine in lines) {
            val line = rawLine.trim()
            if (line.isEmpty() || line.startsWith("#")) continue

            val colonIdx = line.indexOf(':')
            if (colonIdx < 0) continue

            val key = line.substring(0, colonIdx).trim()
            val value = line.substring(colonIdx + 1).trim()

            when (key.lowercase()) {
                "id" -> id = value
                "description" -> description = value.trim('"', '\'')
                "alwaysapply" -> alwaysApply = value.equals("true", ignoreCase = true) || value == "1"
                "globs" -> globs = parseListValue(value)
                "keywords" -> keywords = parseListValue(value)
            }
        }

        return Frontmatter(id, description, alwaysApply, globs, keywords)
    }

    /** Parse a YAML list value like `["a", "b"]` or `a, b, c` */
    private fun parseListValue(value: String): List<String> {
        val v = value.trim()
        if (v.startsWith('[') && v.endsWith(']')) {
            val inner = v.substring(1, v.length - 1).trim()
            if (inner.isEmpty()) return emptyList()
            return inner.split(',').map { it.trim().trim('"', '\'') }.filter { it.isNotEmpty() }
        }
        // Fallback: comma-separated
        return v.split(',').map { it.trim() }.filter { it.isNotEmpty() }
    }

    /** Simple glob matching: `*` matches any chars except `/`, `**` matches any chars including `/`. */
    private fun globMatches(glob: String, path: String): Boolean {
        // Convert glob to regex
        val regex = buildString {
            append('^')
            var i = 0
            while (i < glob.length) {
                when (glob[i]) {
                    '*' -> {
                        if (i + 1 < glob.length && glob[i + 1] == '*') {
                            append(".*")  // ** matches everything
                            i += 2
                        } else {
                            append("[^/]*")  // * matches anything except /
                            i++
                        }
                    }
                    '?' -> {
                        append("[^/]")
                        i++
                    }
                    '.', '+', '(', ')', '[', ']', '{', '}', '^', '$', '|', '\\' -> {
                        append('\\')
                        append(glob[i])
                        i++
                    }
                    else -> {
                        append(glob[i])
                        i++
                    }
                }
            }
            append('$')
        }
        return Regex(regex, RegexOption.IGNORE_CASE).matches(path) ||
               Regex(regex, RegexOption.IGNORE_CASE).matches(path.substringAfterLast('/'))
    }
}
