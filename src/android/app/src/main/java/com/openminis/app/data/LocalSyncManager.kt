package com.openminis.app.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.documentfile.provider.DocumentFile
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
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Backup / restore manager for local directory sync. Uses Android's
 * Storage Access Framework (SAF) to let the user pick a directory in
 * any file provider (internal storage, SD card, USB OTG, etc.).
 * Persistent access is kept via [ContentResolver.takePersistableUriPermission].
 *
 * Backups are stored as timestamped ZIP files in the user-selected
 * directory. The ZIP format is byte-compatible with Google Drive sync
 * (files/ prefix, db/ prefix, settings/settings.json) so restores are
 * identical regardless of which sync platform created the backup.
 *
 * State is exposed via [StateFlow] so the UI can reactively observe
 * progress via [backupPhase].
 */
object LocalSyncManager {
    private const val TAG = "LocalSync"
    private const val PREFS_NAME = "local_sync_prefs"
    private const val KEY_FOLDER_URI = "folder_uri"
    private const val KEY_FOLDER_NAME = "folder_name"
    private const val KEY_LAST_SYNC = "last_sync_time"
    private const val KEY_AUTO_SYNC = "auto_sync_enabled"
    private const val KEY_MAX_BACKUPS = "max_backups"
    private const val DEFAULT_MAX_BACKUPS = 10
    private const val BACKUP_PREFIX = "minis-backup-"
    private const val SYNC_INTERVAL_MS = 4L * 60 * 60 * 1000 // 4 hours

    private lateinit var appContext: Context

    // ── Reactive State ──

    private val _isBackingUp = MutableStateFlow(false)
    val isBackingUp: StateFlow<Boolean> = _isBackingUp.asStateFlow()

    private val _isRestoring = MutableStateFlow(false)
    val isRestoring: StateFlow<Boolean> = _isRestoring.asStateFlow()

    private val _syncError = MutableStateFlow<String?>(null)
    val syncError: StateFlow<String?> = _syncError.asStateFlow()

    private val _backupPhase = MutableStateFlow(BackupPhase.IDLE)
    val backupPhase: StateFlow<BackupPhase> = _backupPhase.asStateFlow()

    private val _lastSyncTime = MutableStateFlow(0L)
    val lastSyncTime: StateFlow<Long> = _lastSyncTime.asStateFlow()

    private val _backupCount = MutableStateFlow(0)
    val backupCount: StateFlow<Int> = _backupCount.asStateFlow()

    private val _totalBackupSize = MutableStateFlow(0L)
    val totalBackupSize: StateFlow<Long> = _totalBackupSize.asStateFlow()

    private val _isAutoSyncEnabled = MutableStateFlow(false)
    val isAutoSyncEnabled: StateFlow<Boolean> = _isAutoSyncEnabled.asStateFlow()

    private val _hasDestination = MutableStateFlow(false)
    val hasDestination: StateFlow<Boolean> = _hasDestination.asStateFlow()

    private val _destinationName = MutableStateFlow<String?>(null)
    val destinationName: StateFlow<String?> = _destinationName.asStateFlow()

    private var autoSyncJob: Job? = null

    // ── Init ──

    fun init(context: Context) {
        if (::appContext.isInitialized) return
        appContext = context.applicationContext
        // Ensure GoogleDriveSyncManager is also initialized so we can
        // reuse its createBackupZip/mergeBackup methods.
        GoogleDriveSyncManager.init(context.applicationContext)
        loadSettings()
        refreshStats()
    }

    private fun prefs() = EncryptedPrefsFactory.safeCreate(appContext, PREFS_NAME)

    private fun loadSettings() {
        val p = prefs()
        _lastSyncTime.value = p.getLong(KEY_LAST_SYNC, 0L)
        _isAutoSyncEnabled.value = p.getBoolean(KEY_AUTO_SYNC, false)
        val folderName = p.getString(KEY_FOLDER_NAME, null)
        val folderUri = p.getString(KEY_FOLDER_URI, null)
        _hasDestination.value = folderUri != null && isPersistableUriAvailable(folderUri)
        _destinationName.value = if (_hasDestination.value) folderName else null
    }

    private fun isPersistableUriAvailable(uriString: String): Boolean {
        return try {
            val uri = Uri.parse(uriString)
            val perms = appContext.contentResolver.persistedUriPermissions
            perms.any { it.uri == uri }
        } catch (e: Exception) {
            false
        }
    }

    // ── Folder Selection (SAF) ──

    /**
     * Stores the SAF tree URI and takes persistable permission so we
     * can read/write to the folder across app restarts.
     */
    fun saveDestination(treeUri: Uri) {
        // Take persistable read/write permission
        appContext.contentResolver.takePersistableUriPermission(
            treeUri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
        val folderName = DocumentFile.fromTreeUri(appContext, treeUri)?.name ?: "Folder"
        prefs().edit()
            .putString(KEY_FOLDER_URI, treeUri.toString())
            .putString(KEY_FOLDER_NAME, folderName)
            .apply()
        _hasDestination.value = true
        _destinationName.value = folderName
        Log.i(TAG, "Saved destination: $folderName ($treeUri)")
        refreshStats()
    }

    fun clearDestination() {
        val uriString = prefs().getString(KEY_FOLDER_URI, null) ?: return
        try {
            val uri = Uri.parse(uriString)
            appContext.contentResolver.releasePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to release URI permission: ${e.message}")
        }
        prefs().edit()
            .remove(KEY_FOLDER_URI)
            .remove(KEY_FOLDER_NAME)
            .apply()
        _hasDestination.value = false
        _destinationName.value = null
        _backupCount.value = 0
        _totalBackupSize.value = 0
        stopAutoSync()
        Log.i(TAG, "Cleared destination")
    }

    private fun getFolderUri(): Uri? {
        val uriString = prefs().getString(KEY_FOLDER_URI, null) ?: return null
        return Uri.parse(uriString)
    }

    private fun getFolderDoc(): DocumentFile? {
        val uri = getFolderUri() ?: return null
        return DocumentFile.fromTreeUri(appContext, uri)
    }

    // ── Backup ──

    suspend fun backup() {
        if (_isBackingUp.value) {
            Log.w(TAG, "backup: already backing up, skipping")
            return
        }
        if (!_hasDestination.value) {
            _syncError.value = "No backup folder selected"
            return
        }

        _isBackingUp.value = true
        _syncError.value = null
        _backupPhase.value = BackupPhase.COLLECTING

        try {
            backupInternal()
        } catch (e: Exception) {
            Log.e(TAG, "Backup failed: ${e.message}", e)
            _syncError.value = e.message ?: "Backup failed"
            _backupPhase.value = BackupPhase.ERROR
        } finally {
            _isBackingUp.value = false
        }
    }

    private suspend fun backupInternal() = withContext(Dispatchers.IO) {
        Log.i(TAG, "=== Local backup started ===")

        // 1. Collect data + create ZIP (reuse GoogleDriveSyncManager logic)
        _backupPhase.value = BackupPhase.COLLECTING
        val filesDir = appContext.filesDir
        val dbDir = appContext.getDatabasePath("dummy").parentFile
            ?: File(appContext.filesDir.parent, "databases")

        // Refresh settings snapshot
        GoogleDriveSyncManager.snapshotSettings()

        // 2. Create ZIP archive
        _backupPhase.value = BackupPhase.PACKAGING
        val zipData = GoogleDriveSyncManager.createBackupZip(filesDir, dbDir)
        Log.i(TAG, "ZIP created: ${zipData.size} bytes")

        val timestamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date())
        val fileName = "$BACKUP_PREFIX$timestamp.zip"

        // 3. Write to SAF folder
        _backupPhase.value = BackupPhase.SAVING
        val folder = getFolderDoc()
            ?: throw IllegalStateException("Cannot access backup folder")
        val backupFile = folder.createFile("application/zip", fileName)
            ?: throw IllegalStateException("Failed to create backup file")
        appContext.contentResolver.openOutputStream(backupFile.uri)?.use { out ->
            out.write(zipData)
        } ?: throw IllegalStateException("Failed to open output stream for backup")

        Log.i(TAG, "Backup written: $fileName")

        // 4. Done
        _backupPhase.value = BackupPhase.DONE
        _lastSyncTime.value = System.currentTimeMillis()
        prefs().edit().putLong(KEY_LAST_SYNC, _lastSyncTime.value).apply()

        // 5. Clean up old backups
        cleanupOldBackups()

        // 6. Refresh stats
        refreshStats()

        Log.i(TAG, "=== Local backup complete ===")
    }

    // ── Restore ──

    suspend fun restore() {
        if (_isRestoring.value) {
            Log.w(TAG, "restore: already restoring, skipping")
            return
        }
        _isRestoring.value = true
        _syncError.value = null
        try {
            restoreInternal()
        } catch (e: Exception) {
            Log.e(TAG, "Restore failed: ${e.message}", e)
            _syncError.value = e.message ?: "Restore failed"
        } finally {
            _isRestoring.value = false
        }
    }

    private suspend fun restoreInternal() = withContext(Dispatchers.IO) {
        Log.i(TAG, "=== Local restore started ===")

        val backups = listBackups()
        if (backups.isEmpty()) {
            throw IllegalStateException("No local backups found")
        }
        val latest = backups.first()
        Log.i(TAG, "Restoring: ${latest.name}")

        val zipData = appContext.contentResolver.openInputStream(latest.uri)?.use { it.readBytes() }
            ?: throw IllegalStateException("Failed to read backup file")

        // Merge backup (LWW) — reuse GoogleDriveSyncManager logic
        GoogleDriveSyncManager.mergeBackup(zipData)

        Log.i(TAG, "=== Local restore complete ===")
    }

    suspend fun restoreFrom(uri: Uri) {
        if (_isRestoring.value) {
            Log.w(TAG, "restore: already restoring, skipping")
            return
        }
        _isRestoring.value = true
        _syncError.value = null
        try {
            withContext(Dispatchers.IO) {
                val zipData = appContext.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: throw IllegalStateException("Failed to read backup file")
                GoogleDriveSyncManager.mergeBackup(zipData)
            }
            Log.i(TAG, "Restore from ${uri.lastPathSegment} complete")
        } catch (e: Exception) {
            Log.e(TAG, "Restore failed: ${e.message}", e)
            _syncError.value = e.message ?: "Restore failed"
        } finally {
            _isRestoring.value = false
        }
    }

    // ── Backup List ──

    data class LocalBackup(
        val name: String,
        val uri: Uri,
        val size: Long,
        val lastModified: Long,
    )

    suspend fun listBackups(): List<LocalBackup> = withContext(Dispatchers.IO) {
        val folder = getFolderDoc() ?: return@withContext emptyList()
        val backups = folder.listFiles()
            .filter { it.isFile && it.name?.startsWith(BACKUP_PREFIX) == true && it.name?.endsWith(".zip") == true }
            .map { doc ->
                LocalBackup(
                    name = doc.name ?: "unknown",
                    uri = doc.uri,
                    size = doc.length(),
                    lastModified = doc.lastModified(),
                )
            }
            .sortedByDescending { it.lastModified }
        backups
    }

    // ── Cleanup ──

    private fun cleanupOldBackups() {
        val folder = getFolderDoc() ?: return
        val maxBackups = prefs().getInt(KEY_MAX_BACKUPS, DEFAULT_MAX_BACKUPS)
        val backups = folder.listFiles()
            .filter { it.isFile && it.name?.startsWith(BACKUP_PREFIX) == true && it.name?.endsWith(".zip") == true }
            .sortedByDescending { it.lastModified() }
        if (backups.size > maxBackups) {
            backups.drop(maxBackups).forEach { it.delete() }
            Log.i(TAG, "Cleaned up ${backups.size - maxBackups} old backups")
        }
    }

    // ── Stats ──

    fun refreshStats() {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val folder = getFolderDoc() ?: return@launch
                val files = folder.listFiles()
                    .filter { it.isFile && it.name?.startsWith(BACKUP_PREFIX) == true && it.name?.endsWith(".zip") == true }
                _backupCount.value = files.size
                _totalBackupSize.value = files.sumOf { it.length() }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to refresh stats: ${e.message}")
            }
        }
    }

    // ── Auto Sync ──

    fun startAutoSync() {
        if (autoSyncJob?.isActive == true) return
        _isAutoSyncEnabled.value = true
        prefs().edit().putBoolean(KEY_AUTO_SYNC, true).apply()
        autoSyncJob = CoroutineScope(Dispatchers.IO).launch {
            while (isActive) {
                delay(SYNC_INTERVAL_MS)
                if (_hasDestination.value) {
                    backup()
                }
            }
        }
        Log.i(TAG, "Auto sync started (interval ${SYNC_INTERVAL_MS / 3600000}h)")
    }

    fun stopAutoSync() {
        autoSyncJob?.cancel()
        autoSyncJob = null
        _isAutoSyncEnabled.value = false
        prefs().edit().putBoolean(KEY_AUTO_SYNC, false).apply()
        Log.i(TAG, "Auto sync stopped")
    }

    // ── Helpers ──

    fun clearError() {
        _syncError.value = null
    }

    fun resetPhase() {
        _backupPhase.value = BackupPhase.IDLE
    }

    fun formatDate(timestamp: Long): String {
        if (timestamp == 0L) return "—"
        val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault())
        return fmt.format(Date(timestamp))
    }

    fun formatSize(bytes: Long): String {
        return when {
            bytes >= 1_000_000_000 -> "%.1f GB".format(bytes / 1_000_000_000.0)
            bytes >= 1_000_000 -> "%.1f MB".format(bytes / 1_000_000.0)
            bytes >= 1_000 -> "%.1f KB".format(bytes / 1_000.0)
            else -> "$bytes B"
        }
    }
}

/**
 * Progress phases for the backup capsule UI.
 * Mirrors iOS `BackupPhase` enum.
 */
enum class BackupPhase {
    IDLE,
    COLLECTING,
    PACKAGING,
    SAVING,
    DONE,
    ERROR,
}
