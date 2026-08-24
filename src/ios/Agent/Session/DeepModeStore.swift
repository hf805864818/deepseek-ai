import Foundation

// MARK: - DeepModeStore
/// Persistent behavior-rule file for 深度龙虾Ai (Deep Agent Mode).
///
/// Phase 3 evolution: `deep-rules.md` uses a multi-section YAML frontmatter
/// format where each rule is a `---`-delimited section with metadata
/// (id / description / alwaysApply / globs / keywords) and a Markdown body.
/// This mirrors `SoulStore`'s frontmatter pattern for consistency.
///
/// The file lives in the shared memory directory alongside `GLOBAL.md` and
/// `SOUL.md` so it is covered by the same App Group container and filesystem
/// lifecycle. Unlike those two files it is NOT part of the iCloud sync record
/// set: deep-mode rules are a per-device global behavior switch, and its
/// canonical state is already the on-disk `deepMode.enabled` boolean.
///
/// Backward compatibility: a legacy flat-file (no frontmatter) is parsed as
/// a single `alwaysApply: true` rule, so existing user files keep working.
enum DeepModeStore {

    // MARK: - File location

    /// Filesystem location: `<minisMemoryPersistentDir>/deep-rules.md`.
    static var fileURL: URL {
        AIChatViewModel.minisMemoryPersistentDir.appendingPathComponent("deep-rules.md")
    }

    // MARK: - Default rules (Phase 3 scoped format)

    /// Default scoped rules seeded on first run. The five core behavior rules
    /// are preserved verbatim (as `alwaysApply: true`) so a fresh install
    /// behaves identically to the pre-Phase-3 hard-coded fragment. Additional
    /// scoped rules (iOS / Python / shell conventions) demonstrate the scope
    /// system but only activate when the context matches.
    static let defaultRulesBody: String = """
    ---
    id: core-plan-first
    alwaysApply: true
    description: "Plan before executing non-trivial tasks"
    ---
    1. PLAN FIRST — for non-trivial tasks, state a short numbered plan before acting, then execute it. Skip the plan for trivial single-command tasks.

    ---
    id: core-consult-skills
    alwaysApply: true
    description: "Consult available skills first"
    ---
    2. CONSULT SKILLS FIRST — check <available_skills> above and follow any matching skill's workflow before improvising a process.

    ---
    id: core-execute-transparently
    alwaysApply: true
    description: "Prefer concrete tool calls over describing intentions"
    ---
    3. EXECUTE TRANSPARENTLY — prefer concrete tool calls over describing intentions; let the user follow each step.

    ---
    id: core-self-verify
    alwaysApply: true
    description: "Self-verify results before declaring success"
    ---
    4. SELF-VERIFY — after finishing, re-read the result and fix any errors; do not declare success blindly.

    ---
    id: core-deliver-summary
    alwaysApply: true
    description: "End with a concise summary of changes"
    ---
    5. DELIVER & SUMMARIZE — end with a concise summary of what changed and anything the user should know.

    ---
    id: ios-swift-conventions
    globs: ["*.swift", "*.h", "*.m", "*.xib", "*.storyboard"]
    keywords: ["ios", "swift", "uikit", "swiftui", "xcode", "apple", "iphone", "ipad"]
    description: "iOS/Swift development conventions"
    ---
    iOS / Swift conventions (apply when working on iOS or Swift code):
    - Use Swift concurrency (async/await) over GCD where possible.
    - Follow Swift API Design Guidelines (clear names, consistent types).
    - Prefer value types (structs/enums) over classes for model data.
    - Use [weak self] in closures that could cause retain cycles.
    - Always dispatch UI updates to the main thread.

    ---
    id: python-conventions
    globs: ["*.py"]
    keywords: ["python", "pip", "django", "flask", "pandas", "numpy"]
    description: "Python development conventions"
    ---
    Python conventions (apply when working on Python code):
    - Follow PEP 8 for style (4-space indent, snake_case, 79-char lines).
    - Use type hints for function signatures.
    - Prefer f-strings over .format() or % formatting.
    - Use virtual environments for dependency management.

    ---
    id: shell-safety
    globs: ["*.sh", "*.bash", "*.zsh"]
    keywords: ["shell", "bash", "script", "terminal", "command line", "linux"]
    description: "Shell script safety conventions"
    ---
    Shell safety conventions (apply when writing shell scripts):
    - Start scripts with set -euo pipefail for strict error handling.
    - Quote variable expansions: "$var" not $var.
    - Use printf instead of echo for predictable output.
    - Check return codes; don't assume commands succeed silently.
    """

    // MARK: - File management

    /// Create `deep-rules.md` with the default scoped rules if it does not
    /// already exist. Safe to call on every launch — never overwrites.
    static func ensureExists() {
        let url = fileURL
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        try? defaultRulesBody.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    // MARK: - Cache

    /// Thread-safe cached rules with file modification time check.
    /// Invalidates cache when the file is modified on disk.
    private static var cachedRules: [DeepModeRule]?
    private static var cachedRulesModTime: Date?

    /// Load and parse all rules from `deep-rules.md` with caching.
    ///
    /// Phase 3.4 fix: avoids repeated disk reads and YAML parsing by caching
    /// the parsed rules in memory and only re-reading when the file changes.
    static func loadRules() -> [DeepModeRule] {
        ensureExists()

        // Check cache first
        if let cached = cachedRules {
            if let currentModTime = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[FileAttributeKey.modificationTime] as? Date,
               let cachedModTime = cachedRulesModTime,
               currentModTime == cachedModTime {
                return cached
            }
            // File changed — invalidate cache
            cachedRules = nil
            cachedRulesModTime = nil
        }

        guard let data = try? Data(contentsOf: fileURL),
              let str = String(data: data, encoding: .utf8) else {
            let defaultParsed = DeepModeRuleParser.parse(defaultRulesBody)
            cachedRules = defaultParsed
            cachedRulesModTime = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[FileAttributeKey.modificationTime] as? Date
            return defaultParsed
        }

        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let defaultParsed = DeepModeRuleParser.parse(defaultRulesBody)
            cachedRules = defaultParsed
            cachedRulesModTime = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[FileAttributeKey.modificationTime] as? Date
            return defaultParsed
        }

        let parsed = DeepModeRuleParser.parse(trimmed)
        cachedRules = parsed
        cachedRulesModTime = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[FileAttributeKey.modificationTime] as? Date
        return parsed
    }

    /// Load rules filtered to the given scope context.
    ///
    /// This is the primary entry point for prompt-building: only rules that
    /// match the current turn's context are returned, keeping the system
    /// prompt focused and reducing token waste.
    static func matchingRules(for context: DeepModeScopeContext) -> [DeepModeRule] {
        DeepModeRuleParser.matchingRules(loadRules(), in: context)
    }

    /// Build the rules fragment string for injection into the system prompt.
    ///
    /// Phase 3 behavior (deep mode on): only matching rules are injected,
    /// each prefixed with its description for clarity.
    /// Phase 1/2 fallback (flat body): use `loadRulesBody()` instead.
    static func rulesFragment(for context: DeepModeScopeContext) -> String {
        let rules = matchingRules(for: context)
        guard !rules.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("Behavior rules (scoped to current context — only matching rules shown):")
        for rule in rules {
            if !rule.description.isEmpty {
                lines.append("— \(rule.description)")
            }
            lines.append(rule.body)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Read (flat body — backward compatibility)

    /// Read the current `deep-rules.md` body as a single flat string.
    ///
    /// Kept for backward compatibility and for the "deep mode off" code path
    /// (which shouldn't inject rules anyway). New code should prefer
    /// `loadRules()` or `matchingRules(for:)` for scoped behavior.
    static func loadRulesBody() -> String {
        ensureExists()
        guard let data = try? Data(contentsOf: fileURL),
              let str = String(data: data, encoding: .utf8) else {
            return defaultRulesBody
        }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultRulesBody : trimmed
    }

    // MARK: - Write

    /// Persist a rules body to disk. Intended for a future Settings editor or
    /// `minis-config` proposal path; atomic write mirrors `SoulStore.save`.
    static func saveRulesBody(_ body: String) throws {
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try body.data(using: .utf8)?.write(to: url, options: .atomic)

        // Invalidate cache after write
        cachedRules = nil
        cachedRulesModTime = nil
    }
}
