import Foundation

// MARK: - ErrorRootCauseAnalyzer (C13)
// [T-deep-mode-cognitive-p2-c13] Phase 5.5: Error → root cause → strategy
// update closed loop.
//
// When VerifyGate returns `.failed`, instead of simply injecting "fix it"
// and recursing, the client now:
//   1. Injects a root-cause analysis prompt asking the model to identify
//      the fundamental reason for failure and generate a reusable rule.
//   2. Parses the model's response for a `<<ROOT_CAUSE_RULE>>` sentinel
//      containing the rule text.
//   3. Appends the rule to deep-rules.md with `auto_generated: true`
//      frontmatter so it's physically separated from user-authored rules.
//
// TOTAL-SWITCH SAFE: only invoked from maybeProcessVerifyResult, which is
// guarded by `deepModeEnabled`. When the master switch is off, the verify
// gate is never entered, no root-cause prompt is injected, and no rules
// are appended. The `auto_generated` frontmatter tag allows users to
// identify and remove machine-generated rules at any time.

enum ErrorRootCauseAnalyzer {

    /// Sentinel the model wraps its root-cause rule in.
    static let ruleSentinel = "<<ROOT_CAUSE_RULE>>"

    /// The prompt injected after a verification failure, asking the model
    /// to analyze the root cause and produce a reusable rule.
    static func rootCausePrompt(failureReason: String) -> String {
        return "<system-reminder>深度模式自检发现问题：\(failureReason)\n\n请执行以下步骤：\n1. 分析本次失败的根本原因（不是表面症状，而是根因）\n2. 提出修复方案并立即执行修复\n3. 生成一条可复用的规避规则，防止未来再次出现同类错误\n\n将规避规则包裹在 <<ROOT_CAUSE_RULE>> 和 <<ROOT_CAUSE_RULE>> 之间，格式为单行规则文本。例如：\n<<ROOT_CAUSE_RULE>>在修改iOS项目后，必须将新文件添加到project.pbxproj的4个section中<<ROOT_CAUSE_RULE>>\n\n修复完成后以 <<GOAL_STATE>> done 结束本回合。</system-reminder>"
    }

    /// Extract the root-cause rule from the model's response text.
    /// Returns the rule text if found, nil otherwise.
    static func extractRule(from text: String) -> String? {
        // Find the sentinel pair.
        let sentinel = ruleSentinel
        guard let firstRange = text.range(of: sentinel) else { return nil }
        let afterFirst = firstRange.upperBound
        guard let secondRange = text.range(of: sentinel, range: afterFirst..<text.endIndex) else {
            // Single sentinel — take everything after it until end of line.
            let rest = String(text[afterFirst...])
            let lineEnd = rest.firstIndex(of: "\n") ?? rest.endIndex
            let rule = String(rest[..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            return rule.isEmpty ? nil : rule
        }
        // Content between the two sentinels.
        let rule = String(text[afterFirst..<secondRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rule.isEmpty ? nil : rule
    }

    /// Remove the sentinel-wrapped rule from the text, returning clean text.
    static func textWithoutRuleSentinel(_ text: String) -> String {
        let sentinel = ruleSentinel
        var result = text
        while let firstRange = result.range(of: sentinel) {
            let afterFirst = firstRange.upperBound
            if let secondRange = result.range(of: sentinel, range: afterFirst..<result.endIndex) {
                // Remove everything from first sentinel to second sentinel.
                result.removeSubrange(firstRange.lowerBound..<secondRange.upperBound)
            } else {
                // Single sentinel — remove just it.
                result.removeSubrange(firstRange)
                break
            }
        }
        return result
    }

    /// Append an auto-generated rule to deep-rules.md.
    /// Uses `auto_generated: true` frontmatter so users can identify and
    /// remove machine-generated rules.
    static func appendAutoRule(_ rule: String) {
        guard !rule.isEmpty else { return }

        let ruleSection = """
        \n
        ---
        id: auto-\(Int(Date().timeIntervalSince1970))
        auto_generated: true
        alwaysApply: true
        description: "Auto-generated from verification failure"
        ---
        \(rule)
        """

        let existingBody = DeepModeStore.loadRulesBody()
        let newBody = existingBody + ruleSection

        do {
            try DeepModeStore.saveRulesBody(newBody)
            #if DEBUG
            print("[RootCauseAnalyzer] C13: auto-generated rule appended to deep-rules.md: \(rule)")
            #endif
        } catch {
            #if DEBUG
            print("[RootCauseAnalyzer] C13: failed to append rule: \(error)")
            #endif
        }
    }
}
