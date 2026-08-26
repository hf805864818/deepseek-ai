import Foundation
import SwiftUI
import os.log

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
    /// Heavy work (file collection, ZIP building) runs on the calling
    /// cooperative thread; only UI state updates hop to the main actor.
    func backup() async throws {
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

        // Use do-catch instead of defer+Task so the flag is reset
        // synchronously in both success and error paths. The old
        // `Task { @MainActor in isBackingUp = false }` in defer was
        // fire-and-forget — the async Task might not run for seconds,
        // leaving "正在备份..." spinning even after the backup finished.
        do {
            try await backupInternal()
        } catch {
            await MainActor.run {
                isBackingUp = false
                syncError = error.localizedDescription
            }
            throw error
        }
        // Reset on success path
        await MainActor.run {
            isBackingUp = false
        }
    }

    private func backupInternal() async throws {
        logger.info("=== Google Drive backup started ===")

        // 1. Collect all files from documents directory (I/O — runs on background)
        let docsDir = documentsDirectory
        let files = collectFiles(in: docsDir)
        logger.info("Collected \(files.count) files from documents directory")

        if files.isEmpty {
            throw LLMError.providerError(message: "No files found to back up")
        }

        // 2. Create ZIP archive (CPU + memory heavy — runs on background)
        let zipData = SkillStore.buildZipArchive(files: files)
        let fileSize = zipData.count
        logger.info("ZIP archive built: \(fileSize) bytes")

        // 3. Ensure app folder exists in Drive
        let folderId = try await ensureAppFolder()
        logger.info("App folder ID: \(folderId)")

        // 4. Upload backup file
        let timestamp = Self.backupDateFormatter.string(from: Date())
        let fileName = "\(backupPrefix)\(timestamp).zip"
        let mimeType = "application/zip"

        let fileId: String
        if fileSize > 5 * 1024 * 1024 {
            // Large file — use resumable upload
            logger.info("Using resumable upload for \(fileSize) bytes")
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
            logger.info("Using multipart upload for \(fileSize) bytes")
            fileId = try await GoogleDriveAPI.uploadFile(
                name: fileName,
                data: zipData,
                parentId: folderId,
                mimeType: mimeType
            )
        }

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

        // 3. Extract and restore (I/O heavy — runs on background)
        try extractBackup(zipData)

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

        // 2. Extract and restore (I/O heavy — runs on background)
        try extractBackup(zipData)

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
                do {
                    try await self.backup()
                } catch {
                    logger.error("Auto-sync backup failed: \(error.localizedDescription)")
                    await MainActor.run {
                        self.syncError = error.localizedDescription
                    }
                }
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

    /// Walks the documents directory and collects all files with their
    /// relative paths and data.
    private func collectFiles(in directory: URL) -> [(relativePath: String, data: Data)] {
        var files: [(relativePath: String, data: Data)] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.error("Failed to enumerate documents directory")
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

            let relativePath = fileURL.path.replacingOccurrences(of: basePath, with: "")
            if let data = try? Data(contentsOf: fileURL) {
                files.append((relativePath: relativePath, data: data))
            } else {
                logger.warning("Failed to read file: \(relativePath)")
            }
        }

        return files
    }

    /// Extracts a ZIP archive and restores files to the documents directory.
    /// Overwrites existing files; creates subdirectories as needed.
    private func extractBackup(_ zipData: Data) throws {
        let entries: [SkillStore.ZipEntry]
        do {
            entries = try SkillStore.readZipEntries(data: zipData)
        } catch {
            logger.error("Failed to read ZIP entries: \(error.localizedDescription)")
            throw LLMError.providerError(message: "Failed to read backup archive: \(error.localizedDescription)")
        }

        logger.info("Extracting \(entries.count) entries from backup")

        let fm = FileManager.default
        let docsDir = documentsDirectory

        for entry in entries {
            if entry.isDirectory { continue }

            let destURL = docsDir.appendingPathComponent(entry.name)

            // Create parent directories if needed
            let parentDir = destURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            // Write file (overwrite if exists)
            try entry.data.write(to: destURL)
        }

        logger.info("Extraction complete: \(entries.filter { !$0.isDirectory }.count) files restored")
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
