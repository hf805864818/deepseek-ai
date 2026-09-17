import Foundation

/// Spec-generation gate for 深度龙虾Ai — Phase F (Spec mode).
///
/// An OPTIONAL layer on top of the plan → execute → verify workflow. When the
/// user has both the master switch (`deepMode.enabled`) and the Spec-mode
/// toggle (`deepMode.specMode`) on, verification passing does not immediately
/// finish the workflow: the client instead enters `.specWriting`, injects a
/// spec-generation prompt, and the model writes three documents via
/// `file_write`:
///   • spec.md      — 目标 / 范围 / 功能清单 / 验收标准
///   • checklist.md — 检查清单
///   • tasks.md     — 任务拆分（标可并行）
/// then appends the `<<SPEC_STATE>>` sentinel. The client parses the sentinel,
/// collects the produced file paths, enters `.specReviewing`, and pauses for
/// the user's review (approve / edit / reject).
///
/// Safety guarantees (mirror PlanGate / VerifyGate):
///   • Everything is gated on `deepModeEnabled && specModeEnabled`. When either
///     is off, SpecGate never engages and the existing 4-state workflow is
///     byte-for-byte unchanged (zero drift).
///   • Purely in-memory / prompt-only: no state persisted. Toggling off the
///     master switch or Spec mode leaves zero residue.
///   • Edit rounds are capped (default 2) so reject→regenerate can't loop.
enum SpecGate {

    enum State: Equatable {
        case idle
        /// Spec documents written and awaiting user review.
        case awaitingReview(files: [SpecFile])
        case approved
    }

    static let marker = "<<SPEC_STATE>>"

    /// Cap on reject→regenerate edit rounds per workflow.
    static let maxEditRounds = 2

    /// A produced spec artifact (role → filename/path).
    struct SpecFile: Equatable, Identifiable {
        enum Role: String {
            case spec = "spec"
            case checklist = "checklist"
            case tasks = "tasks"
        }
        let role: Role
        /// Display name: spec.md / checklist.md / tasks.md
        var fileName: String {
            switch role {
            case .spec: return "spec.md"
            case .checklist: return "checklist.md"
            case .tasks: return "tasks.md"
            }
        }
        /// Best-effort path as reported by file_write args.
        let path: String

        var id: String { fileName }
    }

    /// True when the Spec-mode toggle is on (regardless of master switch).
    /// Consumers must still AND with `deepModeEnabled` before engaging.
    static var modeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "deepMode.specMode")
    }

    /// True only when both the master switch and Spec mode are on.
    static func isActive(deepModeEnabled: Bool) -> Bool {
        deepModeEnabled && modeEnabled
    }

    /// Detect the sentinel token in a completed spec-writing turn's text.
    static func parse(_ text: String) -> Bool {
        text.range(of: marker, options: [.caseInsensitive, .backwards]) != nil
    }

    /// Return `text` with the trailing SPEC_STATE sentinel line removed, or nil
    /// when there is no recognizable sentinel. Mirrors VerifyGate's pattern.
    static func textWithoutSpecSentinel(_ text: String) -> String? {
        guard parse(text) else { return nil }
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

    /// Collect spec artifacts from the file_write tool blocks of the current
    /// turn. Keys off the file path's basename (spec.md / checklist.md /
    /// tasks.md), case-insensitive.
    static func detectFiles(in toolBlocks: [AssistantBlock]) -> [SpecFile] {
        var found: [Role: String] = [:]
        for block in toolBlocks {
            guard case .fileWriteTool(let path) = block.kind else { continue }
            let name = (path as NSString).lastPathComponent.lowercased()
            guard let role = role(forFileName: name) else { continue }
            if found[role] == nil { found[role] = path }
        }
        // Deterministic order: spec, checklist, tasks. Only include what exists.
        var result: [SpecFile] = []
        for role in [Role.spec, .checklist, .tasks] {
            if let path = found[role] {
                result.append(SpecFile(role: role, path: path))
            }
        }
        return result
    }

    private static func role(forFileName lowercased: String) -> Role? {
        switch lowercased {
        case "spec.md": return .spec
        case "checklist.md": return .checklist
        case "tasks.md": return .tasks
        default: return nil
        }
    }
}