import Foundation

// MARK: - CrossSessionContextStore (C14)
// [T-deep-mode-cognitive-p2-c14] Phase 7 P2: Unified cross-mode context.
//
// This store bridges the gap between per-session memory (which dies when the
// session is deleted) and global user memory (which is too broad for project-
// specific workflow state). It persists deep-mode workflow context at the
// App level — surviving session switches, app restarts, and even a toggle
// off/on cycle of deep mode itself.
//
// What it stores:
//   - **Active project context**: What the user is currently working on
//     (e.g., "Building an iOS app with deep agent mode — Phase 2"). This
//     lets a new session pick up where the last one left off.
//   - **Recent workflow summaries**: The last N completed workflow retrospectives.
//     These are lightweight one-liners, not full transcripts.
//   - **Cross-session patterns**: Learned behavioral patterns that span
//     multiple sessions (e.g., "user prefers Swift concurrency over GCD").
//     These are distinct from `deep-rules.md` — they're contextual, not
//     behavioral rules.
//
// What it does NOT store:
//   - Conversation history (that's in the session DB)
//   - Behavioral rules (that's in `deep-rules.md`)
//   - User memory entries (that's in `memory-structured.json`)
//
// TOTAL-SWITCH SAFE:
//   - The store file exists regardless of deep mode state (it's a passive
//     data file), but it's only WRITTEN to from deep-mode code paths and
//     only READ from when `deepModeEnabled` is on.
//   - `deepModeDidDisableCleanup()` calls `clearActiveContext()` to remove
//     the active project pointer, but preserves the historical summaries
//     (they're just data — no behavioral impact when deep mode is off).
//   - The injected fragment is a pure prompt addition inside
//     `deepModeFragment`, so when the master switch is off, the fragment
//     is never appended — zero behavioral residue.

/// A single cross-session context entry.
struct CrossSessionEntry: Codable, Identifiable, Equatable {
    let id: String
    let type: EntryType
    let content: String
    let createdAt: Date
    let updatedAt: Date
    /// Optional session ID this entry originated from.
    var sourceSessionId: String?

    enum EntryType: String, Codable {
        /// Active project context — what the user is currently working on.
        case activeProject
        /// A completed workflow retrospective summary (one-liner).
        case workflowSummary
        /// A cross-session learned pattern.
        case learnedPattern
    }

    init(id: String = UUID().uuidString,
         type: EntryType,
         content: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         sourceSessionId: String? = nil) {
        self.id = id
        self.type = type
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceSessionId = sourceSessionId
    }
}

enum CrossSessionContextStore {

    // MARK: - File location

    /// Filesystem location: `<minisMemoryPersistentDir>/deep-cross-session.json`.
    static var fileURL: URL {
        AIChatViewModel.minisMemoryPersistentDir.appendingPathComponent("deep-cross-session.json")
    }

    // MARK: - Cache

    private static var cachedEntries: [CrossSessionEntry]?
    private static var cachedModTime: Date?

    // MARK: - Load / Save

    /// Load all cross-session entries with cache.
    static func loadEntries() -> [CrossSessionEntry] {
        let fm = FileManager.default
        let url = fileURL

        // Check cache
        if let cached = cachedEntries,
           let modTime = cachedModTime,
           fm.fileExists(atPath: url.path) {
            if let currentMod = try? fm.attributesOfItem(atPath: url.path)[FileAttributeKey.modificationDate] as? Date,
               currentMod == modTime {
                return cached
            }
            cachedEntries = nil
            cachedModTime = nil
        }

        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([CrossSessionEntry].self, from: data) else {
            return []
        }

        cachedEntries = entries
        cachedModTime = try? fm.attributesOfItem(atPath: url.path)[FileAttributeKey.modificationDate] as? Date
        return entries
    }

    /// Persist entries to disk atomically.
    static func saveEntries(_ entries: [CrossSessionEntry]) throws {
        let url = fileURL
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        try data.write(to: url, options: .atomic)
        cachedEntries = nil
        cachedModTime = nil
    }

    // MARK: - CRUD

    /// Set the active project context. Replaces any existing active project.
    @discardableResult
    static func setActiveProject(_ content: String, sessionId: String? = nil) throws -> CrossSessionEntry {
        var entries = loadEntries()
        // Remove any existing active project
        entries.removeAll { $0.type == .activeProject }
        let entry = CrossSessionEntry(
            type: .activeProject,
            content: content,
            sourceSessionId: sessionId
        )
        entries.insert(entry, at: 0)
        try saveEntries(entries)
        return entry
    }

    /// Get the active project context, if any.
    static func getActiveProject() -> CrossSessionEntry? {
        loadEntries().first { $0.type == .activeProject }
    }

    /// Clear the active project context. Called on deep mode disable.
    static func clearActiveProject() throws {
        var entries = loadEntries()
        entries.removeAll { $0.type == .activeProject }
        try saveEntries(entries)
    }

    /// Append a workflow summary. Keeps only the last 10 to avoid bloat.
    @discardableResult
    static func appendWorkflowSummary(_ content: String, sessionId: String? = nil) throws -> CrossSessionEntry {
        var entries = loadEntries()
        let entry = CrossSessionEntry(
            type: .workflowSummary,
            content: content,
            sourceSessionId: sessionId
        )
        entries.insert(entry, at: 0)

        // Trim: keep only last 10 workflow summaries
        var summaries = entries.filter { $0.type == .workflowSummary }
        if summaries.count > 10 {
            let toRemove = Set(summaries.dropFirst(10).map { $0.id })
            entries.removeAll { toRemove.contains($0.id) }
        }
        _ = summaries  // suppress unused warning

        try saveEntries(entries)
        return entry
    }

    /// Append a learned pattern.
    @discardableResult
    static func appendLearnedPattern(_ content: String, sessionId: String? = nil) throws -> CrossSessionEntry {
        var entries = loadEntries()
        // Deduplicate: if an identical pattern exists, update it instead
        if let idx = entries.firstIndex(where: { $0.type == .learnedPattern && $0.content == content }) {
            var updated = entries[idx]
            updated.updatedAt = Date()
            entries[idx] = updated
            try saveEntries(entries)
            return updated
        }
        let entry = CrossSessionEntry(
            type: .learnedPattern,
            content: content,
            sourceSessionId: sessionId
        )
        entries.insert(entry, at: 0)
        try saveEntries(entries)
        return entry
    }

    /// Delete an entry by id.
    static func delete(id: String) throws {
        var entries = loadEntries()
        entries.removeAll { $0.id == id }
        try saveEntries(entries)
    }

    // MARK: - Prompt Injection

    /// Build a cross-session context fragment for injection into the system
    /// prompt. Returns nil if there are no entries.
    ///
    /// This fragment gives the model continuity across sessions: it knows what
    /// the user was last working on, what patterns were learned, and what
    /// workflows were recently completed.
    static func contextFragment() -> String? {
        let entries = loadEntries()
        guard !entries.isEmpty else { return nil }

        var sections: [String] = []

        // Active project
        if let project = entries.first(where: { $0.type == .activeProject }) {
            sections.append("【当前项目上下文】\n• \(project.content)")
        }

        // Recent workflow summaries (last 5)
        let summaries = entries.filter { $0.type == .workflowSummary }.prefix(5)
        if !summaries.isEmpty {
            var s = "【近期工作流回顾】"
            let bullets = summaries.map { "• \($0.content)" }
            s += "\n" + bullets.joined(separator: "\n")
            sections.append(s)
        }

        // Learned patterns (last 5)
        let patterns = entries.filter { $0.type == .learnedPattern }.prefix(5)
        if !patterns.isEmpty {
            var s = "【跨会话学习模式】"
            let bullets = patterns.map { "• \($0.content)" }
            s += "\n" + bullets.joined(separator: "\n")
            sections.append(s)
        }

        guard !sections.isEmpty else { return nil }

        var result = "Cross-session context (from deep-cross-session.json — context from previous deep-mode sessions; use as background, not standing instructions):\n"
        result += sections.joined(separator: "\n\n")
        return result
    }
}
