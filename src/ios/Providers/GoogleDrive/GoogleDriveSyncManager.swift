import Foundation
import SwiftUI
import os.log
import SQLite3

private let logger = AppLogger(category: "GoogleDriveSync")

// MARK: - Sync Manager

/// Backup and restore sync manager for Google Drive.
/// Creates ZIP archives of the app's documents directory and uploads
/// them to a dedicated "Minis" folder in the user's Google Drive.
/// Supports manual backup/restore and automatic periodic sync.
///
/// Note: This class is NOT @MainActor. Heavy I/O work (file collection,
/// ZIP building, extraction) runs on the calling cooperative thread.
/// Only @Published properties are isolated to the main actor via
/// MainActor.run {} at the call sites.
final class GoogleDriveSyncManager: ObservableObject {

    static let shared = GoogleDriveSyncManager()

    // MARK: - Configuration

    /// App folder name in Google Drive root.
    private let appFolderName = "Minis"
    /// Backup file name prefix.
    private let backupPrefix = "minis-backup-"
    /// Auto-sync interval (4 hours).
    private let autoSyncInterval: TimeInterval = 4 * 60 * 60

    /// Date formatter for backup file names (UTC).
    private static let backupDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    // MARK: - Published State (must be accessed on main actor)

    @MainActor @Published private(set) var isBackingUp = false
    @MainActor @Published private(set) var isRestoring = false
    @MainActor @Published private(set) var syncError: String?
    @MainActor @Published private(set) var backupCount = 0
    @MainActor @Published private(set) var totalBackupSize: Int64 = 0

    // MARK: - AppStorage (persistent settings)

    @AppStorage("gdrive.autoSync.enabled") var isAutoSyncEnabled: Bool = false
    @AppStorage("gdrive.lastSync") private var lastSyncTimestamp: Double = 0
    @AppStorage("gdrive.appFolderId") private var storedAppFolderId: String = ""

    /// Maximum number of backup files to keep in Google Drive.
    /// Older backups beyond this limit are automatically deleted after
    /// each successful backup. Default is 5 to conserve Drive storage.
    @AppStorage("gdrive.maxBackups") var maxBackups: Int = 5

    // MARK: - Computed Properties

    var lastSyncDate: Date? {
        lastSyncTimestamp > 0 ? Date(timeIntervalSince1970: lastSyncTimestamp) : nil
    }

    var appFolderId: String? {
        storedAppFolderId.isEmpty ? nil : storedAppFolderId
    }

    // MARK: - Private

    private var autoSyncTask: Task<Void, Never>?

    private init() {
        if isAutoSyncEnabled {
            startAutoSync()
        }
    }

    // MARK: - Backup

    /// Creates a ZIP archive of the app's documents directory and uploads
    /// it to Google Drive. Updates sync state on completion.
    ///
    /// Heavy work (file collection, ZIP building) runs on a background
    /// thread via `Task.detached` so the MainActor / UI thread is never
    /// blocked. The caller does NOT need to catch errors — all errors
    /// are handled internally by setting `syncError` and resetting
    /// `isBackingUp`.
    func backup() async {
        // Check backing up flag on main actor
        let alreadyBackingUp = await MainActor.run { isBackingUp }
        guard !alreadyBackingUp else {
            logger.warning("Backup already in progress — skipping")
            return
        }

        await MainActor.run {
            isBackingUp = true
            syncError = nil
        }

        // Use fire-and-forget Task to avoid blocking MainActor.
        // The .value call on Task.detached was causing deadlocks because it
        // synchronously waits on the current actor, blocking the UI thread.
        Task {
            do {
                try await self.backupInternal()
            } catch {
                logger.error("Backup failed: \(error.localizedDescription)")
                await MainActor.run {
                    isBackingUp = false
                    syncError = error.localizedDescription
                }
                return
            }
            // Reset on success path
            await MainActor.run {
                isBackingUp = false
            }
        }
    }

    private func backupInternal() async throws {
        logger.info("=== Google Drive backup started ===")

        // 1. Collect all files from documents directory AND Library/MinisChat
        //    (I/O — runs on background). Library/MinisChat contains minis.db,
        //    skills.db, and the minis/ file assets directory. Without these,
        //    the backup only covers the iSH rootfs but not the actual chat data.
        let docsDir = documentsDirectory
        let libDir = libraryMinisChatDirectory
        logger.info("Step 1a: collecting files from docs dir...")
        var files = collectFiles(in: docsDir, prefix: "docs/")
        logger.info("Step 1a: collected \(files.count) files from docs")
        logger.info("Step 1b: collecting files from library/MinisChat...")
        files.append(contentsOf: collectFiles(in: libDir, prefix: "lib/MinisChat/"))
        logger.info("Step 1b: collected \(files.count) total files (docs + library)")

        // 1c. Include app settings snapshot (independent of iCloud sync)
        if let settingsData = await MainActor.run(body: { AppSettingsSync.buildBackupPayload() }) {
            files.append((relativePath: "settings/settings.json", data: settingsData))
            logger.info("Added settings/settings.json to backup")
        }

        if files.isEmpty {
            throw LLMError.providerError(message: "No files found to back up")
        }

        // Log total size before ZIP
        let totalRawSize = files.reduce(0) { $0 + $1.data.count }
        logger.info("Step 2: building ZIP archive (\(files.count) files, \(totalRawSize) bytes raw)...")

        // 2. Create ZIP archive (CPU + memory heavy — runs on background)
        let zipData = SkillStore.buildZipArchive(files: files)
        let fileSize = zipData.count
        logger.info("Step 2: ZIP built: \(fileSize) bytes")

        // 3. Ensure app folder exists in Drive
        logger.info("Step 3: ensuring app folder exists in Drive...")
        let folderId = try await ensureAppFolder()
        logger.info("Step 3: app folder ID: \(folderId)")

        // 4. Upload backup file
        logger.info("Step 4: uploading \(fileSize) bytes to Drive...")
        let timestamp = Self.backupDateFormatter.string(from: Date())
        let fileName = "\(backupPrefix)\(timestamp).zip"
        let mimeType = "application/zip"

        let fileId: String
        if fileSize > 5 * 1024 * 1024 {
            // Large file — use resumable upload
            logger.info("Step 4: using resumable upload for \(fileSize) bytes")
            fileId = try await GoogleDriveAPI.uploadFileResumable(
                name: fileName,
                data: zipData,
                parentId: folderId,
                mimeType: mimeType,
                progressHandler: { progress in
                    logger.info("Upload progress: \(Int(progress * 100))%")
                }
            )
        } else {
            logger.info("Step 4: using multipart upload for \(fileSize) bytes")
            fileId = try await GoogleDriveAPI.uploadFile(
                name: fileName,
                data: zipData,
                parentId: folderId,
                mimeType: mimeType
            )
        }
        logger.info("Step 4: upload complete, fileId: \(fileId)")

        // 5. Update sync state
        lastSyncTimestamp = Date().timeIntervalSince1970
        await MainActor.run { syncError = nil }
        logger.info("=== Google Drive backup complete: \(fileId) ===")

        // 6. Clean up old backups beyond maxBackups limit
        try? await cleanupOldBackups(folderId: folderId)

        // 7. Refresh backup list
        try? await refreshBackupStats(folderId: folderId)
    }

    // MARK: - Restore

    /// Downloads the latest backup from Google Drive and restores it
    /// to the app's documents directory.
    func restore() async throws {
        let alreadyRestoring = await MainActor.run { isRestoring }
        guard !alreadyRestoring else {
            logger.warning("Restore already in progress — skipping")
            return
        }

        await MainActor.run {
            isRestoring = true
            syncError = nil
        }

        do {
            try await restoreInternal()
        } catch {
            await MainActor.run {
                isRestoring = false
                syncError = error.localizedDescription
            }
            throw error
        }
        await MainActor.run {
            isRestoring = false
        }
    }

    private func restoreInternal() async throws {
        logger.info("=== Google Drive restore started ===")

        // 1. Get latest backup
        let backups = try await listBackups()
        guard let latest = backups.first else {
            throw LLMError.providerError(message: "No backups found in Google Drive")
        }
        logger.info("Latest backup: \(latest.name) (modified: \(String(describing: latest.modifiedTime)))")

        // 2. Download backup file
        let zipData = try await GoogleDriveAPI.downloadFile(fileId: latest.id)
        logger.info("Backup downloaded: \(zipData.count) bytes")

        // 3. Merge backup into local storage (LWW conflict resolution)
        try await mergeBackup(zipData)

        logger.info("=== Google Drive restore complete ===")
    }

    /// Restores from a specific backup file by its ID.
    func restoreFrom(fileId: String) async throws {
        let alreadyRestoring = await MainActor.run { isRestoring }
        guard !alreadyRestoring else {
            logger.warning("Restore already in progress — skipping")
            return
        }

        await MainActor.run {
            isRestoring = true
            syncError = nil
        }

        do {
            try await restoreFromInternal(fileId: fileId)
        } catch {
            await MainActor.run {
                isRestoring = false
                syncError = error.localizedDescription
            }
            throw error
        }
        await MainActor.run {
            isRestoring = false
        }
    }

    private func restoreFromInternal(fileId: String) async throws {
        logger.info("=== Google Drive restore from \(fileId) started ===")

        // 1. Download backup file
        let zipData = try await GoogleDriveAPI.downloadFile(fileId: fileId)
        logger.info("Backup downloaded: \(zipData.count) bytes")

        // 2. Merge backup into local storage (LWW conflict resolution)
        try await mergeBackup(zipData)

        logger.info("=== Google Drive restore complete ===")
    }

    // MARK: - Backup Listing

    /// Lists all backup files in the app's Google Drive folder,
    /// sorted by modified time (newest first).
    func listBackups() async throws -> [GoogleDriveFile] {
        let folderId = try await ensureAppFolder()
        let allFiles = try await GoogleDriveAPI.listFiles(parentId: folderId)

        // Filter to only backup files
        let backups = allFiles
            .filter { $0.name.hasPrefix(backupPrefix) && $0.name.hasSuffix(".zip") }
            .sorted { a, b in
                (a.modifiedTime ?? .distantPast) > (b.modifiedTime ?? .distantPast)
            }

        let count = backups.count
        let totalSize = backups.reduce(0) { $0 + ($1.size ?? 0) }

        // Update published stats (on main actor)
        await MainActor.run {
            backupCount = count
            totalBackupSize = totalSize
        }

        logger.info("Found \(count) backups totaling \(totalSize) bytes")
        return backups
    }

    /// Deletes a specific backup file from Google Drive.
    func deleteBackup(fileId: String) async throws {
        logger.info("Deleting backup: \(fileId)")
        try await GoogleDriveAPI.deleteFile(fileId: fileId)

        // Refresh stats
        if let folderId = appFolderId {
            try? await refreshBackupStats(folderId: folderId)
        }
    }

    /// Removes oldest backups that exceed the maxBackups limit.
    /// Called automatically after each successful backup. Uses
    /// try? so cleanup failures never block the backup itself.
    private func cleanupOldBackups(folderId: String) async throws {
        let allFiles = try await GoogleDriveAPI.listFiles(parentId: folderId)
        let backups = allFiles
            .filter { $0.name.hasPrefix(backupPrefix) && $0.name.hasSuffix(".zip") }
            .sorted { a, b in
                (a.modifiedTime ?? .distantPast) > (b.modifiedTime ?? .distantPast)
            }

        let limit = max(maxBackups, 1)
        guard backups.count > limit else {
            logger.info("Cleanup: \(backups.count) backups, limit is \(limit) — nothing to delete")
            return
        }

        let toDelete = Array(backups.dropFirst(limit))
        logger.info("Cleanup: deleting \(toDelete.count) old backup(s) to stay within limit of \(limit)")

        for backup in toDelete {
            do {
                try await GoogleDriveAPI.deleteFile(fileId: backup.id)
                logger.info("Deleted old backup: \(backup.name)")
            } catch {
                logger.warning("Failed to delete old backup \(backup.name): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Auto Sync

    /// Starts the auto-sync timer (4 hour interval) if auto-sync is enabled.
    func startAutoSync() {
        stopAutoSync()
        let interval = autoSyncInterval
        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                guard let self else { return }
                logger.info("Auto-sync triggered")
                await self.backup()
            }
        }
        logger.info("Auto-sync started (interval: \(Int(interval / 60)) min)")
    }

    /// Stops the auto-sync timer.
    func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
        logger.info("Auto-sync stopped")
    }

    // MARK: - Private Helpers

    /// Returns the app's documents directory URL.
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Returns the Library/MinisChat directory URL (where minis.db,
    /// skills.db, and the minis/ file assets directory live).
    private var libraryMinisChatDirectory: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return libraryURL.appendingPathComponent("MinisChat", isDirectory: true)
    }

    /// Ensures the "Minis" app folder exists in Google Drive root.
    /// Caches the folder ID in @AppStorage for subsequent calls.
    private func ensureAppFolder() async throws -> String {
        // Return cached ID if available
        if let cached = appFolderId {
            // Verify the folder still exists
            if let _ = try? await GoogleDriveAPI.getFileMetadata(fileId: cached) {
                return cached
            }
            // Folder was deleted — clear cache and recreate
            logger.warning("Cached app folder no longer exists — recreating")
            storedAppFolderId = ""
        }

        // Find or create the folder
        let folderId = try await GoogleDriveAPI.findOrCreateFolder(name: appFolderName)
        storedAppFolderId = folderId
        logger.info("App folder ensured: \(folderId)")
        return folderId
    }

    /// Walks a directory and collects all files with their relative paths
    /// and data. The optional prefix is prepended to each relative path
    /// so multiple source directories can be distinguished in the ZIP.
    private func collectFiles(in directory: URL, prefix: String = "") -> [(relativePath: String, data: Data)] {
        var files: [(relativePath: String, data: Data)] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.error("Failed to enumerate directory: \(directory.path)")
            return files
        }

        let basePath = directory.path + "/"
        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            if isDir.boolValue { continue }

            // Skip backup files if they somehow end up in documents
            let name = fileURL.lastPathComponent
            if name.hasPrefix(backupPrefix) && name.hasSuffix(".zip") { continue }

            // Skip SQLite WAL/SHM temp files — they are transient and
            // including them in the backup can corrupt the DB on restore.
            if name.hasSuffix("-wal") || name.hasSuffix("-shm") { continue }

            let relativePath = prefix + fileURL.path.replacingOccurrences(of: basePath, with: "")
            if let data = try? Data(contentsOf: fileURL) {
                files.append((relativePath: relativePath, data: data))
            } else {
                logger.warning("Failed to read file: \(relativePath)")
            }
        }

        return files
    }

    /// Merges a backup ZIP into local storage. Instead of overwriting all
    /// files, this walks the backup and applies records with LWW (last-write-
    /// wins) conflict resolution — the same logic used by iCloud sync.
    ///
    /// For SQLite databases (minis.db, skills.db), records are read from the
    /// backup DB and merged into the live DB through the existing mergeRemote*
    /// methods. For file assets, files are copied only if they are missing
    /// locally or the backup copy is newer.
    ///
    /// Old-format backups (without docs/ or lib/ prefixes) fall back to
    /// the original extract-and-overwrite behavior for backward compatibility.
    private func mergeBackup(_ zipData: Data) async throws {
        let entries: [SkillStore.ZipEntry]
        do {
            entries = try SkillStore.readZipEntries(data: zipData)
        } catch {
            logger.error("Failed to read ZIP entries: \(error.localizedDescription)")
            throw LLMError.providerError(message: "Failed to read backup archive: \(error.localizedDescription)")
        }

        let fileEntries = entries.filter { !$0.isDirectory }
        let isNewFormat = fileEntries.contains { $0.name.hasPrefix("docs/") || $0.name.hasPrefix("lib/") || $0.name.hasPrefix("settings/") }

        if isNewFormat {
            try await mergeBackupNewFormat(fileEntries)
        } else {
            // Old format backup — extract directly to documents (backward compat)
            logger.info("Old-format backup detected — extracting to documents directory")
            try extractBackupOldFormat(fileEntries)
        }
    }

    /// Merges a new-format backup (with docs/ and lib/ prefixes).
    private func mergeBackupNewFormat(_ entries: [SkillStore.ZipEntry]) async throws {
        // 1. Extract everything to a temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minis-restore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for entry in entries {
            let destURL = tempDir.appendingPathComponent(entry.name)
            let parentDir = destURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try entry.data.write(to: destURL)
        }
        logger.info("Extracted \(entries.count) entries to temp directory for merging")

        // 2. Merge minis.db (sessions, messages, folders, compact_markers)
        let backupDBURL = tempDir.appendingPathComponent("lib/MinisChat/minis.db")
        if FileManager.default.fileExists(atPath: backupDBURL.path) {
            try await mergeMinisDatabase(from: backupDBURL)
        } else {
            logger.warning("Backup does not contain minis.db — skipping DB merge")
        }

        // 3. Merge skills.db + skill files
        let backupSkillsURL = tempDir.appendingPathComponent("lib/MinisChat/skills.db")
        if FileManager.default.fileExists(atPath: backupSkillsURL.path) {
            try await mergeSkillsDatabase(from: backupSkillsURL, tempDir: tempDir)
        }

        // 4. Copy file assets with deduplication
        try copyFileAssets(from: tempDir)

        // 4b. Apply settings snapshot (independent of iCloud sync)
        let settingsURL = tempDir.appendingPathComponent("settings/settings.json")
        if FileManager.default.fileExists(atPath: settingsURL.path),
           let settingsData = try? Data(contentsOf: settingsURL) {
            await MainActor.run { AppSettingsSync.applyBackupPayload(settingsData) }
            logger.info("Applied settings from backup")
        }

        // 5. Reload databases so in-memory caches pick up merged data
        await ChatStore.shared.reloadDatabase()
        await MainActor.run {
            SkillStore.shared.reloadDatabase()
        }
        logger.info("=== Backup merge complete ===")
    }

    // MARK: - Database Merge

    /// Opens the backup minis.db and merges all records into the live
    /// ChatStore using existing LWW (last-write-wins) merge methods.
    private func mergeMinisDatabase(from backupDBURL: URL) async throws {
        var backupDB: OpaquePointer?
        guard sqlite3_open_v2(backupDBURL.path, &backupDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let backupDB else {
            logger.error("Failed to open backup minis.db at \(backupDBURL.path)")
            throw LLMError.providerError(message: "Failed to open backup database")
        }
        defer { sqlite3_close(backupDB) }

        logger.info("Merging minis.db from backup...")

        // --- Sessions ---
        var sessionCount = 0
        var sessionStmt: OpaquePointer?
        if sqlite3_prepare_v2(backupDB,
            "SELECT id, title, model_id, created_at, updated_at, category, model_binding, memory_enabled, pinned_at, folder_id FROM sessions WHERE remote_tombstoned_at IS NULL",
            -1, &sessionStmt, nil) == SQLITE_OK {
            while sqlite3_step(sessionStmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(sessionStmt, 0))
                let title = sqlite3_column_text(sessionStmt, 1).map { String(cString: $0) }
                let modelId = sqlite3_column_text(sessionStmt, 2).map { String(cString: $0) } ?? "unknown"
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(sessionStmt, 3))
                let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(sessionStmt, 4))
                let category = sqlite3_column_text(sessionStmt, 5).map { String(cString: $0) }
                let modelBinding = sqlite3_column_text(sessionStmt, 6).map { String(cString: $0) }
                let memoryEnabled = sqlite3_column_int(sessionStmt, 7) != 0
                let pinnedAt: Date? = sqlite3_column_type(sessionStmt, 8) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(sessionStmt, 8))
                let folderId = sqlite3_column_text(sessionStmt, 9).map { String(cString: $0) }

                var session = ChatSession(
                    id: id, title: title, category: category,
                    modelId: modelId, createdAt: createdAt, updatedAt: updatedAt
                )
                session.pinnedAt = pinnedAt
                session.folderId = folderId

                await ChatStore.shared.mergeRemoteSession(
                    session, fromDeviceId: "",
                    memoryEnabled: memoryEnabled,
                    modelBinding: modelBinding,
                    remotePinnedAtRaw: pinnedAt,
                    remoteFolderId: folderId,
                    remoteHasFolderField: true
                )
                sessionCount += 1
            }
        }
        sqlite3_finalize(sessionStmt)
        logger.info("Merged \(sessionCount) sessions from backup")

        // --- Messages ---
        var messageCount = 0
        var msgStmt: OpaquePointer?
        if sqlite3_prepare_v2(backupDB,
            "SELECT id, session_id, role, parts_json, created_at, token_usage, sort_order, reasoning_content, stream_interrupt_count, updated_at FROM messages",
            -1, &msgStmt, nil) == SQLITE_OK {
            while sqlite3_step(msgStmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(msgStmt, 0))
                let sessionId = String(cString: sqlite3_column_text(msgStmt, 1))
                let role = String(cString: sqlite3_column_text(msgStmt, 2))
                let partsJson = String(cString: sqlite3_column_text(msgStmt, 3))
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(msgStmt, 4))
                let tokenUsage = sqlite3_column_text(msgStmt, 5).map { String(cString: $0) }
                let sortOrder = Int(sqlite3_column_int(msgStmt, 6))
                let reasoningContent = sqlite3_column_text(msgStmt, 7).map { String(cString: $0) }
                let streamInterruptCount = Int(sqlite3_column_int(msgStmt, 8))
                let updatedAt: Date? = sqlite3_column_type(msgStmt, 9) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(msgStmt, 9))

                await ChatStore.shared.mergeRemoteMessage(
                    id: id, sessionId: sessionId, role: role, partsJson: partsJson,
                    createdAt: createdAt, tokenUsageJson: tokenUsage, sortOrder: sortOrder,
                    reasoningContent: reasoningContent, streamInterruptCount: streamInterruptCount,
                    updatedAt: updatedAt
                )
                messageCount += 1
            }
        }
        sqlite3_finalize(msgStmt)
        logger.info("Merged \(messageCount) messages from backup")

        // --- Folders ---
        var folderCount = 0
        var folderStmt: OpaquePointer?
        if sqlite3_prepare_v2(backupDB,
            "SELECT id, name, icon, color, origin, sort_index, pinned_at, description, created_at, updated_at FROM folders",
            -1, &folderStmt, nil) == SQLITE_OK {
            while sqlite3_step(folderStmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(folderStmt, 0))
                let name = String(cString: sqlite3_column_text(folderStmt, 1))
                let icon = sqlite3_column_text(folderStmt, 2).map { String(cString: $0) }
                let color = sqlite3_column_text(folderStmt, 3).map { String(cString: $0) }
                let origin = sqlite3_column_text(folderStmt, 4).map { String(cString: $0) } ?? "manual"
                let sortIndex = Int(sqlite3_column_int(folderStmt, 5))
                let pinnedAt: Date? = sqlite3_column_type(folderStmt, 6) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(folderStmt, 6))
                let desc = sqlite3_column_text(folderStmt, 7).map { String(cString: $0) }
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(folderStmt, 8))
                let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(folderStmt, 9))

                let folder = ChatFolder(
                    id: id, name: name, icon: icon, color: color,
                    origin: origin, sortIndex: sortIndex, pinnedAt: pinnedAt,
                    desc: desc, createdAt: createdAt, updatedAt: updatedAt
                )
                await ChatStore.shared.applyRemoteFolder(folder)
                folderCount += 1
            }
        }
        sqlite3_finalize(folderStmt)
        logger.info("Merged \(folderCount) folders from backup")

        // --- Compact Markers ---
        var markerCount = 0
        var markerStmt: OpaquePointer?
        if sqlite3_prepare_v2(backupDB,
            "SELECT id, session_id, summary, first_kept_sort_order, compacted_count, created_at, ui_boundary_sort_order, boundary_message_id, first_kept_message_id, last_compacted_message_id, version FROM compact_markers",
            -1, &markerStmt, nil) == SQLITE_OK {
            while sqlite3_step(markerStmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(markerStmt, 0))
                let sessionId = String(cString: sqlite3_column_text(markerStmt, 1))
                let summary = String(cString: sqlite3_column_text(markerStmt, 2))
                let firstKeptSortOrder = Int(sqlite3_column_int(markerStmt, 3))
                let compactedCount = Int(sqlite3_column_int(markerStmt, 4))
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(markerStmt, 5))
                let uiBoundarySortOrder: Int? = sqlite3_column_type(markerStmt, 6) == SQLITE_NULL
                    ? nil
                    : Int(sqlite3_column_int(markerStmt, 6))
                let boundaryMessageId = sqlite3_column_text(markerStmt, 7).map { String(cString: $0) }
                let firstKeptMessageId = sqlite3_column_text(markerStmt, 8).map { String(cString: $0) }
                let lastCompactedMessageId = sqlite3_column_text(markerStmt, 9).map { String(cString: $0) }
                let version = Int(sqlite3_column_int(markerStmt, 10))

                let marker = CompactMarker(
                    id: id, sessionId: sessionId, summary: summary,
                    firstKeptSortOrder: firstKeptSortOrder, compactedCount: compactedCount,
                    createdAt: createdAt, uiBoundarySortOrder: uiBoundarySortOrder,
                    boundaryMessageId: boundaryMessageId,
                    firstKeptMessageId: firstKeptMessageId,
                    lastCompactedMessageId: lastCompactedMessageId,
                    version: version
                )
                await ChatStore.shared.mergeRemoteCompactMarker(marker)
                markerCount += 1
            }
        }
        sqlite3_finalize(markerStmt)
        logger.info("Merged \(markerCount) compact markers from backup")
    }

    /// Opens the backup skills.db and merges skills into the live SkillStore
    /// using importSkillFromSync (which has its own LWW guard).
    private func mergeSkillsDatabase(from backupDBURL: URL, tempDir: URL) async throws {
        var backupDB: OpaquePointer?
        guard sqlite3_open_v2(backupDBURL.path, &backupDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let backupDB else {
            logger.error("Failed to open backup skills.db at \(backupDBURL.path)")
            return
        }
        defer { sqlite3_close(backupDB) }

        struct BackupSkill {
            let id: String
            let content: String
            let importSourceStr: String
            let isEnabled: Bool
            let installedAt: Date
            let updatedAt: Date
        }

        var skills: [BackupSkill] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(backupDB,
            "SELECT id, import_source, is_enabled, installed_at, updated_at FROM skills",
            -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let importSourceStr = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "file"
                let isEnabled = sqlite3_column_int(stmt, 2) != 0
                let installedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
                let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))

                // Read SKILL.md content from the backup's skills directory
                let skillFile = tempDir
                    .appendingPathComponent("lib/MinisChat/skills/\(id)/SKILL.md")
                let content = (try? String(contentsOf: skillFile, encoding: .utf8)) ?? ""
                guard !content.isEmpty else {
                    logger.warning("Skill \(id) has no SKILL.md in backup — skipping")
                    continue
                }
                skills.append(BackupSkill(
                    id: id, content: content,
                    importSourceStr: importSourceStr,
                    isEnabled: isEnabled,
                    installedAt: installedAt,
                    updatedAt: updatedAt
                ))
            }
        }
        sqlite3_finalize(stmt)

        for skill in skills {
            let source = SkillImportSource.fromDB(skill.importSourceStr)
            await MainActor.run {
                _ = SkillStore.shared.importSkillFromSync(
                    skillId: skill.id,
                    content: skill.content,
                    source: source,
                    isEnabled: skill.isEnabled,
                    installedAt: skill.installedAt,
                    updatedAt: skill.updatedAt
                )
            }
        }
        logger.info("Merged \(skills.count) skills from backup")
    }

    // MARK: - File Asset Deduplication

    /// Copies file assets from the temp restore directory to their live
    /// locations, skipping files that already exist locally and are newer
    /// or the same age (deduplication by modification time).
    private func copyFileAssets(from tempDir: URL) throws {
        let fm = FileManager.default

        // docs/ → Documents directory
        let docsTemp = tempDir.appendingPathComponent("docs")
        if fm.fileExists(atPath: docsTemp.path) {
            try copyFilesWithDedup(from: docsTemp, to: documentsDirectory)
        }

        // lib/MinisChat/minis/ → Library/MinisChat/minis/ (file assets)
        let minisTemp = tempDir.appendingPathComponent("lib/MinisChat/minis")
        let minisLive = libraryMinisChatDirectory.appendingPathComponent("minis")
        if fm.fileExists(atPath: minisTemp.path) {
            try copyFilesWithDedup(from: minisTemp, to: minisLive)
        }
    }

    /// Recursively copies files from source to destination, skipping any
    /// file that already exists at the destination and is newer or the
    /// same age. Overwrites only when the source file is strictly newer.
    private func copyFilesWithDedup(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let basePath = source.path + "/"
        var copied = 0, skipped = 0

        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            if isDir.boolValue { continue }

            let relativePath = fileURL.path.replacingOccurrences(of: basePath, with: "")
            let destURL = destination.appendingPathComponent(relativePath)

            // Create parent directories
            let parentDir = destURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            // Dedup: skip if local exists and is >= backup mtime
            if fm.fileExists(atPath: destURL.path) {
                let localMod = try? fm.attributesOfItem(atPath: destURL.path)[.modificationDate] as? Date
                let backupMod = try? fm.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
                if let localDate = localMod, let backupDate = backupMod, localDate >= backupDate {
                    skipped += 1
                    continue
                }
                // Backup is newer — remove old file before copy
                try? fm.removeItem(at: destURL)
            }

            try fm.copyItem(at: fileURL, to: destURL)
            copied += 1
        }
        logger.info("File dedup: copied \(copied), skipped \(skipped) (local newer/same)")
    }

    /// Old-format backup extraction (backward compatibility). Extracts
    /// files directly to the documents directory, overwriting existing.
    private func extractBackupOldFormat(_ entries: [SkillStore.ZipEntry]) throws {
        let fm = FileManager.default
        let docsDir = documentsDirectory

        for entry in entries {
            let destURL = docsDir.appendingPathComponent(entry.name)
            let parentDir = destURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            try entry.data.write(to: destURL)
        }
        logger.info("Old-format extraction complete: \(entries.count) files restored")
    }

    /// Refreshes backupCount and totalBackupSize from Google Drive.
    private func refreshBackupStats(folderId: String) async throws {
        let allFiles = try await GoogleDriveAPI.listFiles(parentId: folderId)
        let backups = allFiles.filter { $0.name.hasPrefix(backupPrefix) && $0.name.hasSuffix(".zip") }
        let count = backups.count
        let totalSize = backups.reduce(0) { $0 + ($1.size ?? 0) }
        await MainActor.run {
            backupCount = count
            totalBackupSize = totalSize
        }
    }
}
