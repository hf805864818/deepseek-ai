import Foundation

/// Self-verification / reflection loop for 深度龙虾Ai — Phase 2.
///
/// Phase 1 could "keep going" (GoalRunner) but never "looked back". This gate
/// adds TRAE-style Verify: after the model reports `done` on an execution turn,
/// the client forces a self-check phase — run / preview / compare results — and
/// only considers the workflow truly complete when verification passes. If it
/// fails, control returns to `.executing` so the model can fix the issues.
///
/// Sentinel contract (appended by the model at the END of a verify turn):
///   <<VERIFY_STATE>> passed                          → verification OK → finish
///   <<VERIFY_STATE>> failed: <reason + fix plan>     → issues found → re-execute
///
/// Fail-safe by design:
///   • No sentinel / unrecognized token → treat as passed (degrade to Phase 1
///     behavior; the user still sees the completed workflow, no blockage).
///   • Verify round budget (default 2) + ToolLoopDetector backstop → can't
///     loop forever.
///   • Everything is gated on `deepModeEnabled`; memory-only state, never
///     persisted — toggle off leaves zero residue.
enum VerifyGate {

    enum ParseResult: Equatable {
        case passed
        case failed(reason: String?)
    }

    /// The sentinel line the deep-mode fragment instructs the model to emit
    /// at the end of a verification turn.
    static let marker = "<<VERIFY_STATE>>"

    /// Hard cap on verification rounds per workflow. Two is enough for the
    /// common "oops, I missed a thing → fix it → re-verify" pattern; anything
    /// more suggests the plan itself is wrong and the user should intervene.
    static let maxVerifyRounds = 2

    /// Parse the trailing verification sentinel from a completed turn's visible
    /// text. Returns nil when there is no recognized sentinel (degrade to
    /// Phase 1 finish). Matches the LAST occurrence so a plan/citation that
    /// quotes the marker up-stream doesn't shadow the final status.
    static func parse(_ text: String) -> ParseResult? {
        guard let range = text.range(of: marker, options: [.caseInsensitive, .backwards]) else {
            return nil
        }
        let token = text[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if token.hasPrefix("passed") || token.hasPrefix("pass") || token.hasPrefix("ok") {
            return .passed
        }
        if token.hasPrefix("failed") || token.hasPrefix("fail") {
            let rest = token.dropFirst("failed".count)
            let reason = rest
                .trimmingCharacters(in: CharacterSet(charactersIn: ":：- \t\n"))
            return .failed(reason: reason.isEmpty ? nil : String(reason))
        }
        return nil
    }

    /// Return `text` with the trailing sentinel line removed, or nil when there
    /// is no recognizable sentinel. Mirrors GoalRunner.textWithoutSentinel.
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
