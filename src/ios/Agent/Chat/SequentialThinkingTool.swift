import Foundation

// MARK: - SequentialThinkingTool (C11)
// [T-deep-mode-cognitive-p2-c11] Phase 7.5 P2: On-demand sequential thinking.
//
// This is the "柔性版 planning" — unlike PlanGate's forced planning phase
// (which always runs before execution), this tool is called BY THE MODEL
// when it feels the need to structure its reasoning mid-task. The model
// might be in the middle of executing, hit a complex sub-problem, and
// call this tool to think it through step by step.
//
// What the tool does:
//   1. The model calls it with a problem description and max_steps.
//   2. The tool returns a structured reasoning framework (hypothesis →
//      verification → conclusion for each step).
//   3. The model fills in each step in its response, following the framework.
//   4. The tool's output is a template — the actual reasoning is done by
//      the model, but the tool structures the output format so the
//      reasoning is visible and auditable.
//
// Enhanced beyond the original stub (which just returned a blank template):
//   - Context-aware: injects the current workflow phase and step number
//     so the model can connect its thinking to where it is in the task.
//   - Adaptive step count: suggests fewer steps for simpler problems,
//     more for complex ones.
//   - Convergence tracking: each step asks the model to assess whether
//     it's converging or diverging, preventing endless exploration.
//   - Deep-mode integration: connects to C9 (cognitive load) and C12
//     (multi-path) — if the model is in a multi-path workflow, the
//     thinking tool suggests evaluating all paths.
//
// TOTAL-SWITCH SAFE:
//   - Tool registration is gated on `deepModeEnabled` (moved from
//     always-on to deep-mode-exclusive).
//   - Handler has a `guard deepModeEnabled` check (defensive — if the
//     toggle was turned off between registration and execution).
//   - The tool produces no persistent state — its output is a text
//     template that goes into the conversation as a tool result.
//   - `deepModeDidDisableCleanup()` needs no action for this tool
//     (no state to clear).

/// Reasoning step template for the sequential thinking tool.
struct ThinkingStep: Identifiable {
    let id = UUID()
    let index: Int
    var hypothesis: String = ""
    var verification: String = ""
    var conclusion: String = ""
    var convergence: Convergence = .unknown

    enum Convergence: String {
        case converging = "收敛中"
        case diverging = "发散中"
        case stable = "稳定"
        case unknown = "待评"
    }
}

/// Result of a sequential thinking tool call.
struct SequentialThinkingResult {
    let problem: String
    let steps: [ThinkingStep]
    let framework: String  // The text template returned to the model
    let contextPhase: String  // Current workflow phase for context
    let contextStep: Int  // Current workflow step number (0 = not in workflow)
}

enum SequentialThinkingTool {

    /// The tool name as registered in the tool definitions.
    static let toolName = "sequential_thinking"

    /// Minimum and maximum reasoning steps.
    static let minSteps = 2
    static let defaultSteps = 5
    static let maxSteps = 15

    // MARK: - Framework Generation

    /// Generate a structured reasoning framework for the given problem.
    ///
    /// The framework is a text template that the model fills in. It includes:
    /// - The problem statement
    /// - Current context (workflow phase + step, if in a workflow)
    /// - N reasoning steps, each with hypothesis/verification/conclusion/convergence
    /// - A final synthesis section
    /// - C9 cognitive load check (if load is high, suggest fewer steps)
    /// - C12 multi-path check (if in a multi-path workflow, suggest evaluating paths)
    static func generateFramework(
        problem: String,
        maxSteps: Int,
        workflowPhase: String,
        workflowStep: Int,
        cognitiveLoadLevel: CognitiveLoadLevel,
        isMultiPath: Bool
    ) -> SequentialThinkingResult {
        // Adaptive step count: if cognitive load is high, cap at fewer steps
        // to prevent the thinking session from becoming another source of overload.
        var actualSteps = max(minSteps, min(maxSteps, maxSteps))
        if cognitiveLoadLevel >= .high {
            actualSteps = min(actualSteps, 3)
        } else if cognitiveLoadLevel == .medium {
            actualSteps = min(actualSteps, 5)
        }

        var steps: [ThinkingStep] = []
        for i in 1...actualSteps {
            steps.append(ThinkingStep(index: i))
        }

        // Build the framework text
        var framework = "## 结构化推理框架\n\n"
        framework += "**问题**: \(problem)\n\n"

        // Context injection — helps the model connect its thinking to the task
        if workflowPhase != "idle" {
            framework += "**当前上下文**: 工作流阶段=\(workflowPhase)"
            if workflowStep > 0 {
                framework += ", 步骤=\(workflowStep)"
            }
            framework += "\n\n"
        }

        // Cognitive load context
        if cognitiveLoadLevel >= .medium {
            framework += "**认知负荷提示**: 当前负荷=\(cognitiveLoadLevel.displayName)。"
            if cognitiveLoadLevel >= .high {
                framework += "建议聚焦核心问题，避免发散。本框架已限制为\(actualSteps)步。\n\n"
            } else {
                framework += "保持推理聚焦。\n\n"
            }
        }

        // Multi-path context (C12 integration)
        if isMultiPath {
            framework += "**多路径提示**: 当前工作流有多条候选路径。在推理时考虑各路径的优劣，确认当前路径是否仍然最优。\n\n"
        }

        // Step templates
        for step in steps {
            framework += "### 步骤 \(step.index)\n"
            framework += "- **假设**: [陈述本步假设——你认为什么是对的？]\n"
            framework += "- **验证**: [检验这个假设——有什么证据支持或反对？]\n"
            framework += "- **结论**: [本步得出什么结论？是否需要修正方向？]\n"
            framework += "- **收敛状态**: [收敛中/发散中/稳定] — 推理是在接近答案还是远离？\n\n"
        }

        // Final synthesis
        framework += "### 最终综合\n"
        framework += "[综合所有步骤的结论，给出最终判断。如果结论与初始假设不同，说明为什么。]\n"

        // Check for divergence
        framework += "\n---\n"
        framework += "**自检**: 如果有超过一半的步骤标记为「发散中」，请考虑：是否问题本身需要重新定义？是否需要更多上下文信息（可用 <<GOAL_STATE>> need_more_context: <说明> 退出自主模式请求用户输入）？"

        return SequentialThinkingResult(
            problem: problem,
            steps: steps,
            framework: framework,
            contextPhase: workflowPhase,
            contextStep: workflowStep
        )
    }

    // MARK: - Validation

    /// Validate the input parameters for the sequential thinking tool.
    /// Returns nil if valid, or an error message string if invalid.
    static func validateInput(problem: String, maxSteps: Int) -> String? {
        if problem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Error: 'problem' parameter is required. Please describe the problem you want to reason through."
        }
        if problem.count > 5000 {
            return "Error: 'problem' is too long (max 5000 chars). Please be more concise."
        }
        if maxSteps < 1 || maxSteps > 20 {
            return "Error: 'max_steps' must be between 1 and 20."
        }
        return nil
    }

    // MARK: - Tool Definition

    /// The AgentToolDefinition for this tool. Used when registering
    /// (only when deepModeEnabled is on).
    static func toolDefinition() -> AgentToolDefinition {
        return AgentToolDefinition(
            name: toolName,
            description: "Break down a complex problem into structured reasoning steps. Use this when you need to think through a problem methodically before or during execution. Each step follows: hypothesis → verification → conclusion → convergence assessment. The tool returns a framework template you fill in. Do NOT use for simple tasks — only when the problem genuinely requires multi-step deduction. Only available in deep mode.",
            parameters: [
                "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user (e.g. 'Analyze authentication flow', 'Plan database migration strategy'). Use the same language as the user."),
                "problem": AgentToolParam(type: .string, description: "The problem or question that needs structured reasoning. Be specific — include context, constraints, and what you're trying to determine."),
                "max_steps": AgentToolParam(type: .integer, description: "Maximum reasoning steps (default: 5, range: 2-15). Each step is one hypothesis-check-conclusion cycle. Use more for complex architecture decisions, fewer for straightforward questions. The tool may reduce this if cognitive load is high."),
            ],
            required: ["tool_title", "problem"],
            propertyOrdering: ["tool_title", "problem", "max_steps"]
        )
    }
}
