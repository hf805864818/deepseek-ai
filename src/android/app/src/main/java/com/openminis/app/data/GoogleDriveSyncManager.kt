package com.openminis.app.data

import android.content.Context
import android.util.Log
import com.openminis.app.auth.GoogleDriveOAuthManager
import com.openminis.app.util.EncryptedPrefsFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/**
 * Backup / restore manager for Google Drive sync. Coordinates between
 * [GoogleDriveAPI] (Drive operations) and the local file system
 * ([Context.filesDir]).
 *
 * Backups are stored as timestamped ZIP files under a top-level "Minis"
 * folder in the user's Google Drive. Each backup is named with the
 * prefix [BACKUP_PREFIX] followed by a sortable timestamp.
 *
 * State is exposed via [StateFlow] properties so the UI can reactively
 * observe sync progress, errors, and backup statistics.
 *
 * Settings (last sync time, auto-sync preference) are persisted via
 * [EncryptedPrefsFactory] under the "gdrive_sync_prefs" file.
 */
object GoogleDriveSyncManager {
    private const val TAG = "GoogleDriveSync"
    private const val APP_FOLDER = "Minis"
    private const val BACKUP_PREFIX = "minis-backup-"
    private const val PREFS_NAME = "gdrive_sync_prefs"
    private const val KEY_LAST_SYNC = "last_sync_time"
    private const val KEY_AUTO_SYNC = "auto_sync_enabled"
    private const val KEY_MAX_BACKUPS = "max_backups"
    private const val DEFAULT_MAX_BACKUPS = 5
    private const val SYNC_INTERVAL_MS = 4L * 60 * 60 * 1000 // 4 hours

    private lateinit var appContext: Context

    private val _isBackingUp = MutableStateFlow(false)
    val isBackingUp: StateFlow<Boolean> = _isBackingUp.asStateFlow()

    private val _isRestoring = MutableStateFlow(false)
    val isRestoring: StateFlow<Boolean> = _isRestoring.asStateFlow()

    private val _syncError = MutableStateFlow<String?>(null)
    val syncError: StateFlow<String?> = _syncError.asStateFlow()

    private val _lastSyncTime = MutableStateFlow(0L)
    val lastSyncTime: StateFlow<Long> = _lastSyncTime.asStateFlow()

    private val _backupCount = MutableStateFlow(0)
    val backupCount: StateFlow<Int> = _backupCount.asStateFlow()

    private val _totalBackupSize = MutableStateFlow(0L)
    val totalBackupSize: StateFlow<Long> = _totalBackupSize.asStateFlow()

    private val _isAutoSyncEnabled = MutableStateFlow(false)
    val isAutoSyncEnabled: StateFlow<Boolean> = _isAutoSyncEnabled.asStateFlow()

    private var autoSyncJob: Job? = null

    /**
     * Initialise the singleton with the application [Context]. Loads
     * persisted settings (last sync time, auto-sync preference) into the
     * corresponding StateFlows. Call once before any sync operation.
     */
    fun init(context: Context) {
        appContext = context.applicationContext
        val prefs = getPrefs()
        _lastSyncTime.value = prefs.getLong(KEY_LAST_SYNC, 0L)
        _isAutoSyncEnabled.value = prefs.getBoolean(KEY_AUTO_SYNC, false)
    }

    private fun getPrefs() = EncryptedPrefsFactory.safeCreate(appContext, PREFS_NAME)

    /** Clear the current error message (used by the UI after displaying it). */
    fun clearError() {
        _syncError.value = null
    }

    /**
     * Create a backup: collect all files from [Context.filesDir], pack them
     * into a ZIP, and upload to the "Minis" folder on Google Drive.
     * Updates [lastSyncTime], [backupCount], and [totalBackupSize] on success.
     */
    suspend fun backup(oauthManager: GoogleDriveOAuthManager) {
        if (_isBackingUp.value) {
            Log.w(TAG, "backup: already backing up, skipping")
            return
        }
        _isBackingUp.value = true
        _syncError.value = null
        try {
            GoogleDriveAPI.configure(oauthManager)
            val folderId = GoogleDriveAPI.findOrCreateFolder(APP_FOLDER)
            val filesDir = appContext.filesDir
            // ZIP building is CPU-heavy; run it off the main thread so the UI
            // doesn't freeze/fail during backup.
            val zipData = withContext(Dispatchers.IO) {
                createZipFromDirectory(filesDir)
            }
            val timestamp = SimpleDateFormat("yyyy-MM-dd-HHmmss", Locale.US).format(Date())
            val backupName = "$BACKUP_PREFIX$timestamp.zip"
            GoogleDriveAPI.uploadFile(backupName, zipData, folderId, "application/zip")

            val now = System.currentTimeMillis()
            _lastSyncTime.value = now
            getPrefs().edit().putLong(KEY_LAST_SYNC, now).apply()

            // Clean up old backups beyond maxBackups limit
            cleanupOldBackups(folderId)

            // Refresh backup statistics
            val files = GoogleDriveAPI.listFiles(folderId)
                .filter { it.name.startsWith(BACKUP_PREFIX) }
            _backupCount.value = files.size
            _totalBackupSize.value = files.sumOf { it.size ?: 0L }

            Log.i(TAG, "Backup completed: $backupName (${zipData.size} bytes)")
        } catch (e: Exception) {
            Log.e(TAG, "Backup failed", e)
            _syncError.value = e.message ?: "Backup failed"
        } finally {
            _isBackingUp.value = false
        }
    }

    /**
     * Restore from the latest backup. Finds the most recent backup file
     * and delegates to [restoreFrom].
     */
    suspend fun restore(oauthManager: GoogleDriveOAuthManager) {
        val backups = listBackups(oauthManager)
        val latest = backups.firstOrNull()
        if (latest == null) {
            _syncError.value = "No backups found"
            return
        }
        restoreFrom(oauthManager, latest.id)
    }

    /**
     * Restore from a specific backup file. Downloads the ZIP and extracts
     * its contents to [Context.filesDir].
     */
    suspend fun restoreFrom(oauthManager: GoogleDriveOAuthManager, fileId: String) {
        if (_isRestoring.value) {
            Log.w(TAG, "restoreFrom: already restoring, skipping")
            return
        }
        _isRestoring.value = true
        _syncError.value = null
        try {
            GoogleDriveAPI.configure(oauthManager)
            val zipData = GoogleDriveAPI.downloadFile(fileId)
            // Extraction is CPU-heavy; run it off the main thread so the UI
            // doesn't freeze/fail during restore.
            withContext(Dispatchers.IO) {
                extractZipToDirectory(zipData, appContext.filesDir)
            }
            Log.i(TAG, "Restore completed from file: $fileId (${zipData.size} bytes)")
        } catch (e: Exception) {
            Log.e(TAG, "Restore failed", e)
            _syncError.value = e.message ?: "Restore failed"
        } finally {
            _isRestoring.value = false
        }
    }

    /**
     * List all backup files in the "Minis" folder, sorted by modification
     * time (newest first). Also updates [backupCount] and [totalBackupSize].
     */
    suspend fun listBackups(oauthManager: GoogleDriveOAuthManager): List<GoogleDriveFile> {
        return withContext(Dispatchers.IO) {
            try {
                GoogleDriveAPI.configure(oauthManager)
                val folderId = GoogleDriveAPI.findOrCreateFolder(APP_FOLDER)
                val files = GoogleDriveAPI.listFiles(folderId)
                    .filter { it.name.startsWith(BACKUP_PREFIX) }
                    .sortedByDescending { it.modifiedTime ?: "" }
                _backupCount.value = files.size
                _totalBackupSize.value = files.sumOf { it.size ?: 0L }
                files
            } catch (e: Exception) {
                Log.e(TAG, "listBackups failed", e)
                _syncError.value = e.message ?: "Failed to list backups"
                emptyList()
            }
        }
    }

    /**
     * Delete a specific backup file by ID. Refreshes backup statistics
     * after deletion.
     */
    suspend fun deleteBackup(oauthManager: GoogleDriveOAuthManager, fileId: String) {
        withContext(Dispatchers.IO) {
            try {
                GoogleDriveAPI.configure(oauthManager)
                GoogleDriveAPI.deleteFile(fileId)

                // Refresh backup statistics
                val folderId = GoogleDriveAPI.findOrCreateFolder(APP_FOLDER)
                val files = GoogleDriveAPI.listFiles(folderId)
                    .filter { it.name.startsWith(BACKUP_PREFIX) }
                _backupCount.value = files.size
                _totalBackupSize.value = files.sumOf { it.size ?: 0L }

                Log.i(TAG, "Backup deleted: $fileId")
            } catch (e: Exception) {
                Log.e(TAG, "deleteBackup failed", e)
                _syncError.value = e.message ?: "Failed to delete backup"
            }
        }
    }

    /**
     * Removes oldest backups that exceed the maxBackups limit.
     * Called automatically after each successful backup. Errors are
     * logged but never block the backup itself.
     */
    private suspend fun cleanupOldBackups(folderId: String) {
        try {
            val allBackups = GoogleDriveAPI.listFiles(folderId)
                .filter { it.name.startsWith(BACKUP_PREFIX) && it.name.endsWith(".zip") }
                .sortedByDescending { it.modifiedTime ?: 0L }

            val limit = maxOf(getMaxBackups(), 1)
            if (allBackups.size <= limit) {
                Log.i(TAG, "Cleanup: ${allBackups.size} backups, limit is $limit — nothing to delete")
                return
            }

            val toDelete = allBackups.drop(limit)
            Log.i(TAG, "Cleanup: deleting ${toDelete.size} old backup(s) to stay within limit of $limit")

            for (backup in toDelete) {
                try {
                    GoogleDriveAPI.deleteFile(backup.id)
                    Log.i(TAG, "Deleted old backup: ${backup.name}")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to delete old backup ${backup.name}: ${e.message}")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "cleanupOldBackups failed (non-fatal): ${e.message}")
        }
    }

    /** Reads the maxBackups setting from prefs, default 5. */
    fun getMaxBackups(): Int {
        return getPrefs().getInt(KEY_MAX_BACKUPS, DEFAULT_MAX_BACKUPS)
    }

    /** Sets the maxBackups setting. Takes effect on next backup. */
    fun setMaxBackups(value: Int) {
        getPrefs().edit().putInt(KEY_MAX_BACKUPS, maxOf(value, 1)).apply()
    }

    /**
     * Start periodic auto-sync. Backs up immediately, then repeats every
     * 4 hours. The running [Job] is stored so [stopAutoSync] can cancel it.
     */
    suspend fun startAutoSync(oauthManager: GoogleDriveOAuthManager) {
        _isAutoSyncEnabled.value = true
        getPrefs().edit().putBoolean(KEY_AUTO_SYNC, true).apply()
        autoSyncJob?.cancel()
        autoSyncJob = CoroutineScope(Dispatchers.IO).launch {
            while (isActive) {
                backup(oauthManager)
                delay(SYNC_INTERVAL_MS)
            }
        }
        Log.i(TAG, "Auto-sync started (interval: ${SYNC_INTERVAL_MS}ms)")
    }

    /**
     * Stop the periodic auto-sync job and clear the preference.
     */
    fun stopAutoSync() {
        autoSyncJob?.cancel()
        autoSyncJob = null
        _isAutoSyncEnabled.value = false
        getPrefs().edit().putBoolean(KEY_AUTO_SYNC, false).apply()
        Log.i(TAG, "Auto-sync stopped")
    }

    // ── ZIP helpers ──

    /**
     * Recursively collect all files under [directory] and write them into
     * a ZIP archive. Entry paths are relative to [directory].
     */
    private fun createZipFromDirectory(directory: File): ByteArray {
        val baos = ByteArrayOutputStream()
        ZipOutputStream(baos).use { zos ->
            collectFiles(directory, directory, zos)
        }
        return baos.toByteArray()
    }

    private fun collectFiles(root: File, current: File, zos: ZipOutputStream) {
        val children = current.listFiles() ?: return
        for (child in children) {
            if (child.isDirectory) {
                collectFiles(root, child, zos)
            } else {
                val relativePath = child.absolutePath
                    .substring(root.absolutePath.length + 1)
                val entry = ZipEntry(relativePath)
                zos.putNextEntry(entry)
                child.inputStream().use { it.copyTo(zos) }
                zos.closeEntry()
            }
        }
    }

    /**
     * Extract a ZIP byte array into [targetDir]. Path traversal entries
     * (paths that escape [targetDir]) are skipped for safety.
     */
    private fun extractZipToDirectory(zipData: ByteArray, targetDir: File) {
        targetDir.mkdirs()
        val targetCanonical = targetDir.canonicalPath
        ZipInputStream(zipData.inputStream()).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                val outFile = File(targetDir, entry.name)
                if (!outFile.canonicalPath.startsWith(targetCanonical)) {
                    Log.w(TAG, "Skipping path traversal entry: ${entry.name}")
                    zis.closeEntry()
                    entry = zis.nextEntry
                    continue
                }
                if (entry.isDirectory) {
                    outFile.mkdirs()
                } else {
                    outFile.parentFile?.mkdirs()
                    FileOutputStream(outFile).use { zis.copyTo(it) }
                }
                zis.closeEntry()
                entry = zis.nextEntry
            }
        }
    }

    // ── Formatting helpers (used by the UI) ──

    /** Format a byte count into a human-readable string (B / KB / MB / GB). */
    fun formatSize(bytes: Long): String {
        return when {
            bytes < 1024 -> "$bytes B"
            bytes < 1024 * 1024 -> String.format(Locale.US, "%.1f KB", bytes / 1024.0)
            bytes < 1024 * 1024 * 1024 ->
                String.format(Locale.US, "%.1f MB", bytes / (1024.0 * 1024))
            else ->
                String.format(Locale.US, "%.1f GB", bytes / (1024.0 * 1024 * 1024))
        }
    }

    /** Format a millisecond timestamp into a readable date string. */
    fun formatDate(timestamp: Long): String {
        if (timestamp == 0L) return "Never"
        val sdf = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        return sdf.format(Date(timestamp))
    }
}
