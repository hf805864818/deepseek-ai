package com.openminis.app.ui.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Restore
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.CloudSync
import androidx.compose.material.icons.outlined.FolderOff
import androidx.compose.material.icons.outlined.Upload
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openminis.app.R
import com.openminis.app.data.BackupPhase
import com.openminis.app.data.LocalSyncManager
import com.openminis.app.data.LocalSyncManager.LocalBackup
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Local Sync settings screen. Lets the user pick a directory via SAF,
 * export backups as ZIP files, restore, and enable auto-sync.
 *
 * The "Backup Now" button is always visible. If no folder is selected,
 * tapping it opens the folder picker first, then starts the backup.
 * A capsule toast at the top shows progress phases (collecting →
 * packaging → saving → done/error).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocalSyncScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    // Init manager
    LaunchedEffect(Unit) {
        LocalSyncManager.init(context.applicationContext)
    }

    // Collect reactive state
    val hasDestination by LocalSyncManager.hasDestination.collectAsState()
    val destinationName by LocalSyncManager.destinationName.collectAsState()
    val isBackingUp by LocalSyncManager.isBackingUp.collectAsState()
    val isRestoring by LocalSyncManager.isRestoring.collectAsState()
    val syncError by LocalSyncManager.syncError.collectAsState()
    val lastSyncTime by LocalSyncManager.lastSyncTime.collectAsState()
    val backupCount by LocalSyncManager.backupCount.collectAsState()
    val totalBackupSize by LocalSyncManager.totalBackupSize.collectAsState()
    val isAutoSyncEnabled by LocalSyncManager.isAutoSyncEnabled.collectAsState()
    val backupPhase by LocalSyncManager.backupPhase.collectAsState()

    var backups by remember { mutableStateOf<List<LocalBackup>>(emptyList()) }
    var pendingBackupAfterPicker by remember { mutableStateOf(false) }
    var menuForBackup by remember { mutableStateOf<LocalBackup?>(null) }
    var confirmDelete by remember { mutableStateOf<LocalBackup?>(null) }
    var confirmRestore by remember { mutableStateOf<LocalBackup?>(null) }

    // SAF folder picker launcher
    val folderPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree(),
    ) { uri ->
        if (uri != null) {
            // Take persistable permission + save
            LocalSyncManager.saveDestination(uri)
            if (pendingBackupAfterPicker) {
                pendingBackupAfterPicker = false
                // Auto-start backup after folder selection
                scope.launch { LocalSyncManager.backup() }
            }
        } else {
            // User cancelled — reset pending state
            pendingBackupAfterPicker = false
        }
    }

    // Load backups when destination is set
    LaunchedEffect(hasDestination) {
        if (hasDestination) {
            backups = LocalSyncManager.listBackups()
        } else {
            backups = emptyList()
        }
    }

    // Refresh backup list when backup finishes
    LaunchedEffect(isBackingUp) {
        if (!isBackingUp && hasDestination) {
            backups = LocalSyncManager.listBackups()
        }
    }

    // Show errors via Snackbar
    LaunchedEffect(syncError) {
        syncError?.let {
            snackbarHostState.showSnackbar(it)
            LocalSyncManager.clearError()
        }
    }

    // Auto-dismiss capsule after done/error
    LaunchedEffect(backupPhase) {
        when (backupPhase) {
            BackupPhase.DONE -> { delay(2000); LocalSyncManager.resetPhase() }
            BackupPhase.ERROR -> { delay(2500); LocalSyncManager.resetPhase() }
            else -> {}
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.local_sync_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.back),
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState()),
            ) {
                // ── Destination section ──
                SyncSection(title = stringResource(R.string.local_sync_destination)) {
                    if (hasDestination) {
                        // Folder selected — show name + change/clear
                        SyncRow(
                            icon = Icons.Outlined.Folder,
                            iconColor = Color(0xFF34C759),
                            title = destinationName ?: stringResource(R.string.local_sync_folder_selected),
                            subtitle = stringResource(R.string.local_sync_tap_to_change),
                            onClick = { folderPicker.launch(null) },
                        )
                        SyncRow(
                            icon = Icons.Outlined.FolderOff,
                            iconColor = Color(0xFFFF3B30),
                            title = stringResource(R.string.local_sync_clear_folder),
                            subtitle = null,
                            onClick = { LocalSyncManager.clearDestination() },
                            showDivider = false,
                        )
                    } else {
                        // No folder — show choose button
                        SyncRow(
                            icon = Icons.Outlined.Folder,
                            iconColor = Color(0xFF34C759),
                            title = stringResource(R.string.local_sync_choose_folder),
                            subtitle = stringResource(R.string.local_sync_choose_folder_desc),
                            onClick = { folderPicker.launch(null) },
                            showDivider = false,
                        )
                    }
                }

                // ── Sync section (always visible) ──
                SyncSection(title = stringResource(R.string.local_sync_sync)) {
                    if (hasDestination) {
                        SyncRow(
                            icon = Icons.Outlined.Schedule,
                            iconColor = Color(0xFF007AFF),
                            title = stringResource(R.string.local_sync_last_sync),
                            subtitle = LocalSyncManager.formatDate(lastSyncTime),
                            onClick = {},
                        )
                        SyncRow(
                            icon = Icons.Outlined.CloudSync,
                            iconColor = Color(0xFF5856D6),
                            title = stringResource(R.string.local_sync_backups),
                            subtitle = stringResource(
                                R.string.local_sync_backups_subtitle,
                                backupCount,
                                LocalSyncManager.formatSize(totalBackupSize),
                            ),
                            onClick = {},
                        )
                    } else {
                        // Hint when no destination
                        Text(
                            text = stringResource(R.string.local_sync_no_folder_hint),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                        )
                    }
                    Spacer(Modifier.height(12.dp))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        // Backup Now — always visible
                        OutlinedButton(
                            onClick = {
                                if (hasDestination) {
                                    scope.launch { LocalSyncManager.backup() }
                                } else {
                                    // No folder — open picker, then auto-backup
                                    pendingBackupAfterPicker = true
                                    folderPicker.launch(null)
                                }
                            },
                            enabled = !isBackingUp && !isRestoring,
                            modifier = Modifier.weight(1f),
                        ) {
                            if (isBackingUp) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(16.dp),
                                    strokeWidth = 2.dp,
                                )
                            } else {
                                Icon(Icons.Outlined.Upload, contentDescription = null, modifier = Modifier.size(18.dp))
                            }
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.local_sync_backup_now))
                        }
                        if (hasDestination) {
                            OutlinedButton(
                                onClick = {
                                    scope.launch { LocalSyncManager.restore() }
                                },
                                enabled = !isBackingUp && !isRestoring,
                                modifier = Modifier.weight(1f),
                            ) {
                                if (isRestoring) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(16.dp),
                                        strokeWidth = 2.dp,
                                    )
                                } else {
                                    Icon(Icons.Outlined.Restore, contentDescription = null, modifier = Modifier.size(18.dp))
                                }
                                Spacer(Modifier.width(8.dp))
                                Text(stringResource(R.string.local_sync_restore_latest))
                            }
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }

                if (hasDestination) {
                    // ── Auto Sync section ──
                    SyncSection(title = stringResource(R.string.local_sync_auto_sync)) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    scope.launch {
                                        if (isAutoSyncEnabled) {
                                            LocalSyncManager.stopAutoSync()
                                        } else {
                                            LocalSyncManager.startAutoSync()
                                        }
                                    }
                                }
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            SyncIcon(Icons.Outlined.Sync, Color(0xFFFF9500))
                            Spacer(Modifier.width(14.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = stringResource(R.string.local_sync_auto_sync),
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = MaterialTheme.colorScheme.onSurface,
                                )
                                Text(
                                    text = stringResource(R.string.local_sync_auto_sync_desc),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            Switch(
                                checked = isAutoSyncEnabled,
                                onCheckedChange = { enabled ->
                                    scope.launch {
                                        if (enabled) {
                                            LocalSyncManager.startAutoSync()
                                        } else {
                                            LocalSyncManager.stopAutoSync()
                                        }
                                    }
                                },
                            )
                        }
                    }

                    // ── Backups list section ──
                    SyncSection(title = stringResource(R.string.local_sync_backups)) {
                        if (backups.isEmpty()) {
                            Text(
                                text = stringResource(R.string.local_sync_no_backups),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 16.dp),
                            )
                        } else {
                            backups.forEachIndexed { index, backup ->
                                if (index > 0) SyncDivider()
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .combinedClickable(
                                            onClick = { confirmRestore = backup },
                                            onLongClick = { menuForBackup = backup },
                                        )
                                        .padding(horizontal = 14.dp, vertical = 12.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    SyncIcon(Icons.Outlined.Folder, Color(0xFF007AFF))
                                    Spacer(Modifier.width(14.dp))
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = backup.name.removePrefix("minis-backup-").removeSuffix(".zip"),
                                            style = MaterialTheme.typography.bodyLarge,
                                            color = MaterialTheme.colorScheme.onSurface,
                                        )
                                        val sizeText = LocalSyncManager.formatSize(backup.size)
                                        val dateText = backup.lastModified.let {
                                            if (it > 0) {
                                                val fmt = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault())
                                                "${fmt.format(java.util.Date(it))} - $sizeText"
                                            } else {
                                                sizeText
                                            }
                                        }
                                        Text(
                                            text = dateText,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                    Icon(
                                        Icons.Outlined.MoreVert,
                                        contentDescription = stringResource(R.string.local_sync_more_options),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                                        modifier = Modifier
                                            .size(20.dp)
                                            .clickable { menuForBackup = backup },
                                    )
                                }
                            }
                        }
                    }
                }

                Spacer(Modifier.height(24.dp))
            }

            // ── Capsule progress overlay ──
            CapsuleProgress(backupPhase)
        }
    }

    // Long-press dropdown menu
    DropdownMenu(
        expanded = menuForBackup != null,
        onDismissRequest = { menuForBackup = null },
    ) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.local_sync_restore)) },
            onClick = {
                val backup = menuForBackup
                menuForBackup = null
                if (backup != null) confirmRestore = backup
            },
            leadingIcon = { Icon(Icons.Outlined.Restore, contentDescription = null, modifier = Modifier.size(20.dp)) },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.delete)) },
            onClick = {
                val backup = menuForBackup
                menuForBackup = null
                if (backup != null) confirmDelete = backup
            },
            leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(20.dp)) },
        )
    }

    // Restore confirmation dialog
    confirmRestore?.let { backup ->
        AlertDialog(
            onDismissRequest = { confirmRestore = null },
            title = { Text(stringResource(R.string.local_sync_restore_backup)) },
            text = { Text(stringResource(R.string.local_sync_restore_confirm, backup.name)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        val uri = backup.uri
                        confirmRestore = null
                        scope.launch { LocalSyncManager.restoreFrom(uri) }
                    },
                ) { Text(stringResource(R.string.local_sync_restore)) }
            },
            dismissButton = {
                TextButton(onClick = { confirmRestore = null }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }

    // Delete confirmation dialog
    confirmDelete?.let { backup ->
        AlertDialog(
            onDismissRequest = { confirmDelete = null },
            title = { Text(stringResource(R.string.local_sync_delete_backup)) },
            text = { Text(stringResource(R.string.local_sync_delete_confirm, backup.name)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        val doc = androidx.documentfile.provider.DocumentFile.fromSingleUri(context, backup.uri)
                        doc?.delete()
                        confirmDelete = null
                        scope.launch {
                            backups = LocalSyncManager.listBackups()
                            LocalSyncManager.refreshStats()
                        }
                    },
                ) { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = null }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

// ── Capsule Progress ──

@Composable
private fun CapsuleProgress(phase: BackupPhase) {
    val visible = phase != BackupPhase.IDLE
    val message = when (phase) {
        BackupPhase.COLLECTING -> R.string.local_sync_collecting
        BackupPhase.PACKAGING -> R.string.local_sync_packaging
        BackupPhase.SAVING -> R.string.local_sync_saving
        BackupPhase.DONE -> R.string.local_sync_backup_complete
        BackupPhase.ERROR -> R.string.local_sync_backup_failed
        BackupPhase.IDLE -> R.string.local_sync_backup_complete
    }
    val iconColor = when (phase) {
        BackupPhase.DONE -> Color(0xFF34C759)
        BackupPhase.ERROR -> Color(0xFFFF3B30)
        else -> Color(0xFF007AFF)
    }
    val showSpinner = phase == BackupPhase.COLLECTING ||
        phase == BackupPhase.PACKAGING ||
        phase == BackupPhase.SAVING

    AnimatedVisibility(
        visible = visible,
        enter = slideInVertically(initialOffsetY = { -it }) + fadeIn(),
        exit = slideOutVertically(targetOffsetY = { -it }) + fadeOut(),
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            contentAlignment = Alignment.TopCenter,
        ) {
            Row(
                modifier = Modifier
                    .wrapContentSize()
                    .clip(RoundedCornerShape(20.dp))
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (showSpinner) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = iconColor,
                    )
                } else {
                    Icon(
                        imageVector = if (phase == BackupPhase.DONE) Icons.Outlined.Check else Icons.Outlined.Close,
                        contentDescription = null,
                        tint = iconColor,
                        modifier = Modifier.size(16.dp),
                    )
                }
                Text(
                    text = stringResource(message),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    fontWeight = FontWeight.Medium,
                )
            }
        }
    }
}

// ── Shared local UI components (mirror GoogleDriveSyncScreen) ──

@Composable
private fun SyncSection(
    title: String,
    content: @Composable () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 20.dp),
    ) {
        Text(
            text = title.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = FontWeight.Medium,
            letterSpacing = 0.5.sp,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.surfaceContainerLow),
        ) {
            content()
        }
    }
}

@Composable
private fun SyncRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconColor: Color,
    title: String,
    subtitle: String?,
    onClick: () -> Unit,
    showDivider: Boolean = true,
) {
    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick)
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SyncIcon(icon, iconColor)
            Spacer(Modifier.width(14.dp))
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(1.dp),
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                if (subtitle != null) {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                modifier = Modifier.size(20.dp),
            )
        }
        if (showDivider) {
            SyncDivider()
        }
    }
}

@Composable
private fun SyncIcon(icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color) {
    Box(
        modifier = Modifier
            .size(30.dp)
            .background(color = color, shape = CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier.size(16.dp),
        )
    }
}

@Composable
private fun SyncDivider() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 58.dp, end = 14.dp)
            .height(0.5.dp)
            .background(MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)),
    )
}
