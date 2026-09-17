package com.openminis.app.agent

/**
 * Multi-path planner (C12) — 深度龙虾Ai deep mode.
 *
 * When deep mode is on and the model is in the planning phase, the
 * deep mode fragment instructs it to generate multiple candidate paths
 * inside a fenced ```plan``` block, each marked with a `## PATH N:` header,
 * a `RISK:` line and an optional `RECOMMENDED:` line. The client parses these
 * so the UI can offer a Trae-style multi-select of the candidate paths.
 *
 * TOTAL-SWITCH SAFE: only invoked from the plan-gate detection logic, which
 * is itself gated on `deepModeEnabled`. When the master switch is off the
 * model never produces multi-path plans and this object is never called.
 * Zero runtime state, zero persistence.
 */
object MultiPathPlanner {

    /** Header marker for each candidate path. */
    const val PATH_MARKER = "## PATH"

    /** Risk marker within a path block. */
    const val RISK_MARKER = "RISK:"

    /** Recommended-path marker. */
    const val RECOMMEND_MARKER = "RECOMMENDED:"

    /** A single candidate path. */
    data class CandidatePath(
        val index: Int,             // 1-based path number
        val title: String,          // Short title after "## PATH N:"
        val body: String,           // Full plan text for this path
        val rationale: String,      // Why this path, from the model's scoring
        val riskLevel: RiskLevel,
    )

    enum class RiskLevel { LOW, MEDIUM, HIGH }

    sealed class Result {
        /** The plan contains multiple candidate paths. */
        data class MultiPath(val paths: List<CandidatePath>, val recommendedIndex: Int) : Result()

        /** The plan is a standard single-path plan — not multi-path format. */
        object SinglePath : Result()
    }

    /**
     * Parse a plan text to determine if it's a multi-path plan.
     * Returns [Result.SinglePath] if the plan doesn't contain two or more
     * `## PATH` headers (backward compatible with the existing PlanGate).
     */
    fun parse(planText: String): Result {
        val lines = planText.lines()
        val pathLineIndexes = lines.mapIndexedNotNull { i, l ->
            if (l.trimStart().startsWith(PATH_MARKER)) i else null
        }

        if (pathLineIndexes.size < 2) return Result.SinglePath

        val paths = mutableListOf<CandidatePath>()
        var recommendedIndex = 1

        for ((idx, start) in pathLineIndexes.withIndex()) {
            val end = if (idx + 1 < pathLineIndexes.size) pathLineIndexes[idx + 1] else lines.size
            val block = lines.subList(start, end)
            val headerTrimmed = block[0].trim()
            // "## PATH 1: <title>" → "<title>"
            val afterMarker = headerTrimmed
                .removePrefix(PATH_MARKER)
                .trim()
                .substringAfter(":")
                .trim()
            val title = if (afterMarker.isBlank()) headerTrimmed else afterMarker

            var body = ""
            var rationale = ""
            var risk = RiskLevel.MEDIUM
            val bodyLines = mutableListOf<String>()

            for (line in block.drop(1)) {
                val t = line.trim()
                when {
                    t.startsWith(RISK_MARKER) -> {
                        risk = when (t.removePrefix(RISK_MARKER).trim().lowercase()) {
                            "low" -> RiskLevel.LOW
                            "high" -> RiskLevel.HIGH
                            else -> RiskLevel.MEDIUM
                        }
                    }
                    t.startsWith(RECOMMEND_MARKER) -> {
                        val digits = t.removePrefix(RECOMMEND_MARKER)
                            .filter { it.isDigit() }
                        val num = digits.toIntOrNull()
                        if (num != null && num in 1..pathLineIndexes.size) {
                            recommendedIndex = num
                        }
                    }
                    else -> bodyLines.add(line)
                }
            }

            body = bodyLines.joinToString("\n").trim()
            paths.add(
                CandidatePath(
                    index = idx + 1,
                    title = title,
                    body = body,
                    rationale = rationale.trim(),
                    riskLevel = risk,
                )
            )
        }

        if (paths.size < 2) return Result.SinglePath
        return Result.MultiPath(
            paths = paths,
            recommendedIndex = recommendedIndex.coerceIn(1, paths.size),
        )
    }

    /** Extract the recommended path's body for step parsing. */
    fun extractRecommendedPlanBody(result: Result, originalPlan: String): String? {
        return when (result) {
            is Result.SinglePath -> null
            is Result.MultiPath -> {
                val idx = result.recommendedIndex - 1
                if (idx in result.paths.indices) result.paths[idx].body else null
            }
        }
    }
}