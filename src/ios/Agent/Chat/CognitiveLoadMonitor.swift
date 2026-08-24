import Foundation

// MARK: - CognitiveLoadMonitor (C9)
// [T-deep-mode-cognitive-p2-c9] Phase 6 P2: Cognitive load real-time monitoring.
//
// This component provides real-time cognitive load tracking for the deep agent
// mode. It combines two signal sources:
//
//   1. **Model-emitted sentinel**: The deep-mode fragment instructs the model
//      to periodically emit a `<<COGNITIVE_LOAD>>` sentinel with a level
//      (low / medium / high / critical) and optional notes. This is the
//      model's *self-assessed* load — how confident it is about the current
//      trajectory, whether it's losing track of the goal, etc.
//
//   2. **Client-computed metrics**: The client independently computes load
//      from observable signals — context token saturation, tool-call count,
//      verify failure rounds, workflow step count. These are *objective*
//      indicators the model may not notice (e.g., the context window is
//      85% full but the model doesn't track tokens).
//
// The two signals are merged: if EITHER source reports high/critical, the
// UI warning fires. This prevents the model from under-reporting load
// (a known failure mode — models tend to be overconfident about their own
// capacity).
//
// TOTAL-SWITCH SAFE: only invoked from runAgentLoop and the deep-mode UI
// rendering path, both of which are guarded by `deepModeEnabled`. When the
// master switch is off, no sentinels are parsed, no metrics are computed,
// and the @Published `cognitiveLoadLevel` stays at `.none` — zero UI residue.
// `deepModeDidDisableCleanup()` resets all state to `.none`.

/// Cognitive load level. `.none` means no load monitoring active (deep mode
/// off or no signal yet).
enum CognitiveLoadLevel: Int, Equatable, Comparable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    static func < (lhs: CognitiveLoadLevel, rhs: CognitiveLoadLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Human-readable label for UI display.
    var displayName: String {
        switch self {
        case .none:     return ""
        case .low:      return "低"
        case .medium:   return "中"
        case .high:     return "高"
        case .critical: return "严重"
        }
    }

    /// UI color hint (hex string for SwiftUI Color).
    var colorHint: String {
        switch self {
        case .none:     return "#8E8E93"
        case .low:      return "#34C759"  // green
        case .medium:   return "#FF9500"  // orange
        case .high:     return "#FF3B30"  // red
        case .critical: return "#FF2D55"  // deep red
        }
    }
}

/// Parsed result from a model-emitted cognitive load sentinel.
struct CognitiveLoadSignal: Equatable {
    let level: CognitiveLoadLevel
    let note: String?  // optional one-line note from the model
}

/// Aggregated cognitive load state combining model self-assessment and
/// client-computed metrics.
struct CognitiveLoadState: Equatable {
    /// The merged (max) level from all signal sources.
    let level: CognitiveLoadLevel
    /// The model's self-assessed level (from sentinel).
    let modelAssessed: CognitiveLoadLevel
    /// The client's computed level (from metrics).
    let clientComputed: CognitiveLoadLevel
    /// Optional note from the model's sentinel.
    let note: String?

    static let empty = CognitiveLoadState(
        level: .none,
        modelAssessed: .none,
        clientComputed: .none,
        note: nil
    )
}

enum CognitiveLoadMonitor {

    /// The sentinel the model wraps its self-assessed cognitive load in.
    static let marker = "<<COGNITIVE_LOAD>>"

    // MARK: - Sentinel Parsing

    /// Parse the cognitive load sentinel from the model's output text.
    /// Returns nil when no sentinel is found (degrade to client-only metrics).
    /// Matches the LAST occurrence so a quoted marker up-stream doesn't shadow.
    static func parseSentinel(_ text: String) -> CognitiveLoadSignal? {
        guard let range = text.range(of: marker, options: [.caseInsensitive, .backwards]) else {
            return nil
        }
        let token = text[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Expected format: "<<COGNITIVE_LOAD>> high" or
        // "<<COGNITIVE_LOAD>> medium: losing track of step 3"
        var level: CognitiveLoadLevel = .none
        var note: String?

        if token.hasPrefix("critical") {
            level = .critical
            note = extractNote(from: token, after: "critical")
        } else if token.hasPrefix("high") {
            level = .high
            note = extractNote(from: token, after: "high")
        } else if token.hasPrefix("medium") {
            level = .medium
            note = extractNote(from: token, after: "medium")
        } else if token.hasPrefix("low") {
            level = .low
            note = extractNote(from: token, after: "low")
        } else {
            return nil
        }

        return CognitiveLoadSignal(level: level, note: note)
    }

    /// Extract the note portion after the level keyword.
    private static func extractNote(from token: String, after keyword: String) -> String? {
        let rest = token.dropFirst(keyword.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":：- \t\n"))
        return rest.isEmpty ? nil : String(rest)
    }

    /// Remove the cognitive load sentinel line from text (for display).
    static func textWithoutSentinel(_ text: String) -> String? {
        guard parseSentinel(text) != nil else { return nil }
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

    // MARK: - Client-Computed Metrics

    /// Compute the client-side cognitive load from objective metrics.
    /// All inputs are optional — callers pass what they have.
    ///
    /// - Parameters:
    ///   - contextTokens: Current context window token usage.
    ///   - maxContextTokens: The model's max context window size.
    ///   - toolCallCount: Number of tool calls in the current agent loop.
    ///   - workflowStepCount: Number of steps in the current workflow.
    ///   - verifyFailures: Number of VerifyGate failures in the current workflow.
    ///   - goalRunnerRoundsUsed: Number of GoalRunner auto-continuation rounds used.
    static func computeClientLoad(
        contextTokens: Int,
        maxContextTokens: Int,
        toolCallCount: Int,
        workflowStepCount: Int,
        verifyFailures: Int,
        goalRunnerRoundsUsed: Int
    ) -> CognitiveLoadLevel {
        var level: CognitiveLoadLevel = .low

        // Context saturation: <50% = low, 50-70% = medium, 70-85% = high, >85% = critical
        if maxContextTokens > 0 {
            let ratio = Double(contextTokens) / Double(maxContextTokens)
            if ratio >= 0.85 {
                level = max(level, .critical)
            } else if ratio >= 0.70 {
                level = max(level, .high)
            } else if ratio >= 0.50 {
                level = max(level, .medium)
            }
        }

        // Tool call count: >20 = critical, >12 = high, >6 = medium
        if toolCallCount >= 20 {
            level = max(level, .critical)
        } else if toolCallCount >= 12 {
            level = max(level, .high)
        } else if toolCallCount >= 6 {
            level = max(level, .medium)
        }

        // Workflow complexity: >10 steps = high, >6 = medium
        if workflowStepCount >= 10 {
            level = max(level, .high)
        } else if workflowStepCount >= 6 {
            level = max(level, .medium)
        }

        // Verify failures: any failure = medium, 2 = high
        if verifyFailures >= 2 {
            level = max(level, .high)
        } else if verifyFailures >= 1 {
            level = max(level, .medium)
        }

        // GoalRunner exhaustion: used all 3 rounds = medium
        if goalRunnerRoundsUsed >= 3 {
            level = max(level, .medium)
        }

        return level
    }

    // MARK: - Merge

    /// Merge model-assessed and client-computed signals. Takes the MAX of
    /// both sources so the more conservative (higher) estimate wins.
    static func merge(modelAssessed: CognitiveLoadLevel?, clientComputed: CognitiveLoadLevel) -> CognitiveLoadState {
        let model = modelAssessed ?? .none
        let merged = max(model, clientComputed)
        return CognitiveLoadState(
            level: merged,
            modelAssessed: model,
            clientComputed: clientComputed,
            note: nil  // note is carried separately by the caller
        )
    }
}
