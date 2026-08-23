import Foundation

/// Client-driven workflow state machine for 深度龙虾Ai — Phase 1.
///
/// This is the "强制式" (deterministic) upgrade over Layer B's purely-reactive
/// plan gate. Instead of only *detecting* whether the model happened to emit a
/// fenced ```plan``` block, the client now owns an explicit phase and advances
/// it at well-defined events (plan raised → executing → …). The model remains
/// the executor inside each phase; the *transitions* are client state, not
/// model whim.
///
/// Contract (总开关 / 回退): every consumer MUST be gated on `deepModeEnabled`.
/// All of these types are in-memory only and are NEVER persisted, so turning
/// the global toggle off leaves zero residue in behavior, state, or UI.
enum WorkflowPhase: Equatable {
    /// No workflow in progress (trivial task, or deep mode off).
    case idle
    /// Complex task: model should produce a plan only, no tool calls.
    case planning
    /// Plan confirmed / executing tools.
    case executing
    /// Post-execution self-verification (Phase 2). Entered when the model
    /// reports `done` on an execution turn; the client then injects a
    /// mandatory self-check prompt. The model must verify results and emit
    /// a `<<VERIFY_STATE>> passed / failed` sentinel. On `passed` the
    /// workflow finishes; on `failed` it re-enters `.executing` for a fix.
    /// All steps stay `.done` visually during this phase (the user sees
    /// "复查中" on an all-green list).
    case verifying
}

enum WorkflowStepStatus: Equatable {
    case pending
    case active
    case done
}

struct WorkflowStep: Identifiable, Equatable {
    /// 1-based index matching the plan's numbered list order.
    let id: Int
    let title: String
    var status: WorkflowStepStatus

    init(id: Int, title: String, status: WorkflowStepStatus = .pending) {
        self.id = id
        self.title = title
        self.status = status
    }
}

/// Parses plan text into an ordered list of numbered steps.
/// Pure function: no side effects, safe to call on any thread.
enum WorkflowPlanParser {

    /// Extract step titles from plan text. Accepts both a fenced ```plan```
    /// block and a bare numbered/bulleted list. Deduplicates on the title and
    /// collapses empty lines so prose around the list does not produce junk.
    static func parseSteps(from planText: String) -> [WorkflowStep] {
        var text = planText

        // If the plan is wrapped in a ```plan ... ``` fence, take the inner
        // body. Search is case-insensitive on the ORIGINAL string so the range
        // indices remain valid for it (a lowercased copy's indices must never
        // subscript the original — that is undefined for non-ASCII content).
        if let start = text.range(of: "```plan", options: .caseInsensitive) {
            let afterFence = text[start.upperBound...]
            if let end = afterFence.range(of: "```") {
                text = String(afterFence[..<end.lowerBound])
            } else {
                text = String(afterFence)
            }
        }

        var steps: [WorkflowStep] = []
        var seen = Set<String>()

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let title = stepTitle(fromLine: line) else { continue }

            let key = title.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            steps.append(WorkflowStep(id: steps.count + 1, title: title))
        }
        return steps
    }

    /// Returns the cleaned title for a line that reads like a list item, else nil.
    private static func stepTitle(fromLine line: String) -> String? {
        var rest = line

        // Numbered list: "1.", "12)", "3、", with optional spaces.
        if let m = rest.range(of: #"^\s*\d{1,3}\s*[.)、]\s*"#, options: .regularExpression) {
            rest = String(rest[m.upperBound...])
        } else if let m = rest.range(of: #"^\s*[-*•·]\s*"#, options: .regularExpression) {
            rest = String(rest[m.upperBound...])
        } else {
            // Not a recognized list marker.
            return nil
        }

        let title = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        // Cap length so an accidentally matched prose line can't bloat the UI.
        return String(title.prefix(120))
    }
}

extension Notification.Name {
    /// [T-deep-mode-workflow] Posted when the 深度龙虾Ai master switch changes.
    /// The VM observes this to hard-reset all Phase 1 workflow UI/state the
    /// instant deep mode is disabled, so turning the toggle off leaves zero
    /// residual banner, phase, or step list.
    static let deepModeDidChange = Notification.Name("deepModeDidChange")
}