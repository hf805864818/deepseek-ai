package com.openminis.app.agent

// MARK: - SequentialThinkingTool (C11)
// [T-deep-mode-cognitive-p2-c11] Phase 7.5 P2: On-demand sequential thinking.
//
// The model calls this tool when it feels the need to structure its reasoning
// mid-task. Returns a structured reasoning framework (hypothesis → verification
// → conclusion → convergence for each step).
//
// TOTAL-SWITCH SAFE: tool registration gated on deepModeEnabled; produces
// no persistent state — output is a text template returned as a tool result.

data class ThinkingStep(
    val index: Int,
    var hypothesis: String = "",
    var verification: String = "",
    var conclusion: String = "",
    var convergence: Convergence = Convergence.UNKNOWN,
) {
    enum class Convergence(val displayName: String) {
        CONVERGING("收敛中"),
        DIVERGING("发散中"),
        STABLE("稳定"),
        UNKNOWN("待评"),
    }
}

data class SequentialThinkingResult(
    val problem: String,
    val steps: List<ThinkingStep>,
    val framework: String,
    val contextPhase: String,
    val contextStep: Int,
)

object SequentialThinkingTool {

    const val TOOL_NAME = "sequential_thinking"

    const val MIN_STEPS = 2
    const val DEFAULT_STEPS = 5
    const val MAX_STEPS = 15

    /**
     * Generate a structured reasoning framework for the given problem.
     */
    fun generateFramework(
        problem: String,
        maxSteps: Int,
        workflowPhase: String = "idle",
        workflowStep: Int = 0,
        cognitiveLoadLevel: CognitiveLoadLevel = CognitiveLoadLevel.NONE,
        isMultiPath: Boolean = false,
    ): SequentialThinkingResult {
        // Adaptive step count: reduce when cognitive load is high
        var actualSteps = maxOf(MIN_STEPS, minOf(maxSteps, MAX_STEPS))
        if (cognitiveLoadLevel >= CognitiveLoadLevel.HIGH) {
            actualSteps = minOf(actualSteps, 3)
        } else if (cognitiveLoadLevel == CognitiveLoadLevel.MEDIUM) {
            actualSteps = minOf(actualSteps, 5)
        }

        val steps = (1..actualSteps).map { ThinkingStep(index = it) }

        val framework = buildString {
            append("## 结构化推理框架\n\n")
            append("**问题**: $problem\n\n")

            // Context injection
            if (workflowPhase != "idle") {
                append("**当前上下文**: 工作流阶段=$workflowPhase")
                if (workflowStep > 0) {
                    append(", 步骤=$workflowStep")
                }
                append("\n\n")
            }

            // Cognitive load context
            if (cognitiveLoadLevel >= CognitiveLoadLevel.MEDIUM) {
                append("**认知负荷提示**: 当前负荷=${cognitiveLoadLevel.displayName}。")
                if (cognitiveLoadLevel >= CognitiveLoadLevel.HIGH) {
                    append("建议聚焦核心问题，避免发散。本框架已限制为${actualSteps}步。\n\n")
                } else {
                    append("保持推理聚焦。\n\n")
                }
            }

            // Multi-path context (C12 integration)
            if (isMultiPath) {
                append("**多路径提示**: 当前工作流有多条候选路径。在推理时考虑各路径的优劣，确认当前路径是否仍然最优。\n\n")
            }

            // Step templates
            for (step in steps) {
                append("### 步骤 ${step.index}\n")
                append("- **假设**: [陈述本步假设——你认为什么是对的？]\n")
                append("- **验证**: [检验这个假设——有什么证据支持或反对？]\n")
                append("- **结论**: [本步得出什么结论？是否需要修正方向？]\n")
                append("- **收敛状态**: [收敛中/发散中/稳定] — 推理是在接近答案还是远离？\n\n")
            }

            // Final synthesis
            append("### 最终综合\n")
            append("[综合所有步骤的结论，给出最终判断。如果结论与初始假设不同，说明为什么。]\n")

            // Self-check
            append("\n---\n")
            append("**自检**: 如果有超过一半的步骤标记为「发散中」，请考虑：是否问题本身需要重新定义？是否需要更多上下文信息（可用 <<GOAL_STATE>> need_more_context: <说明> 退出自主模式请求用户输入）？")
        }

        return SequentialThinkingResult(
            problem = problem,
            steps = steps,
            framework = framework,
            contextPhase = workflowPhase,
            contextStep = workflowStep,
        )
    }

    /**
     * Validate input parameters. Returns null if valid, or an error message.
     */
    fun validateInput(problem: String, maxSteps: Int): String? {
        if (problem.isBlank()) {
            return "Error: 'problem' parameter is required. Please describe the problem you want to reason through."
        }
        if (problem.length > 5000) {
            return "Error: 'problem' is too long (max 5000 chars). Please be more concise."
        }
        if (maxSteps < 1 || maxSteps > 20) {
            return "Error: 'max_steps' must be between 1 and 20."
        }
        return null
    }
}
