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
///   <<GOAL_STATE>> need_more_context: <reason>   → [C10] stop & ask user
///
/// Every layer is fail-safe: if the model never emits the sentinel (or writes
/// an unrecognized token), `parse` returns nil and nothing continues — control
/// degrades to the pre-existing "one turn, then stop" behavior. It can never
/// wedge a turn, because the cap bounds the number of auto-rounds and the
/// existing `ToolLoopDetector` / `maxAgentTurns` backstops bound per-round work.
///
/// [T-deep-mode-cognitive-p2-c10] Phase 6.5 P2: Dynamic autonomy exit.
/// The `needMoreContext` case gives the model an explicit escape hatch from
/// full autonomy: instead of flailing or hallucinating when it hits a gap it
/// can't fill, the model emits `need_more_context` and the client STOPS the
/// auto-continuation loop, surfaces the reason to the user, and waits for
/// input. This prevents the "3 rounds of auto-continue with increasingly
/// wrong assumptions" failure mode. Total-switch safe: only reachable when
/// deep mode is on (the sentinel is never injected otherwise).
struct GoalRunner {

    enum ParseResult: Equatable {
        case done
        case pending(reason: String?)
        /// [T-deep-mode-cognitive-p2-c10] The model needs user input before
        /// it can proceed. The client should STOP auto-continuation, surface
        /// the reason to the user, and wait for a new user message.
        case needMoreContext(reason: String?)
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
        // [T-deep-mode-cognitive-p2-c10] Dynamic autonomy exit: the model
        // recognizes it needs user input and proactively stops.
        if token.hasPrefix("need_more_context") || token.hasPrefix("need context") || token.hasPrefix("need more context") {
            let rest: String
            if token.hasPrefix("need_more_context") {
                rest = String(token.dropFirst("need_more_context".count))
            } else if token.hasPrefix("need more context") {
                rest = String(token.dropFirst("need more context".count))
            } else {
                rest = String(token.dropFirst("need context".count))
            }
            let reason = rest
                .trimmingCharacters(in: CharacterSet(charactersIn: ":：- \t\n"))
            return .needMoreContext(reason: reason.isEmpty ? nil : String(reason))
        }
        return nil
    }

    /// Return `text` with the trailing sentinel line removed, or nil when there
    /// is no recognizable sentinel (the caller leaves `text` untouched). Uses
    /// the same LAST-occurrence rule as `parse` so a quoted marker up-stream
    /// never strips the wrong line, and removes only the single line that owns
    /// the marker (plus its trailing newline) so surrounding content survives
    /// verbatim. Pair with `parse` at text-capture time so the auto-continue
    /// decision is taken BEFORE the technical line is stripped from the shown /
    /// persisted text.
    static func textWithoutSentinel(_ text: String) -> String? {
        guard parse(text) != nil else { return nil }
        guard let markerRange = text.range(of: marker, options: [.caseInsensitive, .backwards]) else {
            return nil
        }
        let prefix = text[..<markerRange.lowerBound]
        let lineStart = prefix.lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let suffix = text[markerRange.upperBound...]
        let lineEnd = suffix.firstIndex(of: "\n").map { text.index(after: $0) } ?? text.endIndex
        var cleaned = text
        cleaned.removeSubrange(lineStart..<lineEnd)
        return cleaned
    }
}