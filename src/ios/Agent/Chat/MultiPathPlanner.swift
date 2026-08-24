import Foundation

// MARK: - MultiPathPlanner (C12)
// [T-deep-mode-cognitive-p2-c12] Phase 4.5 P2: Multi-path parallel thinking.
//
// When deep mode is on and the model is in the planning phase, the
// deepModeFragment instructs it to generate multiple candidate paths
// (default 3) inside a fenced ```plan``` block, each marked with a
// `## PATH N:` header. The client then picks the best path based on
// a scoring rubric the model itself provides.
//
// TOTAL-SWITCH SAFE: MultiPathPlanner is only invoked from PlanGate
// detection logic, which is itself gated on `deepModeEnabled`. When
// the master switch is off, deepModeFragment is never injected, the
// model never produces multi-path plans, and MultiPathPlanner is
// never called. Zero runtime state, zero persistence, zero UI.

/// A single candidate path in a multi-path plan.
struct CandidatePath: Identifiable, Equatable {
    let id = UUID()
    let index: Int          // 1-based path number
    let title: String       // Short title after "## PATH N:"
    let body: String        // Full plan text for this path
    let rationale: String   // Why this path, from the model's scoring
    let riskLevel: RiskLevel

    enum RiskLevel: String, Equatable {
        case low
        case medium
        case high
    }
}

/// Result of multi-path plan parsing.
enum MultiPathResult: Equatable {
    /// The plan contains multiple candidate paths.
    case multiPath(paths: [CandidatePath], recommendedIndex: Int)
    /// The plan is a standard single-path plan — not multi-path format.
    case singlePath
}

enum MultiPathPlanner {

    /// Header marker for each candidate path in a multi-path plan.
    /// The model is instructed to format each path as:
    /// ```
    /// ## PATH 1: <title>
    /// <steps>
    /// RISK: low|medium|high
    /// ```
    static let pathMarker = "## PATH"
    static let riskMarker = "RISK:"
    static let recommendMarker = "RECOMMENDED:"

    /// Parse a plan text to determine if it's a multi-path plan.
    /// Returns `.singlePath` if the plan doesn't contain multiple
    /// `## PATH` headers (backward compatible with existing PlanGate).
    static func parse(_ planText: String) -> MultiPathResult {
        // Count occurrences of the path marker.
        let lines = planText.components(separatedBy: "\n")
        let pathLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix(pathMarker) }

        guard pathLines.count >= 2 else {
            // Fewer than 2 paths → not a multi-path plan.
            return .singlePath
        }

        // Parse each path block.
        var paths: [CandidatePath] = []
        var recommendedIndex = 1

        var currentPathIndex = 0
        var currentTitle = ""
        var currentBody: [String] = []
        var currentRisk: CandidatePath.RiskLevel = .medium
        var currentRationale = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix(pathMarker) {
                // Save previous path if exists.
                if currentPathIndex > 0 {
                    paths.append(CandidatePath(
                        index: currentPathIndex,
                        title: currentTitle,
                        body: currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                        rationale: currentRationale.trimmingCharacters(in: .whitespacesAndNewlines),
                        riskLevel: currentRisk
                    ))
                }

                // Start new path.
                currentPathIndex += 1
                // Extract title: "## PATH 1: <title>" → "<title>"
                let afterMarker = String(trimmed.dropFirst(pathMarker.count))
                    .trimmingCharacters(in: .whitespaces)
                // Remove leading number and colon: "1: " or "1 - "
                if let colonRange = afterMarker.range(of: ":") {
                    currentTitle = String(afterMarker[afterMarker.index(after: colonRange.lowerBound)...])
                        .trimmingCharacters(in: .whitespaces)
                } else if let dashRange = afterMarker.range(of: "-") {
                    currentTitle = String(afterMarker[afterMarker.index(after: dashRange.lowerBound)...])
                        .trimmingCharacters(in: .whitespaces)
                } else {
                    currentTitle = afterMarker
                }
                currentBody = []
                currentRisk = .medium
                currentRationale = ""
            } else if trimmed.hasPrefix(riskMarker) {
                let riskStr = String(trimmed.dropFirst(riskMarker.count))
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                currentRisk = CandidatePath.RiskLevel(rawValue: riskStr) ?? .medium
            } else if trimmed.hasPrefix(recommendMarker) {
                // "RECOMMENDED: PATH 2" or "RECOMMENDED: 2"
                let afterMarker = String(trimmed.dropFirst(recommendMarker.count))
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                // Try to extract a number.
                let digits = afterMarker.compactMap { $0.isNumber ? $0 : nil }
                let numStr = String(digits)
                if let num = Int(numStr), num >= 1 && num <= pathLines.count {
                    recommendedIndex = num
                }
            } else {
                // Regular line — add to current path body.
                if currentPathIndex > 0 {
                    currentBody.append(line)
                }
            }
        }

        // Save last path.
        if currentPathIndex > 0 {
            paths.append(CandidatePath(
                index: currentPathIndex,
                title: currentTitle,
                body: currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                rationale: currentRationale.trimmingCharacters(in: .whitespacesAndNewlines),
                riskLevel: currentRisk
            ))
        }

        guard paths.count >= 2 else {
            return .singlePath
        }

        return .multiPath(paths: paths, recommendedIndex: min(max(recommendedIndex, 1), paths.count))
    }

    /// Extract the recommended path's step list as a standard plan text,
    /// so it can be fed to WorkflowPlanParser.parseSteps() unchanged.
    static func extractRecommendedPlan(from result: MultiPathResult) -> String? {
        switch result {
        case .singlePath:
            return nil
        case .multiPath(let paths, let recommendedIndex):
            guard paths.indices.contains(recommendedIndex - 1) else { return nil }
            return paths[recommendedIndex - 1].body
        }
    }
}
