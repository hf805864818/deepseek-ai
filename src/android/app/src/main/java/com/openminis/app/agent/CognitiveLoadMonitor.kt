package com.openminis.app.agent

// MARK: - CognitiveLoadMonitor (C9)
// [T-deep-mode-cognitive-p2-c9] Phase 6 P2: Cognitive load real-time monitoring.
//
// Combines two signal sources:
//   1. Model-emitted sentinel: <<COGNITIVE_LOAD>> with level (low/medium/high/critical)
//   2. Client-computed metrics: context saturation, tool count, verify failures, etc.
//
// Merged by taking the MAX of both — prevents the model from under-reporting load.
//
// TOTAL-SWITCH SAFE: only invoked from deep-mode code paths.

enum class CognitiveLoadLevel(val rawValue: Int) {
    NONE(0),
    LOW(1),
    MEDIUM(2),
    HIGH(3),
    CRITICAL(4);

    val displayName: String
        get() = when (this) {
            NONE -> ""
            LOW -> "低"
            MEDIUM -> "中"
            HIGH -> "高"
            CRITICAL -> "严重"
        }

    val colorHint: String
        get() = when (this) {
            NONE -> "#8E8E93"
            LOW -> "#34C759"
            MEDIUM -> "#FF9500"
            HIGH -> "#FF3B30"
            CRITICAL -> "#FF2D55"
        }

    companion object {
        fun fromRaw(raw: Int): CognitiveLoadLevel =
            values().firstOrNull { it.rawValue == raw } ?: NONE
    }
}

data class CognitiveLoadSignal(
    val level: CognitiveLoadLevel,
    val note: String? = null,
)

data class CognitiveLoadState(
    val level: CognitiveLoadLevel,
    val modelAssessed: CognitiveLoadLevel,
    val clientComputed: CognitiveLoadLevel,
    val note: String? = null,
) {
    companion object {
        val empty = CognitiveLoadState(
            level = CognitiveLoadLevel.NONE,
            modelAssessed = CognitiveLoadLevel.NONE,
            clientComputed = CognitiveLoadLevel.NONE,
            note = null,
        )
    }
}

object CognitiveLoadMonitor {

    const val MARKER = "<<COGNITIVE_LOAD>>"

    /**
     * Parse the cognitive load sentinel from model output text.
     * Returns null when no sentinel is found.
     */
    fun parseSentinel(text: String): CognitiveLoadSignal? {
        val idx = text.lastIndexOf(MARKER, ignoreCase = true)
        if (idx < 0) return null

        val token = text.substring(idx + MARKER.length)
            .trim()
            .lowercase()

        return when {
            token.startsWith("critical") -> CognitiveLoadSignal(
                CognitiveLoadLevel.CRITICAL,
                extractNote(token, "critical"),
            )
            token.startsWith("high") -> CognitiveLoadSignal(
                CognitiveLoadLevel.HIGH,
                extractNote(token, "high"),
            )
            token.startsWith("medium") -> CognitiveLoadSignal(
                CognitiveLoadLevel.MEDIUM,
                extractNote(token, "medium"),
            )
            token.startsWith("low") -> CognitiveLoadSignal(
                CognitiveLoadLevel.LOW,
                extractNote(token, "low"),
            )
            else -> null
        }
    }

    private fun extractNote(token: String, keyword: String): String? {
        val rest = token.removePrefix(keyword)
            .trimStart(':', '：', '-', ' ', '\t', '\n')
        return rest.ifBlank { null }
    }

    /**
     * Remove the cognitive load sentinel line from text (for display).
     * Returns null if no sentinel was found.
     */
    fun textWithoutSentinel(text: String): String? {
        if (parseSentinel(text) == null) return null
        val idx = text.lastIndexOf(MARKER, ignoreCase = true)
        if (idx < 0) return null

        // Walk back to start of line
        var lineStart = idx
        while (lineStart > 0 && text[lineStart - 1] != '\n') {
            lineStart--
        }
        // Walk forward to end of line (or end of text)
        var lineEnd = idx
        while (lineEnd < text.length && text[lineEnd] != '\n') {
            lineEnd++
        }

        return text.removeRange(lineStart, lineEnd).trimEnd()
    }

    /**
     * Compute client-side cognitive load from objective metrics.
     */
    fun computeClientLoad(
        contextTokens: Int = 0,
        maxContextTokens: Int = 0,
        toolCallCount: Int = 0,
        workflowStepCount: Int = 0,
        verifyFailures: Int = 0,
        goalRunnerRoundsUsed: Int = 0,
    ): CognitiveLoadLevel {
        var level = CognitiveLoadLevel.LOW

        // Context saturation
        if (maxContextTokens > 0) {
            val ratio = contextTokens.toDouble() / maxContextTokens.toDouble()
            level = when {
                ratio >= 0.85 -> maxOf(level, CognitiveLoadLevel.CRITICAL)
                ratio >= 0.70 -> maxOf(level, CognitiveLoadLevel.HIGH)
                ratio >= 0.50 -> maxOf(level, CognitiveLoadLevel.MEDIUM)
                else -> level
            }
        }

        // Tool call count
        level = when {
            toolCallCount >= 20 -> maxOf(level, CognitiveLoadLevel.CRITICAL)
            toolCallCount >= 12 -> maxOf(level, CognitiveLoadLevel.HIGH)
            toolCallCount >= 6 -> maxOf(level, CognitiveLoadLevel.MEDIUM)
            else -> level
        }

        // Workflow complexity
        level = when {
            workflowStepCount >= 10 -> maxOf(level, CognitiveLoadLevel.HIGH)
            workflowStepCount >= 6 -> maxOf(level, CognitiveLoadLevel.MEDIUM)
            else -> level
        }

        // Verify failures
        level = when {
            verifyFailures >= 2 -> maxOf(level, CognitiveLoadLevel.HIGH)
            verifyFailures >= 1 -> maxOf(level, CognitiveLoadLevel.MEDIUM)
            else -> level
        }

        // GoalRunner exhaustion
        if (goalRunnerRoundsUsed >= 3) {
            level = maxOf(level, CognitiveLoadLevel.MEDIUM)
        }

        return level
    }

    /**
     * Merge model-assessed and client-computed signals.
     * Takes the MAX of both so the more conservative estimate wins.
     */
    fun merge(
        modelAssessed: CognitiveLoadLevel?,
        clientComputed: CognitiveLoadLevel,
        note: String? = null,
    ): CognitiveLoadState {
        val model = modelAssessed ?: CognitiveLoadLevel.NONE
        val merged = maxOf(model, clientComputed)
        return CognitiveLoadState(
            level = merged,
            modelAssessed = model,
            clientComputed = clientComputed,
            note = note,
        )
    }

    /**
     * System prompt fragment explaining the cognitive load sentinel.
     * Injected at medium+ deep mode level.
     */
    val systemPromptFragment: String
        get() = """
COGNITIVE LOAD SELF-ASSESSMENT — every 3-5 tool calls, briefly assess your own cognitive load and append one line:
  • <<COGNITIVE_LOAD>> low   — cruising, on track
  • <<COGNITIVE_LOAD>> medium: <one-line note>   — some complexity, managing
  • <<COGNITIVE_LOAD>> high: <one-line note>   — struggling, may need to simplify
  • <<COGNITIVE_LOAD>> critical: <one-line note>   — overwhelmed, likely to make mistakes

Be honest. If you report high or critical, you should also simplify your approach or ask for guidance.
"""
}
