package com.openminis.app.agent

/**
 * DeepMode intensity level — controls how aggressively the agent pursues
 * autonomy and depth. Mirrors iOS `DeepModeLevel`.
 *
 * Three tiers:
 * - LITE       — Minimal overhead, only the 5 core behavior rules. Fastest,
 *                cheapest, closest to a normal assistant with slight rigor.
 * - STANDARD   — Default. Core rules + Plan-First + Self-Verify + scope-aware
 *                rules. Good balance of depth and speed.
 * - AGGRESSIVE — Maximum autonomy. Everything in STANDARD plus GoalRunner
 *                auto-continue, ClarifyGate ambiguity detection, MultiPath
 *                planning, error root-cause analysis, and post-task review.
 *                Slowest and most expensive but most thorough.
 */
enum class DeepModeLevel(val rawValue: String) {
    LITE("lite"),
    STANDARD("standard"),
    AGGRESSIVE("aggressive");

    val displayName: String
        get() = when (this) {
            LITE -> "轻量"
            STANDARD -> "标准"
            AGGRESSIVE -> "深度"
        }

    val description: String
        get() = when (this) {
            LITE -> "仅核心行为规则，响应最快"
            STANDARD -> "标准深度：计划+自验证+上下文规则"
            AGGRESSIVE -> "完全自主：自动续跑+多路径规划+复盘"
        }

    companion object {
        fun fromRaw(raw: String?): DeepModeLevel {
            return values().firstOrNull { it.rawValue.equals(raw, ignoreCase = true) }
                ?: STANDARD
        }
    }
}
