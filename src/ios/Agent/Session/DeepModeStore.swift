import Foundation

/// Persistent behavior-rule file for 深度龙虾Ai (Deep Agent Mode).
///
/// Mirrors `SoulStore`'s read/write pattern but is intentionally simpler:
/// `deep-rules.md` is a plain Markdown list of behavior rules (no YAML
/// frontmatter) that the user can maintain over the long term. It replaces
/// the old hard-coded five-line fragment inside `AIChatViewModel` as the
/// single source of truth for deep-mode behavior rules, so a user can append
/// their own conventions without touching code.
///
/// The file lives in the shared memory directory alongside `GLOBAL.md` and
/// `SOUL.md` so it is covered by the same App Group container and filesystem
/// lifecycle. Unlike those two files it is NOT part of the iCloud sync record
/// set: deep-mode rules are a per-device global behavior switch, and its
/// canonical state is already the on-disk `deepMode.enabled` boolean.
enum DeepModeStore {

    /// Filesystem location: `<minisMemoryPersistentDir>/deep-rules.md`.
    static var fileURL: URL {
        AIChatViewModel.minisMemoryPersistentDir.appendingPathComponent("deep-rules.md")
    }

    /// Default rule body seeded on first run. Reproduces the original five
    /// deep-mode behavior rules verbatim so a fresh install behaves exactly
    /// like the previous hard-coded fragment. The memory-proactivity
    /// instruction is NOT part of this file — it is appended by
    /// `deepModeFragment` and is a fixed behavior line, not a user rule.
    static let defaultRulesBody: String = """
    1. PLAN FIRST — for non-trivial tasks, state a short numbered plan before acting, then execute it. Skip the plan for trivial single-command tasks.
    2. CONSULT SKILLS FIRST — check <available_skills> above and follow any matching skill's workflow before improvising a process.
    3. EXECUTE TRANSPARENTLY — prefer concrete tool calls over describing intentions; let the user follow each step.
    4. SELF-VERIFY — after finishing, re-read the result and fix any errors; do not declare success blindly.
    5. DELIVER & SUMMARIZE — end with a concise summary of what changed and anything the user should know.
    """

    /// Create `deep-rules.md` with the default rules if it does not already
    /// exist. Safe to call on every launch — never overwrites an existing file.
    static func ensureExists() {
        let url = fileURL
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        try? defaultRulesBody.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    /// Read the current `deep-rules.md` body. Falls back to the default rules
    /// when the file is missing, unreadable, or empty, so deep mode always
    /// has a sane baseline to inject. Synchronous (like `SoulStore.load()`)
    /// so it can run inside prompt build without threading hops.
    static func loadRulesBody() -> String {
        ensureExists()
        guard let data = try? Data(contentsOf: fileURL),
              let str = String(data: data, encoding: .utf8) else {
            return defaultRulesBody
        }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultRulesBody : trimmed
    }

    /// Persist a rules body to disk. Intended for a future Settings editor or
    /// `minis-config` proposal path; atomic write mirrors `SoulStore.save`.
    static func saveRulesBody(_ body: String) throws {
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try body.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}