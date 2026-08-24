import Foundation

// MARK: - DeepModeRule
// Phase 3: Scoped behavior rule for 深度龙虾Ai.
//
// Each rule has a YAML frontmatter block (delimited by `---`) that carries
// metadata (id / description / alwaysApply / globs / keywords) followed by
// a free-form Markdown body. This mirrors SoulStore's frontmatter pattern
// so the parser style is consistent across the codebase.
//
// Rules are matched against a "scope context" (file paths mentioned in the
// conversation + keywords from the user's input). A rule applies when:
//   - alwaysApply == true, OR
//   - any glob pattern matches a file path in scope, OR
//   - any keyword appears in the user's latest message.

/// A single scoped rule parsed from deep-rules.md.
struct DeepModeRule: Identifiable, Equatable {
    /// Stable unique identifier. Used for dedup and future UI editors.
    let id: String
    /// Short human-readable description (shown in debug output, not injected).
    let description: String
    /// If true, this rule is always injected regardless of scope.
    let alwaysApply: Bool
    /// Glob patterns (e.g. "*.swift", "src/**/*.py"). Matched against file paths.
    let globs: [String]
    /// Keywords to match against user input (case-insensitive, substring match).
    let keywords: [String]
    /// The rule body text injected into the system prompt.
    let body: String
}

// MARK: - Parser

enum DeepModeRuleParser {

    /// Parse the full content of deep-rules.md into an array of scoped rules.
    ///
    /// Backward-compatible: if the file has no frontmatter at all (legacy
    /// format), the entire content is treated as a single rule with
    /// `alwaysApply: true` and an auto-generated id.
    static func parse(_ content: String) -> [DeepModeRule] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Legacy format: no leading frontmatter → treat whole file as one always-apply rule.
        if !trimmed.hasPrefix("---") {
            return [
                DeepModeRule(
                    id: "legacy-default",
                    description: "Legacy flat rules (pre-Phase-3 format)",
                    alwaysApply: true,
                    globs: [],
                    keywords: [],
                    body: trimmed
                )
            ]
        }

        // Split on `---` frontmatter boundaries. Each section between two
        // `---` lines (plus the body after the closing `---`) is one rule.
        let lines = trimmed.components(separatedBy: "\n")
        var rules: [DeepModeRule] = []
        var i = 0
        let n = lines.count

        while i < n {
            // Find opening ---
            guard lines[i].trimmingCharacters(in: .whitespaces) == "---" else {
                // Skip non-frontmatter lines (shouldn't happen in well-formed files,
                // but we tolerate leading blank lines / comments).
                i += 1
                continue
            }
            i += 1 // skip opening ---

            // Collect frontmatter lines until closing ---
            var frontmatterLines: [String] = []
            while i < n && lines[i].trimmingCharacters(in: .whitespaces) != "---" {
                frontmatterLines.append(lines[i])
                i += 1
            }
            guard i < n else {
                // Malformed: no closing --- . Stop parsing.
                break
            }
            i += 1 // skip closing ---

            // Collect body lines until next --- or end of file
            var bodyLines: [String] = []
            while i < n && lines[i].trimmingCharacters(in: .whitespaces) != "---" {
                bodyLines.append(lines[i])
                i += 1
            }

            let meta = parseFrontmatter(frontmatterLines)
            let body = bodyLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !body.isEmpty else { continue }

            rules.append(DeepModeRule(
                id: meta.id ?? "rule-\(rules.count)",
                description: meta.description ?? "",
                alwaysApply: meta.alwaysApply,
                globs: meta.globs,
                keywords: meta.keywords,
                body: body
            ))
        }

        // If no rules were parsed (malformed file), fall back to legacy behavior
        // so deep mode never runs with zero rules.
        if rules.isEmpty {
            return [
                DeepModeRule(
                    id: "fallback-single",
                    description: "Fallback (parse produced no rules)",
                    alwaysApply: true,
                    globs: [],
                    keywords: [],
                    body: trimmed
                )
            ]
        }

        return rules
    }

    // MARK: - Frontmatter parsing

    private struct RuleMetadata {
        var id: String?
        var description: String?
        var alwaysApply: Bool = false
        var globs: [String] = []
        var keywords: [String] = []
    }

    private static func parseFrontmatter(_ lines: [String]) -> RuleMetadata {
        var meta = RuleMetadata()

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            // key: value  OR  key: [item1, item2]  OR  key:
            //   - item1
            //   - item2
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let valueStr = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)

            switch key {
            case "id":
                meta.id = stripQuotes(valueStr).nilIfEmpty
            case "description", "desc":
                meta.description = stripQuotes(valueStr).nilIfEmpty
            case "alwaysapply", "always_apply", "always-apply":
                meta.alwaysApply = (valueStr.lowercased() == "true" || valueStr == "yes")
            case "globs", "glob":
                meta.globs = parseList(valueStr)
            case "keywords", "keyword", "tags":
                meta.keywords = parseList(valueStr).map { $0.lowercased() }
            default:
                break
            }
        }

        return meta
    }

    /// Parse a value that may be:
    ///   - "[item1, item2]" (inline array)
    ///   - "item1" (single value)
    ///   - "" (empty)
    /// YAML block-style arrays (indented `- item`) are NOT supported by this
    /// simple parser — the inline form is sufficient for rule metadata and
    /// keeps the parser tiny and safe.
    private static func parseList(_ value: String) -> [String] {
        let s = value.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return [] }

        // Inline array: [a, b, c]
        if s.hasPrefix("[") && s.hasSuffix("]") {
            let inner = s.dropFirst().dropLast()
            return inner
                .components(separatedBy: ",")
                .map { stripQuotes($0.trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.isEmpty }
        }

        // Single value
        let stripped = stripQuotes(s)
        return stripped.isEmpty ? [] : [stripped]
    }

    private static func stripQuotes(_ s: String) -> String {
        var str = s
        if str.hasPrefix("\"") && str.hasSuffix("\"") && str.count >= 2 {
            str = String(str.dropFirst().dropLast())
        }
        if str.hasPrefix("'") && str.hasSuffix("'") && str.count >= 2 {
            str = String(str.dropFirst().dropLast())
        }
        return str
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Scope matching

/// Context used to decide which rules apply for the current turn.
///
/// Collected by the view model from the conversation state and passed to
/// `DeepModeStore.matchingRules(for:)`.
struct DeepModeScopeContext: Equatable {
    /// File paths mentioned in recent messages (relative or absolute).
    let mentionedFilePaths: [String]
    /// The user's latest message text, lowercased for keyword matching.
    let userInputLowercased: String
}

extension DeepModeRuleParser {

    /// Filter rules by scope context. A rule is included if:
    ///   - alwaysApply == true, OR
    ///   - any glob matches any mentioned file path, OR
    ///   - any keyword appears in the user's input.
    static func matchingRules(_ rules: [DeepModeRule], in context: DeepModeScopeContext) -> [DeepModeRule] {
        rules.filter { rule in
            if rule.alwaysApply { return true }
            if matchesAnyGlob(rule.globs, paths: context.mentionedFilePaths) { return true }
            if matchesAnyKeyword(rule.keywords, input: context.userInputLowercased) { return true }
            return false
        }
    }

    // MARK: - Glob matching

    /// Cache: compiled NSPredicate per glob string. NSPredicate construction
    /// is expensive (parses the regex string); globs are a small fixed set that
    /// repeat across every deep-mode turn, so caching them removes the dominant
    /// cost of per-turn rule matching. Purely a performance cache — the results
    /// are byte-identical to building the predicate fresh, so behavior is
    /// unchanged whether deep mode is on or off (this code is only reachable
    /// from deep-mode rule matching anyway).
    private static let globPredicateCacheLock = NSLock()
    private static var globPredicateCache: [String: NSPredicate] = [:]

    /// Test if any glob pattern matches any of the given paths.
    /// Uses `fnmatch`-style globbing via `NSPredicate` with MATCHES operator.
    static func matchesAnyGlob(_ globs: [String], paths: [String]) -> Bool {
        guard !globs.isEmpty, !paths.isEmpty else { return false }
        for glob in globs {
            let predicate = predicate(forGlob: glob)
            for path in paths {
                if predicate.evaluate(with: path) {
                    return true
                }
                // Also try matching just the last path component (filename)
                let fileName = (path as NSString).lastPathComponent
                if !fileName.isEmpty, fileName != path, predicate.evaluate(with: fileName) {
                    return true
                }
            }
        }
        return false
    }

    /// Return a compiled NSPredicate for a glob, reusing a cached one when
    /// available. Thread-safe; result is deterministic (pure function of glob).
    private static func predicate(forGlob glob: String) -> NSPredicate {
        globPredicateCacheLock.lock()
        defer { globPredicateCacheLock.unlock() }
        if let cached = globPredicateCache[glob] {
            return cached
        }
        let predicate = NSPredicate(format: "SELF MATCHES %@", fnmatchRegex(from: glob))
        // Bound the cache so a pathological unbounded glob set can't grow it
        // forever; rule globs are small/fixed in practice.
        if globPredicateCache.count >= 256 {
            globPredicateCache.removeAll()
        }
        globPredicateCache[glob] = predicate
        return predicate
    }

    /// Convert a shell-style glob pattern to a regex string for NSPredicate MATCHES.
    ///
    /// Supported: `*` (any chars except /), `**` (any chars including /), `?` (single char),
    /// character classes `[abc]`. Everything else is escaped for literal matching.
    private static func fnmatchRegex(from glob: String) -> String {
        var regex = ""
        var chars = Array(glob)
        var i = 0
        let n = chars.count

        while i < n {
            let c = chars[i]
            switch c {
            case "*":
                // Check for **
                if i + 1 < n && chars[i + 1] == "*" {
                    regex += ".*"
                    i += 2
                    // Skip trailing / after ** to match "**/foo" style
                    if i < n && chars[i] == "/" {
                        regex += "/*"
                        i += 1
                    }
                } else {
                    regex += "[^/]*"
                    i += 1
                }
            case "?":
                regex += "[^/]"
                i += 1
            case "[":
                // Character class — find closing ]
                var j = i + 1
                while j < n && chars[j] != "]" { j += 1 }
                if j < n {
                    let cls = String(chars[i...j])
                    regex += cls
                    i = j + 1
                } else {
                    regex += "\\["
                    i += 1
                }
            case ".", "+", "(", ")", "^", "$", "{", "}", "|", "\\":
                regex += "\\\(c)"
                i += 1
            default:
                regex += String(c)
                i += 1
            }
        }

        // Anchor to match full path
        return "^\(regex)$"
    }

    // MARK: - Keyword matching

    /// Test if any keyword appears as a substring in the user input (lowercased).
    static func matchesAnyKeyword(_ keywords: [String], input: String) -> Bool {
        guard !keywords.isEmpty, !input.isEmpty else { return false }
        for kw in keywords {
            guard !kw.isEmpty else { continue }
            if input.contains(kw.lowercased()) {
                return true
            }
        }
        return false
    }
}
