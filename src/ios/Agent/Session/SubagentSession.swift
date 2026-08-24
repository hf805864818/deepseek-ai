import Foundation

// MARK: - SubagentSession
// Phase 5: Subagent orchestration — an independent mini agent loop that runs
// with its own context window, limited tools, and bounded turns.
//
// [T-phase5] SubagentSession is the core of the `task_dispatch` tool. When the
// main agent calls `task_dispatch`, a SubagentSession is created with:
//   - A fresh conversation context (no shared history with the parent)
//   - A restricted tool set (no task_dispatch — no recursive subagents)
//   - A bounded number of turns (max_tool_calls)
//   - An optional allowed_tools whitelist
//
// The subagent runs its own mini agent loop using the same provider as the
// parent session. When done, it returns a result summary string that the
// parent incorporates into its analysis.
//
// TOTAL-SWITCH SAFE: SubagentSession is only instantiated inside the
// `task_dispatch` tool execution branch, which is only reachable when
// `deepModeEnabled` is true (the tool definition is only registered when
// deep mode is on). When the master switch is off, no SubagentSession
// is ever created, and `activeSubagents` stays empty.

/// Status of a subagent session.
enum SubagentStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

/// A subagent session — an independent mini agent loop.
@MainActor
final class SubagentSession: ObservableObject, Identifiable {
    let id = UUID()
    let taskDescription: String
    let prompt: String
    let maxToolCalls: Int
    let allowedTools: [String]?
    let createdAt: Date

    @Published var status: SubagentStatus = .pending
    @Published var resultSummary: String = ""
    @Published var toolCallCount: Int = 0
    @Published var lastActivity: String = ""

    /// The agent history for this subagent (independent of parent).
    private var agentHistory: [AgentMessage] = []
    /// Whether this session has finished (completed, failed, or cancelled).
    private(set) var isFinished: Bool = false

    init(taskDescription: String, prompt: String, maxToolCalls: Int = 10, allowedTools: [String]? = nil) {
        self.taskDescription = taskDescription
        self.prompt = prompt
        self.maxToolCalls = max(1, min(maxToolCalls, 30))
        self.allowedTools = allowedTools
        self.createdAt = Date()
    }

    // MARK: - Execution

    /// Run the subagent's mini agent loop.
    /// - Parameters:
    ///   - provider: The agent provider to use (resolved from parent session).
    ///   - systemPrompt: The system prompt for the subagent.
    ///   - makeTools: A closure that returns the full tool list; we filter it.
    ///   - executeToolCallback: A closure to execute a tool call, returning
    ///     (output, success).
    ///   - parentViewModel: The parent AIChatViewModel (for tool execution).
    /// - Returns: The result summary string.
    func run(
        provider: AgentProvider,
        systemPrompt: String,
        makeTools: () -> [AgentToolDefinition],
        executeTool: @escaping (AgentToolUse, Int, Int) async -> (String, Bool)
    ) async -> String {
        status = .running
        lastActivity = "Starting subagent..."

        // Build the restricted tool set.
        var tools = makeTools()
        // Always remove task_dispatch — no recursive subagents.
        tools.removeAll { $0.name == "task_dispatch" }
        // If allowedTools is specified, filter to only those tools.
        if let allowed = allowedTools, !allowed.isEmpty {
            let allowedSet = Set(allowed)
            tools = tools.filter { allowedSet.contains($0.name) }
        }

        // [T-phase5-5.3] Build a subagent-specific system prompt that
        // tells the model it's operating as a bounded subagent with a
        // limited tool budget. This encourages concise, focused execution
        // rather than open-ended exploration.
        let toolBudgetHint = "You are operating as a subagent with a BOUNDED tool budget of \(maxToolCalls) tool calls. Be efficient and focused — prioritize the most important actions first. When you have enough information, provide a clear summary of your findings instead of continuing to explore."
        let subagentSystemPrompt = systemPrompt + "\n\n" + toolBudgetHint

        // Build the initial user message with the prompt.
        let userMsg = AgentMessage(role: .user, parts: [.text(prompt)])
        agentHistory.append(userMsg)

        var loopCount = 0
        let maxIterations = maxToolCalls + 2  // Allow a couple extra turns for the final response

        while loopCount < maxIterations && toolCallCount < maxToolCalls {
            // [T-phase5-5.3] Cancellation check: if cancel() was called
            // (e.g. master switch turned off mid-run), bail out immediately.
            if isFinished {
                return resultSummary
            }

            loopCount += 1
            lastActivity = "Iteration \(loopCount), tool calls: \(toolCallCount)/\(maxToolCalls)"

            do {
                let stream = try await provider.streamAgentMessage(
                    messages: agentHistory,
                    systemPrompt: subagentSystemPrompt,
                    tools: tools,
                    maxTokens: provider.defaultMaxTokens
                )

                var textContent = ""
                var toolCalls: [(id: String, name: String, args: [String: Any])] = []
                var reasoningContent: String?
                var reasoningEcho: ReasoningEcho?

                for try await event in stream {
                    switch event {
                    case .textDelta(let delta):
                        textContent += delta
                    case .toolCallComplete(let id, let name, let args, _):
                        toolCalls.append((id: id, name: name, args: args))
                    case .reasoningContent(let content):
                        reasoningContent = (reasoningContent ?? "") + content
                    case .reasoningEcho(let echo):
                        reasoningEcho = echo
                    case .done(let stopReason):
                        break
                    default:
                        break
                    }
                }

                // Build assistant message from the response.
                var parts: [AgentContentPart] = []
                if !textContent.isEmpty {
                    parts.append(.text(textContent))
                }
                for tc in toolCalls {
                    parts.append(.toolUse(id: tc.id, name: tc.name, input: tc.args))
                }

                let assistantMsg = AgentMessage(
                    role: .assistant,
                    parts: parts,
                    reasoningContent: reasoningContent,
                    reasoningEcho: reasoningEcho
                )
                agentHistory.append(assistantMsg)

                // If no tool calls, the subagent is done — return the text.
                if toolCalls.isEmpty {
                    resultSummary = textContent.isEmpty ? "Subagent completed with no output." : textContent
                    status = .completed
                    isFinished = true
                    return resultSummary
                }

                // Execute tool calls and build the tool result message.
                // [T-phase5-5.3] Enforce the tool call limit during parallel
                // execution: if the model emitted more parallel calls than
                // the remaining budget allows, execute only what fits and
                // inject a limit-reminder for the rest.
                var toolResultParts: [AgentContentPart] = []
                for tc in toolCalls {
                    // Stop executing if we've hit the budget.
                    if toolCallCount >= maxToolCalls {
                        toolResultParts.append(.toolResult(
                            id: tc.id,
                            name: tc.name,
                            content: "Skipped: tool call budget exhausted (\(maxToolCalls)/\(maxToolCalls)).",
                            isError: true
                        ))
                        continue
                    }

                    toolCallCount += 1
                    lastActivity = "Executing: \(tc.name) (\(toolCallCount)/\(maxToolCalls))"

                    let toolUse = AgentToolUse(id: tc.id, name: tc.name, args: tc.args)
                    let (output, success) = await executeTool(toolUse, loopCount, toolCallCount)

                    toolResultParts.append(.toolResult(
                        id: tc.id,
                        name: tc.name,
                        content: output,
                        isError: !success
                    ))
                }

                let toolResultMsg = AgentMessage(role: .user, parts: toolResultParts)
                agentHistory.append(toolResultMsg)

            } catch is CancellationError {
                status = .cancelled
                isFinished = true
                resultSummary = "Subagent was cancelled."
                return resultSummary
            } catch {
                status = .failed
                isFinished = true
                resultSummary = "Subagent failed: \(error.localizedDescription)"
                return resultSummary
            }
        }

        // If we hit the tool call limit, do one final turn to get a summary.
        if toolCallCount >= maxToolCalls && !isFinished {
            lastActivity = "Max tool calls reached, getting summary..."

            do {
                let limitReminder = AgentMessage(role: .user, parts: [.text("You have reached the maximum number of tool calls. Please provide a final summary of your findings.")])
                agentHistory.append(limitReminder)

                let stream = try await provider.streamAgentMessage(
                    messages: agentHistory,
                    systemPrompt: subagentSystemPrompt,
                    tools: [],  // No tools — force a text response
                    maxTokens: provider.defaultMaxTokens
                )

                var textContent = ""
                for try await event in stream {
                    if case .textDelta(let delta) = event {
                        textContent += delta
                    }
                }

                resultSummary = textContent.isEmpty ? "Subagent reached tool call limit with no summary." : textContent
                status = .completed
                isFinished = true
                return resultSummary
            } catch {
                status = .failed
                isFinished = true
                resultSummary = "Subagent failed during final summary: \(error.localizedDescription)"
                return resultSummary
            }
        }

        // Fallback (shouldn't reach here normally).
        resultSummary = "Subagent ended unexpectedly."
        status = .completed
        isFinished = true
        return resultSummary
    }

    /// Cancel the subagent session.
    func cancel() {
        status = .cancelled
        isFinished = true
        resultSummary = "Subagent was cancelled."
    }
}

// MARK: - AgentToolUse (helper struct for tool execution)
// A lightweight wrapper to pass tool call info to the execute closure.
struct AgentToolUse {
    let id: String
    let name: String
    let args: [String: Any]
}
