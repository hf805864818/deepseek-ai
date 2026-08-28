package com.openminis.app.data

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import com.openminis.app.auth.GoogleDriveOAuthManager
import com.openminis.app.data.db.AppDatabase
import com.openminis.app.data.db.ProviderDatabase
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
import org.json.JSONObject
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

    /** SharedPreferences file that stores syncable app settings snapshot. */
    private const val SETTINGS_PREFS = "minis_app_settings"
    private const val KEY_SETTINGS_TIMESTAMP = "settings_updated_at"
    private const val KEY_SETTINGS_SNAPSHOT = "settings_snapshot"

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
     * Create a backup: collect all files from [Context.filesDir] AND the
     * databases directory (minis.db, skills.db, provider.db), pack them
     * into a ZIP with prefixed paths (files/ and db/), include a settings
     * JSON snapshot, and upload to the "Minis" folder on Google Drive.
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
            val dbDir = appContext.getDatabasePath("dummy").parentFile
                ?: File(appContext.filesDir.parent, "databases")
            // Refresh settings snapshot so the latest preferences are included
            snapshotSettings()
            // ZIP building is CPU-heavy; run it off the main thread so the UI
            // doesn't freeze/fail during backup.
            val zipData = withContext(Dispatchers.IO) {
                createBackupZip(filesDir, dbDir)
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
     * Restore from a specific backup file. Downloads the ZIP and merges
     * its contents into local storage using LWW conflict resolution —
     * the same strategy as iCloud sync. Existing local data that is newer
     * than the backup is preserved; only missing or older records are
     * overwritten.
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
            // Merge is CPU+I/O heavy; run it off the main thread so the UI
            // doesn't freeze/fail during restore.
            withContext(Dispatchers.IO) {
                mergeBackup(zipData)
            }
            Log.i(TAG, "Restore (merge) completed from file: $fileId (${zipData.size} bytes)")
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
                .sortedByDescending { it.modifiedTime ?: "" }

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
     * Creates a backup ZIP containing:
     *   - files/ prefix: all files from [filesDir] (workspace, attachments,
     *     skills, memory, media, etc.)
     *   - db/ prefix: all database files from [dbDir] (minis.db, skills.db,
     *     provider.db) — SQLite WAL/SHM temp files are excluded.
     *   - settings/settings.json: a JSON snapshot of syncable app preferences.
     *
     * This multi-source format allows the restore path to distinguish
     * databases from file assets and apply LWW merging per category.
     */
    internal fun createBackupZip(filesDir: File, dbDir: File): ByteArray {
        val baos = ByteArrayOutputStream()
        ZipOutputStream(baos).use { zos ->
            // 1. File assets from filesDir
            collectFilesWithPrefix(filesDir, "files/", zos)
            // 2. Database files (skip WAL/SHM/journal temp files)
            if (dbDir.exists()) {
                collectFilesWithPrefix(dbDir, "db/", zos, skipSuffixes = listOf("-wal", "-shm", "-journal"))
            }
            // 3. Settings snapshot
            val settingsJson = collectSettingsJson()
            if (settingsJson.isNotEmpty()) {
                val entry = ZipEntry("settings/settings.json")
                zos.putNextEntry(entry)
                zos.write(settingsJson.toByteArray(Charsets.UTF_8))
                zos.closeEntry()
            }
        }
        return baos.toByteArray()
    }

    /**
     * Recursively collects all files under [directory] and writes them into
     * the ZIP with [prefix] prepended to each entry path. Files matching any
     * suffix in [skipSuffixes] are excluded (used to skip SQLite temp files).
     */
    private fun collectFilesWithPrefix(
        directory: File,
        prefix: String,
        zos: ZipOutputStream,
        skipSuffixes: List<String> = emptyList(),
    ) {
        val children = directory.listFiles() ?: return
        for (child in children) {
            if (child.isDirectory) {
                collectFilesWithPrefix(child, prefix, zos, skipSuffixes)
            } else {
                // Skip files matching exclusion suffixes
                if (skipSuffixes.any { child.name.endsWith(it) }) continue
                // Skip backup files if they somehow ended up in the directory
                if (child.name.startsWith(BACKUP_PREFIX) && child.name.endsWith(".zip")) continue

                val relativePath = child.absolutePath
                    .substring(directory.absolutePath.length + 1)
                val entryName = "$prefix$relativePath"
                val entry = ZipEntry(entryName)
                zos.putNextEntry(entry)
                child.inputStream().use { it.copyTo(zos) }
                zos.closeEntry()
            }
        }
    }

    /**
     * Merges a backup ZIP into local storage. Instead of overwriting all
     * files, this walks the backup and applies records with LWW (last-write-
     * wins) conflict resolution — the same logic used by iCloud sync.
     *
     * For SQLite databases (minis.db, skills.db, provider.db), records are
     * read from the backup DB and merged into the live DB via INSERT OR IGNORE
     * + conditional UPDATE where backup.updated_at >= local.updated_at.
     * For file assets, files are copied only if they are missing locally or
     * the backup copy is newer.
     *
     * Old-format backups (without files/ or db/ prefixes) fall back to the
     * original extract-and-overwrite behavior for backward compatibility.
     */
    internal fun mergeBackup(zipData: ByteArray) {
        // Read all entries from the ZIP
        val entries = mutableListOf<ZipEntryData>()
        ZipInputStream(zipData.inputStream()).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                val data = zis.readBytes()
                entries.add(ZipEntryData(entry.name, entry.isDirectory, data))
                zis.closeEntry()
                entry = zis.nextEntry
            }
        }

        // Detect backup format: new format uses files/ or db/ prefixes
        val fileEntries = entries.filter { !it.isDirectory }
        val isNewFormat = fileEntries.any { it.name.startsWith("files/") || it.name.startsWith("db/") }

        if (isNewFormat) {
            Log.i(TAG, "New-format backup detected — merging with LWW")
            mergeBackupNewFormat(fileEntries)
        } else {
            Log.i(TAG, "Old-format backup detected — extracting to filesDir (backward compat)")
            extractBackupOldFormat(fileEntries)
        }
    }

    /** Simple holder for a ZIP entry's metadata and content. */
    private data class ZipEntryData(
        val name: String,
        val isDirectory: Boolean,
        val data: ByteArray,
    )

    /**
     * Merges a new-format backup (with files/ and db/ prefixes).
     *
     * 1. Extract everything to a temp directory.
     * 2. Merge minis.db (sessions, messages, folders, compact_markers).
     * 3. Merge skills.db (skills, session_skill_overrides).
     * 4. Merge provider.db (provider configs).
     * 5. Copy file assets with deduplication by modification time.
     * 6. Apply settings snapshot with LWW.
     */
    private fun mergeBackupNewFormat(entries: List<ZipEntryData>) {
        // 1. Extract everything to a temp directory
        val tempDir = File(appContext.cacheDir, "minis-restore-${System.currentTimeMillis()}")
        tempDir.mkdirs()
        try {
            for (entry in entries) {
                val destFile = File(tempDir, entry.name)
                destFile.parentFile?.mkdirs()
                FileOutputStream(destFile).use { it.write(entry.data) }
            }
            Log.i(TAG, "Extracted ${entries.size} entries to temp dir for merging")

            // 2. Merge minis.db
            val backupMinisDb = File(tempDir, "db/minis.db")
            if (backupMinisDb.exists()) {
                mergeMinisDatabase(backupMinisDb)
            } else {
                Log.w(TAG, "Backup does not contain db/minis.db — skipping minis DB merge")
            }

            // 3. Merge skills.db
            val backupSkillsDb = File(tempDir, "db/skills.db")
            if (backupSkillsDb.exists()) {
                mergeSkillsDatabase(backupSkillsDb, tempDir)
            }

            // 4. Merge provider.db
            val backupProviderDb = File(tempDir, "db/provider.db")
            if (backupProviderDb.exists()) {
                mergeProviderDatabase(backupProviderDb)
            }

            // 5. Copy file assets with deduplication
            copyFileAssetsFromTemp(tempDir)

            // 6. Apply settings snapshot
            val settingsFile = File(tempDir, "settings/settings.json")
            if (settingsFile.exists()) {
                val settingsJson = settingsFile.readText(Charsets.UTF_8)
                applySettingsJson(settingsJson)
            }

            Log.i(TAG, "=== Backup merge complete ===")
        } finally {
            tempDir.deleteRecursively()
        }
    }

    // ── Database Merge: minis.db ──

    /**
     * Opens the backup minis.db and merges all records into the live
     * AppDatabase using LWW (last-write-wins) by updated_at.
     *
     * Sessions: INSERT OR IGNORE + conditional UPDATE (avoids cascade
     *   deletes on messages that INSERT OR REPLACE would trigger).
     * Messages: INSERT OR IGNORE + conditional UPDATE by updated_at.
     * Folders: INSERT OR REPLACE (no cascade risk).
     * Compact markers: INSERT OR IGNORE (append-only, never updated).
     * WebApp shortcuts: INSERT OR REPLACE.
     */
    private fun mergeMinisDatabase(backupDbPath: File) {
        val backupDb = SQLiteDatabase.openDatabase(
            backupDbPath.absolutePath, null, SQLiteDatabase.OPEN_READONLY
        )
        try {
            val liveDb = AppDatabase.getInstance(appContext).openHelper.writableDatabase
            liveDb.beginTransaction()
            try {
                var sessionCount = mergeSessions(backupDb, liveDb)
                var messageCount = mergeMessages(backupDb, liveDb)
                var folderCount = mergeFolders(backupDb, liveDb)
                var markerCount = mergeCompactMarkers(backupDb, liveDb)
                var shortcutCount = mergeWebAppShortcuts(backupDb, liveDb)
                liveDb.setTransactionSuccessful()
                Log.i(TAG, "minis.db merge: $sessionCount sessions, $messageCount messages, " +
                    "$folderCount folders, $markerCount compact markers, $shortcutCount shortcuts")
            } finally {
                liveDb.endTransaction()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to merge minis.db", e)
        } finally {
            backupDb.close()
        }
    }

    /** Merges sessions with LWW by updated_at. Uses INSERT OR IGNORE + UPDATE
     *  to avoid cascade-deleting messages (which INSERT OR REPLACE would do). */
    private fun mergeSessions(backupDb: SQLiteDatabase, liveDb: androidx.sqlite.db.SupportSQLiteDatabase): Int {
        var count = 0
        val cursor = backupDb.rawQuery(
            "SELECT id, title, model_id, created_at, updated_at, category, last_message, " +
                "model_binding, source, memory_enabled, pinned_at, edit_count, thinking_override, folder_id " +
                "FROM sessions", null
        )
        try {
            while (cursor.moveToNext()) {
                val id = cursor.getString(0)
                val updatedAt = cursor.getLong(4)

                // Check if local record is newer
                val localCursor = liveDb.query(
                    "SELECT updated_at FROM sessions WHERE id = ?", arrayOf(id)
                )
                val localUpdatedAt = if (localCursor.moveToFirst()) {
                    localCursor.getLong(0)
                } else -1L
                localCursor.close()

                if (localUpdatedAt >= updatedAt) continue // local is newer or same — skip

                // Build values map for INSERT OR IGNORE + UPDATE
                val v = android.content.ContentValues().apply {
                    put("id", id)
                    put("title", if (cursor.isNull(1)) null else cursor.getString(1))
                    put("model_id", cursor.getString(2))
                    put("created_at", cursor.getLong(3))
                    put("updated_at", updatedAt)
                    put("category", if (cursor.isNull(5)) null else cursor.getString(5))
                    put("last_message", if (cursor.isNull(6)) null else cursor.getString(6))
                    put("model_binding", if (cursor.isNull(7)) null else cursor.getString(7))
                    put("source", if (cursor.isNull(8)) null else cursor.getString(8))
                    put("memory_enabled", cursor.getInt(9))
                    put("pinned_at", if (cursor.isNull(10)) null else cursor.getLong(10))
                    put("edit_count", cursor.getInt(11))
                    put("thinking_override", if (cursor.isNull(12)) null else cursor.getString(12))
                    put("folder_id", if (cursor.isNull(13)) null else cursor.getString(13))
                }

                // INSERT OR IGNORE handles the "new record" case;
                // UPDATE handles the "overwrite older record" case.
                liveDb.insert("sessions", SQLiteDatabase.CONFLICT_IGNORE, v)
                liveDb.update("sessions", SQLiteDatabase.CONFLICT_REPLACE, v, "id = ?", arrayOf<Any?>(id))
                count++
            }
        } finally {
            cursor.close()
        }
        return count
    }

    /** Merges messages with LWW by updated_at (falls back to created_at). */
    private fun mergeMessages(backupDb: SQLiteDatabase, liveDb: androidx.sqlite.db.SupportSQLiteDatabase): Int {
        var count = 0
        val cursor = backupDb.rawQuery(
            "SELECT id, session_id, role, parts_json, created_at, token_usage, sort_order, " +
                "reasoning_content, stream_interrupt_count, updated_at, error_info FROM messages", null
        )
        try {
            while (cursor.moveToNext()) {
                val id = cursor.getString(0)
                val backupUpdatedAt = if (cursor.isNull(9)) cursor.getLong(4) else cursor.getLong(9)

                val localCursor = liveDb.query(
                    "SELECT updated_at FROM messages WHERE id = ?", arrayOf(id)
                )
                val localUpdatedAt = if (localCursor.moveToFirst() && !localCursor.isNull(0)) {
                    localCursor.getLong(0)
                } else -1L
                localCursor.close()

                // If updated_at is null, fall back to created_at for LWW comparison
                val effectiveLocalUpdatedAt = if (localUpdatedAt > 0) {
                    localUpdatedAt
                } else {
                    val c2 = liveDb.query("SELECT created_at FROM messages WHERE id = ?", arrayOf(id))
                    val v = if (c2.moveToFirst()) c2.getLong(0) else -1L
                    c2.close()
                    v
                }

                if (effectiveLocalUpdatedAt >= backupUpdatedAt) continue

                val v = android.content.ContentValues().apply {
                    put("id", id)
                    put("session_id", cursor.getString(1))
                    put("role", cursor.getString(2))
                    put("parts_json", cursor.getString(3))
                    put("created_at", cursor.getLong(4))
                    put("token_usage", if (cursor.isNull(5)) null else cursor.getString(5))
                    put("sort_order", cursor.getInt(6))
                    put("reasoning_content", if (cursor.isNull(7)) null else cursor.getString(7))
                    put("stream_interrupt_count", cursor.getInt(8))
                    put("updated_at", if (cursor.isNull(9)) null else cursor.getLong(9))
                    put("error_info", if (cursor.isNull(10)) null else cursor.getString(10))
                }
                liveDb.insert("messages", SQLiteDatabase.CONFLICT_IGNORE, v)
                liveDb.update("messages", SQLiteDatabase.CONFLICT_REPLACE, v, "id = ?", arrayOf<Any?>(id))
                count++
            }
        } finally {
            cursor.close()
        }
        return count
    }

    /** Merges folders with LWW by updated_at. INSERT OR REPLACE is safe —
     *  nothing cascades from folders. */
    private fun mergeFolders(backupDb: SQLiteDatabase, liveDb: androidx.sqlite.db.SupportSQLiteDatabase): Int {
        var count = 0
        val cursor = backupDb.rawQuery(
            "SELECT id, name, icon, color, origin, sort_index, pinned_at, description, " +
                "created_at, updated_at FROM folders", null
        )
        try {
            while (cursor.moveToNext()) {
                val id = cursor.getString(0)
                val backupUpdatedAt = cursor.getLong(9)

                val localCursor = liveDb.query(
                    "SELECT updated_at FROM folders WHERE id = ?", arrayOf(id)
                )
                val localUpdatedAt = if (localCursor.moveToFirst()) localCursor.getLong(0) else -1L
                localCursor.close()

                if (localUpdatedAt >= backupUpdatedAt) continue

                val v = android.content.ContentValues().apply {
                    put("id", id)
                    put("name", cursor.getString(1))
                    put("icon", if (cursor.isNull(2)) null else cursor.getString(2))
                    put("color", if (cursor.isNull(3)) null else cursor.getString(3))
                    put("origin", cursor.getString(4))
                    put("sort_index", cursor.getInt(5))
                    put("pinned_at", if (cursor.isNull(6)) null else cursor.getLong(6))
                    put("description", if (cursor.isNull(7)) null else cursor.getString(7))
                    put("created_at", cursor.getLong(8))
                    put("updated_at", backupUpdatedAt)
                }
                liveDb.insert("folders", SQLiteDatabase.CONFLICT_REPLACE, v)
                count++
            }
        } finally {
            cursor.close()
        }
        return count
    }

    /** Merges compact markers. Append-only — INSERT OR IGNORE only. */
    private fun mergeCompactMarkers(backupDb: SQLiteDatabase, liveDb: androidx.sqlite.db.SupportSQLiteDatabase): Int {
        var count = 0
        // Check if compact_markers table exists in backup
        val tableCursor = backupDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='compact_markers'", null
        )
        val hasTable = tableCursor.moveToFirst()
        tableCursor.close()
        if (!hasTable) return 0

        val cursor = backupDb.rawQuery(
            "SELECT id, session_id, summary, first_kept_sort_order, compacted_count, " +
                "created_at, ui_boundary_sort_order, boundary_message_id, " +
                "first_kept_message_id, last_compacted_message_id, version FROM compact_markers", null
        )
        try {
            while (cursor.moveToNext()) {
                val v = android.content.ContentValues().apply {
                    put("id", cursor.getString(0))
                    put("session_id", cursor.getString(1))
                    put("summary", cursor.getString(2))
                    put("first_kept_sort_order", cursor.getInt(3))
                    put("compacted_count", cursor.getInt(4))
                    put("created_at", cursor.getLong(5))
                    put("ui_boundary_sort_order", if (cursor.isNull(6)) null else cursor.getInt(6))
                    put("boundary_message_id", if (cursor.isNull(7)) null else cursor.getString(7))
                    put("first_kept_message_id", if (cursor.isNull(8)) null else cursor.getString(8))
                    put("last_compacted_message_id", if (cursor.isNull(9)) null else cursor.getString(9))
                    put("version", cursor.getInt(10))
                }
                liveDb.insert("compact_markers", SQLiteDatabase.CONFLICT_IGNORE, v)
                count++
            }
        } finally {
            cursor.close()
        }
        return count
    }

    /** Merges webapp shortcuts. INSERT OR REPLACE is safe (no cascade). */
    private fun mergeWebAppShortcuts(backupDb: SQLiteDatabase, liveDb: androidx.sqlite.db.SupportSQLiteDatabase): Int {
        var count = 0
        val tableCursor = backupDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='webapp_shortcuts'", null
        )
        val hasTable = tableCursor.moveToFirst()
        tableCursor.close()
        if (!hasTable) return 0

        val cursor = backupDb.rawQuery(
            "SELECT id, html_path, path_scope, scope_context, title, icon_ref, " +
                "icon_cache_path, created_at, source_session_id FROM webapp_shortcuts", null
        )
        try {
            while (cursor.moveToNext()) {
                val v = android.content.ContentValues().apply {
                    put("id", cursor.getString(0))
                    put("html_path", cursor.getString(1))
                    put("path_scope", cursor.getString(2))
                    put("scope_context", if (cursor.isNull(3)) null else cursor.getString(3))
                    put("title", cursor.getString(4))
                    put("icon_ref", cursor.getString(5))
                    put("icon_cache_path", if (cursor.isNull(6)) null else cursor.getString(6))
                    put("created_at", cursor.getLong(7))
                    put("source_session_id", if (cursor.isNull(8)) null else cursor.getString(8))
                }
                liveDb.insert("webapp_shortcuts", SQLiteDatabase.CONFLICT_REPLACE, v)
                count++
            }
        } finally {
            cursor.close()
        }
        return count
    }

    // ── Database Merge: skills.db ──

    /**
     * Opens the backup skills.db and merges skills into the live skills.db
     * using LWW by updated_at. Skill SKILL.md files are copied from the
     * backup's files/minis-global/skills/ directory.
     */
    private fun mergeSkillsDatabase(backupDbPath: File, tempDir: File) {
        val backupDb = SQLiteDatabase.openDatabase(
            backupDbPath.absolutePath, null, SQLiteDatabase.OPEN_READONLY
        )
        try {
            // The live skills.db is managed by SkillRepository's SQLiteOpenHelper.
            // We open it directly for the merge transaction.
            val liveSkillsDbPath = appContext.getDatabasePath("skills.db")
            if (!liveSkillsDbPath.exists()) {
                Log.w(TAG, "Live skills.db not found — skipping skills merge")
                return
            }
            val liveDb = SQLiteDatabase.openDatabase(
                liveSkillsDbPath.absolutePath, null, SQLiteDatabase.OPEN_READWRITE
            )
            liveDb.beginTransaction()
            try {
                var count = 0
                val cursor = backupDb.rawQuery(
                    "SELECT id, name, description, version, import_source, source_url, " +
                        "is_enabled, installed_at, updated_at, use_count FROM skills", null
                )
                try {
                    while (cursor.moveToNext()) {
                        val id = cursor.getString(0)
                        val backupUpdatedAt = cursor.getLong(8)

                        // Check local updated_at
                        val localCursor = liveDb.rawQuery(
                            "SELECT updated_at FROM skills WHERE id = ?", arrayOf(id)
                        )
                        val localUpdatedAt = if (localCursor.moveToFirst()) localCursor.getLong(0) else -1L
                        localCursor.close()

                        if (localUpdatedAt >= backupUpdatedAt) continue

                        val v = android.content.ContentValues().apply {
                            put("id", id)
                            put("name", cursor.getString(1))
                            put("description", cursor.getString(2))
                            put("version", cursor.getString(3))
                            put("import_source", cursor.getString(4))
                            put("source_url", if (cursor.isNull(5)) null else cursor.getString(5))
                            put("is_enabled", cursor.getInt(6))
                            put("installed_at", cursor.getLong(7))
                            put("updated_at", backupUpdatedAt)
                            put("use_count", cursor.getDouble(9))
                        }
                        liveDb.insertWithOnConflict("skills", null, v, SQLiteDatabase.CONFLICT_REPLACE)

                        // Copy SKILL.md file from backup temp dir
                        val backupSkillMd = File(tempDir, "files/minis-global/skills/$id/SKILL.md")
                        if (backupSkillMd.exists()) {
                            val liveSkillDir = File(appContext.filesDir, "minis-global/skills/$id")
                            liveSkillDir.mkdirs()
                            val liveSkillMd = File(liveSkillDir, "SKILL.md")
                            backupSkillMd.copyTo(liveSkillMd, overwrite = true)
                        }
                        count++
                    }
                } finally {
                    cursor.close()
                }

                // Merge session_skill_overrides
                var overrideCount = 0
                val overrideCursor = backupDb.rawQuery(
                    "SELECT session_id, skill_id, is_enabled FROM session_skill_overrides", null
                )
                try {
                    while (overrideCursor.moveToNext()) {
                        val v = android.content.ContentValues().apply {
                            put("session_id", overrideCursor.getString(0))
                            put("skill_id", overrideCursor.getString(1))
                            put("is_enabled", overrideCursor.getInt(2))
                        }
                        liveDb.insertWithOnConflict(
                            "session_skill_overrides", null, v, SQLiteDatabase.CONFLICT_REPLACE
                        )
                        overrideCount++
                    }
                } finally {
                    overrideCursor.close()
                }

                liveDb.setTransactionSuccessful()
                Log.i(TAG, "skills.db merge: $count skills, $overrideCount overrides")
            } finally {
                liveDb.endTransaction()
                liveDb.close()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to merge skills.db", e)
        } finally {
            backupDb.close()
        }
    }

    // ── Database Merge: provider.db ──

    /**
     * Opens the backup provider.db and merges provider configs into the
     * live provider database using INSERT OR REPLACE (provider configs are
     * keyed by id with no cascade dependencies).
     */
    private fun mergeProviderDatabase(backupDbPath: File) {
        val backupDb = SQLiteDatabase.openDatabase(
            backupDbPath.absolutePath, null, SQLiteDatabase.OPEN_READONLY
        )
        try {
            val liveDb = ProviderDatabase.getInstance(appContext).openHelper.writableDatabase
            liveDb.beginTransaction()
            try {
                // provider_instances — use IGNORE to avoid cascade-deleting child
                // model_entries that INSERT OR REPLACE would trigger via FK CASCADE.
                var instanceCount = mergeTableSimple(backupDb, liveDb,
                    "provider_instances",
                    "id, label, provider_type, credential_type, custom_base_url, " +
                        "append_v1_suffix, use_responses_api, azure_mode, " +
                        "image_endpoint_mode, image_endpoint_resolved, custom_user_agent, " +
                        "is_enabled, sort_order, created_at",
                    "id",
                    useIgnore = true
                )

                // provider_model_entries
                var modelCount = mergeTableSimple(backupDb, liveDb,
                    "provider_model_entries",
                    "id, provider_instance_id, base_model_json, overrides_json, " +
                        "is_custom, is_hidden, sort_order, user_modified_at",
                    "id"
                )

                // provider_model_groups
                var groupCount = mergeTableSimple(backupDb, liveDb,
                    "provider_model_groups",
                    "id, name, strategy, fallback_strategy, default_thinking_level, " +
                        "context_limit_tokens, last_context_limit_tokens, " +
                        "member_entry_ids_json, sort_order",
                    "id"
                )

                // provider_agent_loop_ids (composite PK: kind, target_id)
                var loopIdCount = mergeTableSimple(backupDb, liveDb,
                    "provider_agent_loop_ids",
                    "kind, target_id, sort_order",
                    "kind"
                )

                // provider_config_meta (PK: key)
                var metaCount = mergeTableSimple(backupDb, liveDb,
                    "provider_config_meta",
                    "key, value",
                    "key"
                )

                // provider_thinking_rules
                var rulesCount = 0
                val tableCursor = backupDb.rawQuery(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name='provider_thinking_rules'", null
                )
                val hasRules = tableCursor.moveToFirst()
                tableCursor.close()
                if (hasRules) {
                    rulesCount = mergeTableSimple(backupDb, liveDb,
                        "provider_thinking_rules",
                        "id, provider_instance_id, label, scope_kind, scope_pattern, " +
                            "wire_format_json, reasoning_echo_json, sort_order",
                        "id"
                    )
                }

                liveDb.setTransactionSuccessful()
                Log.i(TAG, "provider.db merge: $instanceCount instances, $modelCount models, " +
                    "$groupCount groups, $loopIdCount loop ids, $metaCount meta, $rulesCount rules")
            } finally {
                liveDb.endTransaction()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to merge provider.db", e)
        } finally {
            backupDb.close()
        }
    }

    /**
     * Generic table merge: reads all rows from [tableName] in [backupDb],
     * using the given [columns] SELECT list, and inserts into the live
     * database. Uses INSERT OR REPLACE by default; set [useIgnore] to true
     * for parent tables with CASCADE child tables (e.g. provider_instances)
     * to avoid deleting child rows.
     *
     * Returns the number of rows merged.
     */
    private fun mergeTableSimple(
        backupDb: SQLiteDatabase,
        liveDb: androidx.sqlite.db.SupportSQLiteDatabase,
        tableName: String,
        columns: String,
        conflictColumn: String,
        useIgnore: Boolean = false,
    ): Int {
        // Check if table exists in backup
        val tableCursor = backupDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?", arrayOf(tableName)
        )
        val hasTable = tableCursor.moveToFirst()
        tableCursor.close()
        if (!hasTable) return 0

        var count = 0
        val columnList = columns.split(", ").map { it.trim() }
        val cursor = backupDb.rawQuery("SELECT $columns FROM $tableName", null)
        try {
            val conflictStrategy = if (useIgnore) SQLiteDatabase.CONFLICT_IGNORE
                                   else SQLiteDatabase.CONFLICT_REPLACE
            while (cursor.moveToNext()) {
                val v = android.content.ContentValues()
                for ((colIndex, colName) in columnList.withIndex()) {
                    if (cursor.isNull(colIndex)) {
                        v.putNull(colName)
                    } else {
                        // Read as string — SQLite will coerce types appropriately
                        v.put(colName, cursor.getString(colIndex))
                    }
                }
                liveDb.insert(tableName, conflictStrategy, v)
                count++
            }
        } finally {
            cursor.close()
        }
        return count
    }

    // ── File Asset Deduplication ──

    /**
     * Copies file assets from the temp restore directory to their live
     * locations, skipping files that already exist locally and are newer
     * or the same age (deduplication by modification time).
     */
    private fun copyFileAssetsFromTemp(tempDir: File) {
        val filesTemp = File(tempDir, "files")
        if (!filesTemp.exists()) return

        val filesLive = appContext.filesDir
        var copied = 0
        var skipped = 0

        filesTemp.walkTopDown().filter { it.isFile }.forEach { sourceFile ->
            val relativePath = sourceFile.absolutePath
                .substring(filesTemp.absolutePath.length + 1)
            val destFile = File(filesLive, relativePath)
            destFile.parentFile?.mkdirs()

            // Dedup: skip if local exists and is >= backup mtime
            if (destFile.exists()) {
                val localMod = destFile.lastModified()
                val backupMod = sourceFile.lastModified()
                if (localMod >= backupMod) {
                    skipped++
                    return@forEach
                }
                // Backup is newer — remove old file before copy
                destFile.delete()
            }

            sourceFile.copyTo(destFile, overwrite = true)
            copied++
        }
        Log.i(TAG, "File dedup: copied $copied, skipped $skipped (local newer/same)")
    }

    // ── Settings Sync ──

    /**
     * Collects syncable app preferences into a JSON string. Only non-
     * device-specific settings are included (appearance, auto-grouping,
     * memory toggle, fonts, etc.). Auth tokens, Google Drive credentials,
     * and device-local state are excluded.
     *
     * The JSON includes a "updatedAt" timestamp for LWW comparison.
     */
    private fun collectSettingsJson(): String {
        val prefs = appContext.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
        val updatedAt = prefs.getLong(KEY_SETTINGS_TIMESTAMP, 0L)
        val snapshot = prefs.getString(KEY_SETTINGS_SNAPSHOT, "") ?: ""

        // If no settings have ever been saved, return empty
        if (updatedAt == 0L || snapshot.isEmpty()) return ""

        // Wrap in an outer object with timestamp for LWW on restore
        val wrapper = JSONObject()
        wrapper.put("updatedAt", updatedAt)
        wrapper.put("settings", JSONObject(snapshot))
        return wrapper.toString()
    }

    /**
     * Applies a settings JSON snapshot from a backup, but only if the
     * backup's timestamp is newer than the local one (LWW). Writes the
     * merged settings into the live SharedPreferences.
     */
    private fun applySettingsJson(jsonStr: String) {
        try {
            val wrapper = JSONObject(jsonStr)
            val remoteUpdatedAt = wrapper.optLong("updatedAt", 0L)
            val remoteSettings = wrapper.optJSONObject("settings") ?: return

            val prefs = appContext.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
            val localUpdatedAt = prefs.getLong(KEY_SETTINGS_TIMESTAMP, 0L)

            // LWW: only apply if remote is strictly newer
            if (remoteUpdatedAt <= localUpdatedAt) {
                Log.i(TAG, "Settings: local ($localUpdatedAt) >= remote ($remoteUpdatedAt) — skipping")
                return
            }

            // Apply each setting key to the app's default SharedPreferences
            val defaultPrefs = appContext.getSharedPreferences(
                appContext.packageName + "_preferences", Context.MODE_PRIVATE
            )
            val editor = defaultPrefs.edit()
            val keys = remoteSettings.keys()
            for (key in keys) {
                when (val value = remoteSettings.get(key)) {
                    is Boolean -> editor.putBoolean(key, value)
                    is Int -> editor.putInt(key, value)
                    is Long -> editor.putLong(key, value)
                    is String -> editor.putString(key, value)
                    is Double -> editor.putFloat(key, value.toFloat())
                    else -> { /* skip unsupported types */ }
                }
            }
            editor.apply()

            // Record the applied snapshot for future LWW comparison
            prefs.edit()
                .putLong(KEY_SETTINGS_TIMESTAMP, remoteUpdatedAt)
                .putString(KEY_SETTINGS_SNAPSHOT, remoteSettings.toString())
                .apply()

            Log.i(TAG, "Settings applied from backup (timestamp: $remoteUpdatedAt)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply settings JSON", e)
        }
    }

    /**
     * Called by the app when user-facing settings change. Snapshots the
     * syncable preferences and stamps them with the current time so they
     * will be included in the next backup.
     */
    fun snapshotSettings() {
        val defaultPrefs = appContext.getSharedPreferences(
            appContext.packageName + "_preferences", Context.MODE_PRIVATE
        )
        // Collect known syncable keys
        val syncableKeys = listOf(
            "appearanceMode",
            "autoGroupingEnabled",
            "memory.global.enabled",
            "backgroundNotificationsEnabled",
            "font.chatInput",
            "font.messageBase",
            "font.appBase",
        )
        val settingsJson = JSONObject()
        for (key in syncableKeys) {
            if (defaultPrefs.contains(key)) {
                // Read as string — type will be inferred on apply
                val value = defaultPrefs.all[key]
                when (value) {
                    is Boolean -> settingsJson.put(key, value)
                    is Int -> settingsJson.put(key, value)
                    is Long -> settingsJson.put(key, value)
                    is String -> settingsJson.put(key, value)
                    is Float -> settingsJson.put(key, value.toDouble())
                    else -> {}
                }
            }
        }

        val now = System.currentTimeMillis()
        appContext.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_SETTINGS_TIMESTAMP, now)
            .putString(KEY_SETTINGS_SNAPSHOT, settingsJson.toString())
            .apply()
        Log.i(TAG, "Settings snapshot updated (timestamp: $now)")
    }

    // ── Old-format backward compatibility ──

    /**
     * Old-format backup extraction (backward compatibility). Extracts
     * files directly to the filesDir, overwriting existing files. Used
     * when a backup doesn't have the files/ or db/ prefix (pre-merge era).
     */
    private fun extractBackupOldFormat(entries: List<ZipEntryData>) {
        val filesDir = appContext.filesDir
        for (entry in entries) {
            val destFile = File(filesDir, entry.name)
            destFile.parentFile?.mkdirs()
            FileOutputStream(destFile).use { it.write(entry.data) }
        }
        Log.i(TAG, "Old-format extraction complete: ${entries.size} files restored")
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
