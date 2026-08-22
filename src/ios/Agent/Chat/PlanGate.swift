import Foundation

/// Plan-confirmation gate for 深度龙虾Ai (Deep Agent Mode) — Layer B.
///
/// Unlike Layer A (persistent rules + proactive memory), the plan gate adds a
/// *hard* interaction: when deep mode is on and the agent's first reply to a
/// multi-step task is a plan-only turn (no tool calls, plan wrapped in the
/// fenced `plan` block the deep-mode fragment instructs it to emit), the UI
/// raises a confirm/edit bar instead of silently proceeding. The user then
/// either approves (which re-sends an "execute the plan" prompt through the
/// normal `send()` path) or edits/cancels.
///
/// The gate is deliberately fail-safe: if the model ignores the instruction
/// and starts acting immediately, `detectPlan` returns `nil`, the state stays
/// `.idle`, and nothing changes — a missed gate degrades to the pre-existing
/// behavior, never to a stuck or blocked thread.
enum PlanGate {

    enum State: Equatable {
        case idle
        case awaitingApproval(planText: String)
    }

    /// Fenced-block marker the deep-mode fragment tells the model to wrap its
    /// plan in. Detection matches the raw markdown before rendering.
    static let planMarker = "```plan"

    /// True when the assistant turn produced only text/thinking blocks and no
    /// tool-call blocks — i.e. it planned instead of acting.
    static func turnHasNoToolCalls(_ msg: ChatMessage) -> Bool {
        !msg.blocks.contains { block in
            switch block.kind {
            case .text, .thinking:
                return false
            default:
                return true
            }
        }
    }

    /// Combined text of all text blocks in a turn.
    static func visibleText(_ msg: ChatMessage) -> String {
        msg.blocks.compactMap { block -> String? in
            if case .text = block.kind { return block.content }
            return nil
        }.joined(separator: "\n")
    }

    /// Detect a plan-only turn. Returns the plan text when the turn has no
    /// tool calls AND its visible text contains the plan marker; nil otherwise.
    static func detectPlan(in msg: ChatMessage) -> String? {
        guard turnHasNoToolCalls(msg) else { return nil }
        let text = visibleText(msg)
        guard !text.isEmpty else { return nil }
        guard text.localizedCaseInsensitiveContains(planMarker) else { return nil }
        return text
    }
}