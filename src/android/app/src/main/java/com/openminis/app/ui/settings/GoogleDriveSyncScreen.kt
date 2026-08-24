package com.openminis.app.ui.settings

import androidx.compose.foundation.ExperimentalFoundationApi
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.CloudSync
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Restore
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Sync
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openminis.app.R
import com.openminis.app.auth.GoogleDriveOAuthManager
import com.openminis.app.data.GoogleDriveFile
import com.openminis.app.data.GoogleDriveSyncManager
import kotlinx.coroutines.launch

/**
 * Google Drive sync screen. Provides account login/logout, manual backup
 * and restore, auto-sync toggle, and a list of existing backups with
 * per-item restore and delete actions.
 *
 * Visual style mirrors [SettingsScreen] — same grouped Card sections,
 * colored circle icons, and divider pattern. Local component copies
 * are used because the SettingsScreen helpers are file-private.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun GoogleDriveSyncScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val oauthManager = remember { GoogleDriveOAuthManager.forSync(context.applicationContext) }
    val snackbarHostState = remember { SnackbarHostState() }

    val isSyncing by GoogleDriveSyncManager.isSyncing.collectAsState()
    val syncError by GoogleDriveSyncManager.syncError.collectAsState()
    val lastSyncTime by GoogleDriveSyncManager.lastSyncTime.collectAsState()
    val backupCount by GoogleDriveSyncManager.backupCount.collectAsState()
    val totalBackupSize by GoogleDriveSyncManager.totalBackupSize.collectAsState()
    val isAutoSyncEnabled by GoogleDriveSyncManager.isAutoSyncEnabled.collectAsState()

    var isLoggedIn by remember { mutableStateOf(oauthManager.isAuthenticated()) }
    var email by remember { mutableStateOf(oauthManager.email) }
    var backups by remember { mutableStateOf<List<GoogleDriveFile>>(emptyList()) }
    var menuForBackup by remember { mutableStateOf<GoogleDriveFile?>(null) }
    var confirmDelete by remember { mutableStateOf<GoogleDriveFile?>(null) }
    var confirmRestore by remember { mutableStateOf<GoogleDriveFile?>(null) }

    // Initialise the sync manager once.
    LaunchedEffect(Unit) {
        GoogleDriveSyncManager.init(context.applicationContext)
    }

    // Load backups when logged in.
    LaunchedEffect(isLoggedIn) {
        if (isLoggedIn) {
            backups = GoogleDriveSyncManager.listBackups(oauthManager)
        } else {
            backups = emptyList()
        }
    }

    // Show errors via Snackbar.
    LaunchedEffect(syncError) {
        syncError?.let {
            snackbarHostState.showSnackbar(it)
            GoogleDriveSyncManager.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.gdrive_title)) },
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
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            // ── Account section ──
            SyncSection(title = stringResource(R.string.gdrive_account)) {
                if (isLoggedIn) {
                    // Logged in — show email + sign out
                    SyncRow(
                        icon = Icons.Outlined.AccountCircle,
                        iconColor = Color(0xFF34C759),
                        title = email ?: stringResource(R.string.gdrive_signed_in),
                        subtitle = stringResource(R.string.gdrive_tap_to_sign_out),
                        onClick = {
                            oauthManager.logout()
                            isLoggedIn = false
                            email = null
                            GoogleDriveSyncManager.stopAutoSync()
                            backups = emptyList()
                        },
                        showDivider = false,
                    )
                } else {
                    // Not logged in — show sign in button
                    SyncRow(
                        icon = Icons.Outlined.AccountCircle,
                        iconColor = Color(0xFF007AFF),
                        title = stringResource(R.string.gdrive_not_signed_in),
                        subtitle = stringResource(R.string.gdrive_sign_in_to_sync),
                        onClick = {},
                        showDivider = false,
                    )
                    Spacer(Modifier.height(12.dp))
                    Button(
                        onClick = {
                            scope.launch {
                                oauthManager.startLogin { success ->
                                    if (success) {
                                        isLoggedIn = true
                                        email = oauthManager.email
                                    }
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp),
                    ) {
                        Icon(Icons.Outlined.Cloud, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.gdrive_sign_in_with_google))
                    }
                }
            }

            if (isLoggedIn) {
                // ── Sync section ──
                SyncSection(title = stringResource(R.string.gdrive_sync)) {
                    SyncRow(
                        icon = Icons.Outlined.Schedule,
                        iconColor = Color(0xFF007AFF),
                        title = stringResource(R.string.gdrive_last_sync),
                        subtitle = GoogleDriveSyncManager.formatDate(lastSyncTime),
                        onClick = {},
                    )
                    SyncRow(
                        icon = Icons.Outlined.CloudSync,
                        iconColor = Color(0xFF5856D6),
                        title = stringResource(R.string.gdrive_backups),
                        subtitle = stringResource(R.string.gdrive_backups_subtitle, backupCount, GoogleDriveSyncManager.formatSize(totalBackupSize)),
                        onClick = {},
                    )
                    Spacer(Modifier.height(12.dp))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        OutlinedButton(
                            onClick = {
                                scope.launch { GoogleDriveSyncManager.backup(oauthManager) }
                            },
                            enabled = !isSyncing,
                            modifier = Modifier.weight(1f),
                        ) {
                            if (isSyncing) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(16.dp),
                                    strokeWidth = 2.dp,
                                )
                            } else {
                                Icon(Icons.Outlined.Sync, contentDescription = null, modifier = Modifier.size(18.dp))
                            }
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.gdrive_backup_now))
                        }
                        OutlinedButton(
                            onClick = {
                                scope.launch { GoogleDriveSyncManager.restore(oauthManager) }
                            },
                            enabled = !isSyncing,
                            modifier = Modifier.weight(1f),
                        ) {
                            Icon(Icons.Outlined.Restore, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.gdrive_restore_latest))
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }

                // ── Auto Sync section ──
                SyncSection(title = stringResource(R.string.gdrive_auto_sync)) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                scope.launch {
                                    if (isAutoSyncEnabled) {
                                        GoogleDriveSyncManager.stopAutoSync()
                                    } else {
                                        GoogleDriveSyncManager.startAutoSync(oauthManager)
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
                                text = stringResource(R.string.gdrive_auto_sync),
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                            Text(
                                text = stringResource(R.string.gdrive_auto_sync_desc),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = isAutoSyncEnabled,
                            onCheckedChange = { enabled ->
                                scope.launch {
                                    if (enabled) {
                                        GoogleDriveSyncManager.startAutoSync(oauthManager)
                                    } else {
                                        GoogleDriveSyncManager.stopAutoSync()
                                    }
                                }
                            },
                        )
                    }
                }

                // ── Backups section ──
                SyncSection(title = stringResource(R.string.gdrive_backups)) {
                    if (backups.isEmpty()) {
                        Text(
                            text = stringResource(R.string.gdrive_no_backups),
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
                                SyncIcon(Icons.Outlined.Cloud, Color(0xFF007AFF))
                                Spacer(Modifier.width(14.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = backup.name.removePrefix("minis-backup-").removeSuffix(".zip"),
                                        style = MaterialTheme.typography.bodyLarge,
                                        color = MaterialTheme.colorScheme.onSurface,
                                    )
                                    val sizeText = backup.size?.let { GoogleDriveSyncManager.formatSize(it) } ?: stringResource(R.string.gdrive_unknown_size)
                                    val dateText = backup.modifiedTime?.take(10) ?: ""
                                    Text(
                                        text = if (dateText.isNotEmpty()) "$dateText - $sizeText" else sizeText,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Icon(
                                    Icons.Outlined.MoreVert,
                                    contentDescription = stringResource(R.string.gdrive_more_options),
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
    }

    // Long-press dropdown menu for each backup
    DropdownMenu(
        expanded = menuForBackup != null,
        onDismissRequest = { menuForBackup = null },
    ) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.gdrive_restore)) },
            onClick = {
                val backup = menuForBackup
                menuForBackup = null
                if (backup != null) {
                    confirmRestore = backup
                }
            },
            leadingIcon = { Icon(Icons.Outlined.Restore, contentDescription = null, modifier = Modifier.size(20.dp)) },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.delete)) },
            onClick = {
                val backup = menuForBackup
                menuForBackup = null
                if (backup != null) {
                    confirmDelete = backup
                }
            },
            leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(20.dp)) },
        )
    }

    // Restore confirmation dialog
    confirmRestore?.let { backup ->
        AlertDialog(
            onDismissRequest = { confirmRestore = null },
            title = { Text(stringResource(R.string.gdrive_restore_backup)) },
            text = { Text(stringResource(R.string.gdrive_restore_confirm, backup.name)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        val fileId = backup.id
                        confirmRestore = null
                        scope.launch {
                            GoogleDriveSyncManager.restoreFrom(oauthManager, fileId)
                        }
                    },
                ) { Text(stringResource(R.string.gdrive_restore)) }
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
            title = { Text(stringResource(R.string.gdrive_delete_backup)) },
            text = { Text(stringResource(R.string.gdrive_delete_confirm, backup.name)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        val fileId = backup.id
                        confirmDelete = null
                        scope.launch {
                            GoogleDriveSyncManager.deleteBackup(oauthManager, fileId)
                            backups = GoogleDriveSyncManager.listBackups(oauthManager)
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

// ── Local UI components (mirror SettingsScreen's SettingsSection / SettingsItem) ──

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
    icon: ImageVector,
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
private fun SyncIcon(icon: ImageVector, color: Color) {
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
