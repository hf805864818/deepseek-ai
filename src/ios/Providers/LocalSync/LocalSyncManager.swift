import Foundation
import SwiftUI
import os.log

private let logger = AppLogger(category: "LocalSync")

// MARK: - Backup Phase

/// Progress phases for the capsule toast shown during backup.
/// The View observes `LocalSyncManager.backupPhase` and displays a
/// matching message + spinner/checkmark in a capsule overlay.
enum BackupPhase: Equatable {
    case idle
    case collecting
    case packaging
    case saving
    case done
    case error
}

// MARK: - Local Backup

/// A single backup file living in the user-selected local directory.
struct LocalBackup: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let size: Int64
    let modifiedDate: Date
}

// MARK: - Sync Manager

/// Backup and restore sync manager for a user-selected local directory.
///
/// Creates the same ZIP archives as `GoogleDriveSyncManager` (app documents
/// directory + `Library/MinisChat` databases/assets + settings snapshot) but
/// writes the resulting ZIP to a folder the user picks via the document
/// picker. Persistent access across app launches is kept through a
/// security-scoped bookmark stored in `UserDefaults`.
///
/// The merge/restore path reuses the provider-agnostic
/// `GoogleDriveSyncManager.mergeBackup(_:)` so the local backup stays
/// byte-compatible with the Google Drive backup and restores identically
/// (LWW conflict resolution for SQLite + dedup for file assets).
///
/// Like `GoogleDriveSyncManager`, this class is NOT `@MainActor`. Heavy I/O
/// (file collection, ZIP building, bookmark resolution) runs on the calling
/// cooperative thread. Only `@Published` properties are isolated to the main
/// actor via `MainActor.run {}`.
final class LocalSyncManager: ObservableObject {

    static let shared = LocalSyncManager()

    // MARK: - Configuration

    /// Backup file name prefix (must match GoogleDriveSyncManager).
    private let backupPrefix = "minis-backup-"
    /// Auto-sync interval (4 hours, same as Google Drive).
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
    @MainActor @Published private(set) var destinationName: String?
    /// Current backup progress phase, observed by the View to show a
    /// capsule toast. Reset to `.idle` by the View after the toast
    /// for `.done` / `.error` auto-dismisses.
    @MainActor @Published private(set) var backupPhase: BackupPhase = .idle

    // MARK: - AppStorage (persistent settings)

    @AppStorage("localSync.autoSync.enabled") var isAutoSyncEnabled: Bool = false
    @AppStorage("localSync.lastSync") private var lastSyncTimestamp: Double = 0

    /// Maximum number of backup files to keep in the local directory.
    @AppStorage("localSync.maxBackups") var maxBackups: Int = 5

    /// UserDefaults key holding the security-scoped bookmark Data for the
    /// chosen directory. (Stored as Data, so it cannot use @AppStorage.)
    private let bookmarkKey = "localSync.folderBookmark"

    // MARK: - Computed Properties

    var lastSyncDate: Date? {
        lastSyncTimestamp > 0 ? Date(timeIntervalSince1970: lastSyncTimestamp) : nil
    }

    /// True when a destination directory has been bookmarked and the
    /// bookmark is still valid (not stale / revocable).
    var hasDestination: Bool { folderURL != nil }

    /// Resolves the stored security-scoped bookmark into a URL.
    /// Returns nil (and clears the bookmark) when it is missing, stale,
    /// or unresolvable — in which case the UI should re-prompt the user
    /// to pick a folder.
    var folderURL: URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                // The user may have moved/renamed the folder or revoked
                // access — discard the stale bookmark so the UI re-prompts.
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                return nil
            }
            return url
        } catch {
            logger.error("Failed to resolve folder bookmark: \(error.localizedDescription)")
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return nil
        }
    }

    // MARK: - Private

    private var autoSyncTask: Task<Void, Never>?

    private init() {
        if isAutoSyncEnabled {
            startAutoSync()
        }
    }

    // MARK: - Destination Management

    /// Stores a security-scoped bookmark for the user-picked directory.
    /// Called from the document picker callback.
    func saveDestination(_ url: URL) {
        // The URL from UIDocumentPickerViewController is security-scoped.
        // We must start accessing it before creating a bookmark, otherwise
        // the bookmark will not capture the security scope and later
        // startAccessingSecurityScopedResource() will fail.
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Failed to start accessing security-scoped resource for \(url.lastPathComponent)")
            Task { @MainActor in
                syncError = "无法访问所选文件夹，请重新选择。"
            }
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            Task { @MainActor in
                destinationName = url.lastPathComponent
                // Refresh stats for the newly-selected folder.
                try? await refreshBackupStats()
            }
            logger.info("Saved destination bookmark: \(url.lastPathComponent)")
        } catch {
            logger.error("Failed to create folder bookmark: \(error.localizedDescription)")
            Task { @MainActor in
                syncError = error.localizedDescription
            }
        }
    }

    /// Clears the bookmarked destination (user tapped "Clear").
    func clearDestination() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        Task { @MainActor in
            destinationName = nil
            backupCount = 0
            totalBackupSize = 0
        }
        logger.info("Cleared destination bookmark")
    }

    /// Resets `backupPhase` back to `.idle`. Called by the View after
    /// the capsule toast for `.done` or `.error` has been shown.
    @MainActor func resetPhase() {
        backupPhase = .idle
    }

    // MARK: - Backup

    /// Builds a ZIP archive of the app's data and writes it to the
    /// user-selected local directory. Fire-and-forget like
    /// `GoogleDriveSyncManager.backup()` so the MainActor / UI thread is
    /// never blocked. The caller does NOT need to catch errors — all
    /// errors are handled internally by setting `syncError` and resetting
    /// `isBackingUp`. The View should refresh its backup list by
    /// observing `isBackingUp` falling back to false.
    func backup() async {
        let alreadyBackingUp = await MainActor.run { isBackingUp }
        guard !alreadyBackingUp else {
            logger.warning("Backup already in progress — skipping")
            return
        }
        guard hasDestination else {
            await MainActor.run {
                syncError = NSLocalizedString("No backup folder selected. Tap \"Choose Folder\" first.",
                                              comment: "Local sync: no destination error")
            }
            return
        }

        await MainActor.run {
            isBackingUp = true
            syncError = nil
            backupPhase = .collecting
        }

        // Use fire-and-forget Task to avoid blocking MainActor.
        Task {
            do {
                try await self.backupInternal()
            } catch {
                logger.error("Backup failed: \(error.localizedDescription)")
                await MainActor.run {
                    isBackingUp = false
                    syncError = error.localizedDescription
                    backupPhase = .error
                }
                return
            }
            await MainActor.run {
                isBackingUp = false
                // backupPhase is .done (set by backupInternal).
                // The View resets it after the capsule auto-dismisses.
            }
        }
    }

    private func backupInternal() async throws {
        logger.info("=== Local backup started ===")

        // 1. Collect files from documents directory AND Library/MinisChat.
        //    This mirrors GoogleDriveSyncManager exactly so the backup is
        //    byte-compatible and restores identically.
        await MainActor.run { backupPhase = .collecting }
        let docsDir = documentsDirectory
        let libDir = libraryMinisChatDirectory
        var files = collectFiles(in: docsDir, prefix: "docs/")
        files.append(contentsOf: collectFiles(in: libDir, prefix: "lib/MinisChat/"))

        // 1c. Include app settings snapshot (independent of iCloud sync).
        if let settingsData = await MainActor.run(body: { AppSettingsSync.buildBackupPayload() }) {
            files.append((relativePath: "settings/settings.json", data: settingsData))
        }

        guard !files.isEmpty else {
            throw LLMError.providerError(message: "No files found to back up")
        }

        let totalRawSize = files.reduce(0) { $0 + $1.data.count }
        logger.info("Step 2: building ZIP archive (\(files.count) files, \(totalRawSize) bytes raw)...")

        // 2. Create ZIP archive.
        await MainActor.run { backupPhase = .packaging }
        let zipData = SkillStore.buildZipArchive(files: files)
        logger.info("Step 2: ZIP built: \(zipData.count) bytes")

        let timestamp = Self.backupDateFormatter.string(from: Date())
        let fileName = "\(backupPrefix)\(timestamp).zip"

        // 3. Write backup file to the user-selected folder (security-scoped).
        await MainActor.run { backupPhase = .saving }
        try await withFolderAccess { url in
            let destURL = url.appendingPathComponent(fileName)
            try zipData.write(to: destURL, options: .atomic)
            logger.info("Step 3: wrote backup to \(destURL.path)")
        }

        // 4. Done — set phase so the capsule shows success.
        await MainActor.run { backupPhase = .done }
        lastSyncTimestamp = Date().timeIntervalSince1970
        await MainActor.run { syncError = nil }
        logger.info("=== Local backup complete: \(fileName) ===")

        // 5. Clean up old backups beyond the limit.
        try? await cleanupOldBackups()

        // 6. Refresh backup stats.
        try? await refreshBackupStats()
    }

    // MARK: - Restore

    /// Restores the latest backup from the local directory.
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
        logger.info("=== Local restore started ===")

        // 1. List backups to find the latest.
        let backups = try await listBackups()
        guard let latest = backups.first else {
            throw LLMError.providerError(message: "No local backups found in the selected folder")
        }
        logger.info("Latest backup: \(latest.name) (modified: \(latest.modifiedDate))")

        // 2. Read the backup file (security-scoped).
        let zipData: Data = try await withFolderAccess { _ in
            try Data(contentsOf: latest.url)
        }
        logger.info("Backup read: \(zipData.count) bytes")

        // 3. Merge backup into local storage (LWW conflict resolution).
        //    Reuse the provider-agnostic merge logic so the restore result
        //    is identical to restoring from Google Drive.
        try await GoogleDriveSyncManager.shared.mergeBackup(zipData)

        logger.info("=== Local restore complete ===")
    }

    /// Restores from a specific local backup file by its URL.
    func restoreFrom(url: URL) async throws {
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
            try await restoreFromInternal(url: url)
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

    private func restoreFromInternal(url: URL) async throws {
        logger.info("=== Local restore from \(url.lastPathComponent) started ===")

        // Read the backup file (security-scoped access to the folder).
        let zipData: Data = try await withFolderAccess { _ in
            try Data(contentsOf: url)
        }
        logger.info("Backup read: \(zipData.count) bytes")

        // Merge backup into local storage (LWW conflict resolution).
        try await GoogleDriveSyncManager.shared.mergeBackup(zipData)

        logger.info("=== Local restore complete ===")
    }

    // MARK: - Backup Listing

    /// Lists all backup files in the user-selected directory, sorted by
    /// modification time (newest first). Also updates `backupCount` and
    /// `totalBackupSize`.
    func listBackups() async throws -> [LocalBackup] {
        try await withFolderAccess { url in
            let fm = FileManager.default
            let contents = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let backups = contents.compactMap { fileURL -> LocalBackup? in
                let name = fileURL.lastPathComponent
                guard name.hasPrefix(self.backupPrefix) && name.hasSuffix(".zip") else { return nil }
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = Int64(values?.fileSize ?? 0)
                let mod = values?.contentModificationDate ?? .distantPast
                return LocalBackup(url: fileURL, name: name, size: size, modifiedDate: mod)
            }.sorted { $0.modifiedDate > $1.modifiedDate }

            let count = backups.count
            let totalSize = backups.reduce(Int64(0)) { $0 + $1.size }

            await MainActor.run {
                self.backupCount = count
                self.totalBackupSize = totalSize
            }

            logger.info("Found \(count) local backups totaling \(totalSize) bytes")
            return backups
        }
    }

    /// Deletes a specific backup file from the local directory.
    func deleteBackup(at url: URL) async throws {
        logger.info("Deleting local backup: \(url.lastPathComponent)")
        try await withFolderAccess { _ in
            try FileManager.default.removeItem(at: url)
        }
        try? await refreshBackupStats()
    }

    /// Removes oldest backups that exceed the `maxBackups` limit.
    private func cleanupOldBackups() async throws {
        try await withFolderAccess { url in
            let fm = FileManager.default
            let contents = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let backups = contents
                .filter { $0.lastPathComponent.hasPrefix(self.backupPrefix) && $0.lastPathComponent.hasSuffix(".zip") }
                .sorted { a, b in
                    let aMod = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let bMod = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return aMod > bMod
                }

            let limit = max(self.maxBackups, 1)
            guard backups.count > limit else { return }

            let toDelete = Array(backups.dropFirst(limit))
            logger.info("Cleanup: deleting \(toDelete.count) old backup(s) to stay within limit of \(limit)")
            for backup in toDelete {
                do {
                    try fm.removeItem(at: backup)
                    logger.info("Deleted old backup: \(backup.lastPathComponent)")
                } catch {
                    logger.warning("Failed to delete old backup \(backup.lastPathComponent): \(error.localizedDescription)")
                }
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

    /// Resolves the bookmarked folder, opens a security-scoped resource on
    /// it, runs `body` with access, and always releases the scope.
    private func withFolderAccess<T>(
        _ body: (URL) async throws -> T
    ) async throws -> T {
        guard let url = folderURL else {
            throw LLMError.providerError(message: "No backup folder selected")
        }
        guard url.startAccessingSecurityScopedResource() else {
            throw LLMError.providerError(message: "Unable to access the selected folder. Please re-select it in settings.")
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try await body(url)
    }

    /// Walks a directory and collects all files with their relative paths
    /// and data. The optional prefix is prepended to each relative path so
    /// multiple source directories can be distinguished in the ZIP.
    /// Mirrors `GoogleDriveSyncManager.collectFiles` exactly so the local
    /// backup is byte-compatible with the Google Drive backup.
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

            // Skip backup files if they somehow end up in the source dirs.
            let name = fileURL.lastPathComponent
            if name.hasPrefix(backupPrefix) && name.hasSuffix(".zip") { continue }

            // Skip SQLite WAL/SHM temp files — they are transient and
            // including them can corrupt the DB on restore.
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

    /// Refreshes `backupCount` and `totalBackupSize` from the local folder.
    private func refreshBackupStats() async throws {
        try await withFolderAccess { url in
            let fm = FileManager.default
            let contents = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let backups = contents.filter {
                $0.lastPathComponent.hasPrefix(self.backupPrefix) && $0.lastPathComponent.hasSuffix(".zip")
            }
            let count = backups.count
            let totalSize = backups.reduce(Int64(0)) { acc, fileURL in
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return acc + Int64(size)
            }

            await MainActor.run {
                self.backupCount = count
                self.totalBackupSize = totalSize
            }
        }
    }
}
