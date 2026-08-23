import Foundation

/// Goal auto-continuation for 深度龙虾Ai (Deep Agent Mode) — Layer C.
///
/// Layer A persisted the rules and made memory proactive; Layer B added a
/// plan-confirmation gate. This layer adds TRAE's "keep going till the goal is
/// done" autonomy: the deep-mode fragment tells the model to end each multi-step
/// turn with a tiny sentinel line, and the client reads that sentinel at the
/// turn's end to decide whether to auto-continue (up to a hard cap) or stop.
///
/// The sentinel contract:
///   <<GOAL_STATE>> done                          → task fully complete
///   <<GOAL_STATE>> pending: <next step>          → incomplete; auto-continue
///
/// Every layer is fail-safe: if the model never emits the sentinel (or writes
/// an unrecognized token), `parse` returns nil and nothing continues — control
/// degrades to the pre-existing "one turn, then stop" behavior. It can never
/// wedge a turn, because the cap bounds the number of auto-rounds and the
/// existing `ToolLoopDetector` / `maxAgentTurns` backstops bound per-round work.
struct GoalRunner {

    enum ParseResult: Equatable {
        case done
        case pending(reason: String?)
    }

    /// The sentinel line the deep-mode fragment instructs the model to emit.
    static let marker = "<<GOAL_STATE>>"

    /// Hard cap on how many auto-continuation rounds a single user prompt may
    /// trigger. Combined with `maxAgentTurns` (per-round tool ceiling) this
    /// guarantees a bounded amount of autonomous work.
    static let maxAutoRounds = 3

    /// Parse the trailing sentinel from a completed turn's visible text.
    /// Returns nil when there is no recognized sentinel (no-op). Matches the
    /// LAST occurrence so a plan/citation that quotes the marker up-stream
    /// doesn't shadow the final status.
    static func parse(_ text: String) -> ParseResult? {
        guard let range = text.range(of: marker, options: [.caseInsensitive, .backwards]) else {
            return nil
        }
        let token = text[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if token.hasPrefix("done") { return .done }
        if token.hasPrefix("pending") {
            let rest = token.dropFirst("pending".count)
            let reason = rest
                .trimmingCharacters(in: CharacterSet(charactersIn: ":：- \t\n"))
            return .pending(reason: reason.isEmpty ? nil : String(reason))
        }
        return nil
    }
}