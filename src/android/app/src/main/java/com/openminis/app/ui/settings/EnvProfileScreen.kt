package com.openminis.app.ui.settings

import com.openminis.app.R
import com.openminis.app.data.repository.EnvProfileRepository
import com.openminis.app.ui.components.DialogTextField
import com.openminis.app.ui.components.MinisTextButton

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.hapticfeedback.LocalHapticFeedback
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.stringResource

/**
 * Environment variable *profiles* UI (配置集). Mirrors iOS EnvProfileStore.
 *
 * Three public surfaces:
 *  - [EnvProfileScreen]: standalone list page (TopAppBar + LazyColumn) with
 *    add (top-bar +), tap-to-open detail, and long-press-to-delete.
 *  - [EnvProfileVarsScreen]: per-profile variable detail page, reusing the
 *    same visible/copy/delete row style as [EnvironmentVariablesScreen], plus
 *    an edit action for the profile's own metadata.
 *  - [EnvProfileFormSheet]: ModalBottomSheet to create / edit a profile
 *    (name, icon, set-as-default, save / delete).
 *
 * [EnvProfileListSection] and [EnvProfileRow] are factored out so the
 * "Profiles" tab inside [EnvironmentVariablesScreen] can embed the same
 * list rendering instead of duplicating it.
 */

// ─── Icon catalog ─────────────────────────────────────────────────────────────

/**
 * Icon vocabulary for profiles. The [EnvProfileRepository.EnvProfile.icon]
 * string persists the selection across launches; [profileIcon] maps it back
 * to an [ImageVector] (falling back to [Icons.Default.Folder] for unknown /
 * null values).
 */
private data class ProfileIcon(val key: String, val vector: ImageVector)

private val PROFILE_ICONS: List<ProfileIcon> = listOf(
    ProfileIcon("work", Icons.Default.Work),
    ProfileIcon("person", Icons.Default.Person),
    ProfileIcon("home", Icons.Default.Home),
    ProfileIcon("school", Icons.Default.School),
    ProfileIcon("business", Icons.Default.Business),
    ProfileIcon("account", Icons.Default.AccountCircle),
)

private fun profileIcon(key: String?): ImageVector =
    PROFILE_ICONS.firstOrNull { it.key == key }?.vector ?: Icons.Default.Folder

// ─── Profile list page ─────────────────────────────────────────────────────────

/**
 * Standalone profiles list page. TopAppBar + LazyColumn of every profile,
 * with add (top-bar +), tap-to-open detail, and long-press-to-delete.
 *
 * The open detail is tracked by id (not by a captured snapshot) and the
 * live [EnvProfileRepository.EnvProfile] is rederived from the repo's
 * [EnvProfileRepository.profiles] flow on every recomposition — so a rename
 * / icon change made inside the detail page is reflected immediately, and
 * deleting the profile simply makes the overlay vanish.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EnvProfileScreen(
    envProfileRepository: EnvProfileRepository,
    onBack: () -> Unit,
) {
    val profiles by envProfileRepository.profiles.collectAsState()
    var showAddSheet by remember { mutableStateOf(false) }
    var deleteProfile by remember { mutableStateOf<EnvProfileRepository.EnvProfile?>(null) }
    var selectedProfileId by remember { mutableStateOf<String?>(null) }
    val haptics = LocalHapticFeedback.current

    // Rederive the selected profile from the live list so edits/deletes
    // propagate to the detail overlay without a stale snapshot.
    val selectedProfile = selectedProfileId?.let { id ->
        profiles.firstOrNull { it.id == id }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.env_profile_title), fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.common_back))
                    }
                },
                actions = {
                    IconButton(onClick = { showAddSheet = true }) {
                        Icon(Icons.Default.Add, contentDescription = stringResource(R.string.env_profile_add))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        if (profiles.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        stringResource(R.string.env_profile_empty_title),
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        stringResource(R.string.env_profile_empty_action),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) {
                itemsIndexed(profiles) { index, profile ->
                    val dismissState = rememberSwipeToDismissBoxState(
                        confirmValueChange = { value ->
                            if (value == SwipeToDismissBoxValue.EndToStart) {
                                deleteProfile = profile
                                true
                            } else {
                                false
                            }
                        },
                    )
                    SwipeToDismissBox(
                        state = dismissState,
                        backgroundContent = {
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .background(MaterialTheme.colorScheme.error)
                                    .padding(horizontal = 20.dp),
                                contentAlignment = Alignment.CenterEnd,
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Delete,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onError,
                                )
                            }
                        },
                    ) {
                        EnvProfileRow(
                            profile = profile,
                            onClick = { selectedProfileId = profile.id },
                            onLongClick = {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                deleteProfile = profile
                            },
                            showDivider = index < profiles.size - 1,
                        )
                    }
                }
            }
        }
    }

    // Create sheet (add mode only from this list; editing a profile is done
    // from its detail page).
    if (showAddSheet) {
        EnvProfileFormSheet(
            editProfile = null,
            repository = envProfileRepository,
            onDismiss = { showAddSheet = false },
        )
    }

    // Long-press delete confirmation.
    if (deleteProfile != null) {
        AlertDialog(
            onDismissRequest = { deleteProfile = null },
            title = { Text(stringResource(R.string.env_profile_delete_confirm_title, deleteProfile?.name ?: "profile")) },
            text = { Text(stringResource(R.string.env_profile_delete_confirm_text)) },
            confirmButton = {
                MinisTextButton(onClick = {
                    deleteProfile?.let { envProfileRepository.deleteProfile(it.id) }
                    deleteProfile = null
                }) {
                    Text(stringResource(R.string.common_delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                MinisTextButton(onClick = { deleteProfile = null }) {
                    Text(stringResource(R.string.common_cancel))
                }
            },
        )
    }

    // Detail overlay (rendered last so it paints over the list). When the
    // profile is deleted, selectedProfile becomes null and the overlay
    // simply stops composing.
    selectedProfile?.let { profile ->
        EnvProfileVarsScreen(
            profile = profile,
            repository = envProfileRepository,
            onBack = { selectedProfileId = null },
        )
    }
}

// ─── Profile vars detail page ──────────────────────────────────────────────────

/**
 * Variables belonging to a single profile. Mirrors [EnvironmentVariablesScreen]'s
 * global-variable list: each row shows the key, a masked / revealed value
 * (tap eye to toggle), the optional note on a second line, and trailing
 * copy / delete actions. Tap a row to edit; + adds a new profile variable.
 * The top-bar edit action opens [EnvProfileFormSheet] to rename the profile,
 * change its icon, or toggle set-as-default.
 *
 * Uses the SettingsScaffold/SettingsSection toolkit so the row chrome is
 * pixel-identical to the global env-var screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EnvProfileVarsScreen(
    profile: EnvProfileRepository.EnvProfile,
    repository: EnvProfileRepository,
    onBack: () -> Unit,
) {
    val allVars by repository.vars.collectAsState()
    val profileVars = remember(profile.id, allVars) {
        allVars.filter { it.profileId == profile.id }.sortedBy { it.key }
    }
    var showAddVarSheet by remember { mutableStateOf(false) }
    var editVar by remember { mutableStateOf<EnvProfileRepository.EnvProfileVar?>(null) }
    var deleteVarId by remember { mutableStateOf<String?>(null) }
    var editProfile by remember { mutableStateOf(false) }
    val visibleKeys = remember { mutableStateOf(setOf<String>()) }
    val clipboardManager = LocalClipboardManager.current

    SettingsScaffold(
        title = profile.name,
        onBack = onBack,
        actions = {
            IconButton(onClick = { editProfile = true }) {
                Icon(Icons.Default.Edit, contentDescription = stringResource(R.string.common_edit))
            }
            IconButton(onClick = { showAddVarSheet = true }) {
                Icon(Icons.Default.Add, contentDescription = stringResource(R.string.env_var_add))
            }
        },
    ) {
        SettingsSection(
            header = stringResource(R.string.env_var_section_header),
            footer = stringResource(R.string.env_var_section_footer),
        ) {
            if (profileVars.isEmpty()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        stringResource(R.string.env_var_empty_title),
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        stringResource(R.string.env_var_empty_action),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                profileVars.forEachIndexed { index, entry ->
                    val isVisible = entry.key in visibleKeys.value
                    val displayValue = if (isVisible) {
                        repository.value(profile.id, entry.key) ?: ""
                    } else {
                        "\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022"
                    }
                    val subtitleText = if (entry.note.isNotEmpty()) {
                        "$displayValue\n${entry.note}"
                    } else {
                        displayValue
                    }
                    EnvVarEntryRow(
                        key = entry.key,
                        subtitle = subtitleText,
                        showDivider = index < profileVars.size - 1,
                        onClick = { editVar = entry },
                        onToggleVisibility = {
                            visibleKeys.value = if (isVisible)
                                visibleKeys.value - entry.key
                            else
                                visibleKeys.value + entry.key
                        },
                        onCopy = {
                            val v = repository.value(profile.id, entry.key) ?: ""
                            clipboardManager.setText(AnnotatedString("${entry.key}=$v"))
                        },
                        onDelete = { deleteVarId = entry.id },
                        isVisible = isVisible,
                    )
                }
            }
        }

        Spacer(Modifier.height(24.dp))
    }

    // Add / edit profile variable sheet.
    if (showAddVarSheet || editVar != null) {
        EnvProfileVarFormSheet(
            profileId = profile.id,
            editVar = editVar,
            repository = repository,
            onDismiss = {
                showAddVarSheet = false
                editVar = null
            },
        )
    }

    // Edit profile metadata (name / icon / set-as-default). The live
    // `profile` param is rederived by the caller from the repo's flow, so a
    // save here surfaces immediately as a fresh title.
    if (editProfile) {
        EnvProfileFormSheet(
            editProfile = profile,
            repository = repository,
            onDismiss = { editProfile = false },
        )
    }

    // Delete variable confirmation.
    if (deleteVarId != null) {
        val entry = profileVars.find { it.id == deleteVarId }
        AlertDialog(
            onDismissRequest = { deleteVarId = null },
            title = { Text(stringResource(R.string.env_var_delete_confirm_title, entry?.key ?: "variable")) },
            text = { Text(stringResource(R.string.env_var_delete_confirm_text)) },
            confirmButton = {
                MinisTextButton(onClick = {
                    deleteVarId?.let { repository.deleteVar(it) }
                    deleteVarId = null
                }) {
                    Text(stringResource(R.string.common_delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                MinisTextButton(onClick = { deleteVarId = null }) {
                    Text(stringResource(R.string.common_cancel))
                }
            },
        )
    }
}

// ─── Reusable list section (profiles) ──────────────────────────────────────────

/**
 * Inline grouped list of profiles — the "list part" of [EnvProfileScreen],
 * pulled out so the "Profiles" tab inside [EnvironmentVariablesScreen] can
 * embed the exact same rendering instead of duplicating it. Renders inside a
 * [SettingsSection] (grouped card), so it uses forEachIndexed rather than a
 * LazyColumn (the standalone [EnvProfileScreen] uses LazyColumn directly).
 */
@Composable
fun EnvProfileListSection(
    profiles: List<EnvProfileRepository.EnvProfile>,
    onProfileClick: (EnvProfileRepository.EnvProfile) -> Unit,
    onProfileLongClick: (EnvProfileRepository.EnvProfile) -> Unit,
    onProfileDelete: (EnvProfileRepository.EnvProfile) -> Unit,
    modifier: Modifier = Modifier,
) {
    SettingsSection(
        header = stringResource(R.string.env_profile_section_header),
        footer = stringResource(R.string.env_profile_section_footer),
        modifier = modifier,
    ) {
        if (profiles.isEmpty()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    stringResource(R.string.env_profile_empty_title),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    stringResource(R.string.env_profile_empty_action),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            profiles.forEachIndexed { index, profile ->
                val dismissState = rememberSwipeToDismissBoxState(
                    confirmValueChange = { value ->
                        if (value == SwipeToDismissBoxValue.EndToStart) {
                            onProfileDelete(profile)
                            true
                        } else {
                            false
                        }
                    },
                )
                SwipeToDismissBox(
                    state = dismissState,
                    backgroundContent = {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .background(MaterialTheme.colorScheme.error)
                                .padding(horizontal = 20.dp),
                            contentAlignment = Alignment.CenterEnd,
                        ) {
                            Icon(
                                imageVector = Icons.Default.Delete,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onError,
                            )
                        }
                    },
                ) {
                    EnvProfileRow(
                        profile = profile,
                        onClick = { onProfileClick(profile) },
                        onLongClick = { onProfileLongClick(profile) },
                        showDivider = index < profiles.size - 1,
                    )
                }
            }
        }
    }
}

/**
 * A single profile row: colored icon square, name, optional "Default" badge,
 * and a trailing chevron. Supports long-press (for delete) via
 * [combinedClickable]; mirrors [SettingsRow]'s geometry (30dp icon, 56dp
 * min height, inset divider) so it lines up with neighbouring settings rows.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun EnvProfileRow(
    profile: EnvProfileRepository.EnvProfile,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    showDivider: Boolean,
    modifier: Modifier = Modifier,
) {
    val icon = profileIcon(profile.icon)
    Column(modifier = modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .combinedClickable(onClick = onClick, onLongClick = onLongClick)
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(30.dp)
                    .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(8.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(18.dp),
                )
            }
            Spacer(Modifier.width(14.dp))
            Text(
                text = profile.name,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (profile.isDefault) {
                Surface(
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    shape = RoundedCornerShape(6.dp),
                ) {
                    Text(
                        stringResource(R.string.common_default),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                    )
                }
                Spacer(Modifier.width(8.dp))
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                modifier = Modifier.size(20.dp),
            )
        }
        if (showDivider) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 58.dp, end = 14.dp)
                    .height(0.5.dp)
                    .background(MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)),
            )
        }
    }
}

// ─── Reusable list row (variables) ─────────────────────────────────────────────

/**
 * One environment-variable row, factored out of [EnvironmentVariablesScreen]'s
 * inline rendering so [EnvProfileVarsScreen] can reuse the exact visible /
 * copy / delete trailing style. Backed by [SettingsRow] for chrome parity.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EnvVarEntryRow(
    key: String,
    subtitle: String,
    isVisible: Boolean,
    onToggleVisibility: () -> Unit,
    onCopy: () -> Unit,
    onDelete: () -> Unit,
    onClick: () -> Unit,
    showDivider: Boolean,
) {
    SettingsRow(
        title = key,
        subtitle = subtitle,
        showChevron = false,
        showDivider = showDivider,
        onClick = onClick,
        trailing = {
            Row {
                IconButton(onClick = onToggleVisibility) {
                    Icon(
                        if (isVisible) Icons.Default.Visibility else Icons.Default.VisibilityOff,
                        contentDescription = stringResource(R.string.env_var_toggle_visibility),
                        modifier = Modifier.size(20.dp),
                    )
                }
                IconButton(onClick = onCopy) {
                    Icon(
                        Icons.Default.ContentCopy,
                        contentDescription = stringResource(R.string.common_copy),
                        modifier = Modifier.size(20.dp),
                    )
                }
                IconButton(onClick = onDelete) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = stringResource(R.string.common_delete),
                        modifier = Modifier.size(20.dp),
                        tint = MaterialTheme.colorScheme.error,
                    )
                }
            }
        },
    )
}

// ─── Profile form sheet ────────────────────────────────────────────────────────

/**
 * ModalBottomSheet to create or edit a profile: name, icon picker, and a
 * set-as-default switch. Save commits via [EnvProfileRepository.addProfile]
 * / [EnvProfileRepository.updateProfile]; when editing, a destructive Delete
 * button is offered alongside Save.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun EnvProfileFormSheet(
    editProfile: EnvProfileRepository.EnvProfile?,
    repository: EnvProfileRepository,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState()
    var name by remember { mutableStateOf(editProfile?.name ?: "") }
    var iconKey by remember { mutableStateOf(editProfile?.icon ?: PROFILE_ICONS.first().key) }
    var isDefault by remember { mutableStateOf(editProfile?.isDefault ?: false) }

    val isEditing = editProfile != null
    val canSave = name.isNotBlank()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = if (isEditing) stringResource(R.string.env_profile_form_edit_title)
                else stringResource(R.string.env_profile_form_add_title),
                style = MaterialTheme.typography.titleMedium,
            )

            Text(
                text = stringResource(R.string.env_profile_name),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(6.dp))
            DialogTextField(
                value = name,
                onValueChange = { name = it },
                singleLine = true,
            )

            Text(
                text = stringResource(R.string.env_profile_icon),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(6.dp))
            // Icon picker — a single row of selectable tiles. Tapping a
            // tile updates iconKey; the selected tile inverts to the primary
            // tint so the choice is obvious at a glance.
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                PROFILE_ICONS.forEach { ic ->
                    val selected = ic.key == iconKey
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(
                                if (selected) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.surfaceContainerHigh
                            )
                            .combinedClickable(onClick = { iconKey = ic.key }),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = ic.vector,
                            contentDescription = ic.key,
                            tint = if (selected) Color.White
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }

            // Set-as-default switch, inlined (no card) so it aligns with
            // the sheet's 16dp horizontal padding instead of SettingsRow's
            // extra 14dp inset.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    stringResource(R.string.env_profile_set_default),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                )
                Switch(
                    checked = isDefault,
                    onCheckedChange = { isDefault = it },
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (isEditing) {
                    MinisTextButton(onClick = {
                        repository.deleteProfile(editProfile!!.id)
                        onDismiss()
                    }) {
                        Text(stringResource(R.string.common_delete), color = MaterialTheme.colorScheme.error)
                    }
                    Spacer(Modifier.width(4.dp))
                }
                MinisTextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.common_cancel))
                }
                MinisTextButton(
                    onClick = {
                        if (isEditing) {
                            repository.updateProfile(editProfile!!.id, name, iconKey, isDefault)
                        } else {
                            repository.addProfile(name, iconKey, isDefault)
                        }
                        onDismiss()
                    },
                    enabled = canSave,
                ) {
                    Text(if (isEditing) stringResource(R.string.common_save) else stringResource(R.string.env_profile_add))
                }
            }
        }
    }
}

// ─── Profile variable form sheet ───────────────────────────────────────────────

/**
 * ModalBottomSheet to add / edit a variable *inside* a profile. Mirrors
 * [EnvironmentVariablesScreen]'s `EnvVarFormSheet` (monospace key/value,
 * optional note, duplicate + invalid-key validation) but persists through
 * [EnvProfileRepository.addVar] / [EnvProfileRepository.updateVar] so the
 * value lands under the profile-scoped encrypted-prefs key.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EnvProfileVarFormSheet(
    profileId: String,
    editVar: EnvProfileRepository.EnvProfileVar?,
    repository: EnvProfileRepository,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState()
    var keyText by remember { mutableStateOf(editVar?.key ?: "") }
    var valueText by remember {
        mutableStateOf(editVar?.let { repository.value(it.profileId, it.key) } ?: "")
    }
    var noteText by remember { mutableStateOf(editVar?.note ?: "") }

    val isEditing = editVar != null
    val normalizedKey = keyText.trim().uppercase()
    val isValid = repository.isValidKey(normalizedKey)
    val isDuplicate = repository.isDuplicateKey(profileId, normalizedKey, excludeId = editVar?.id)
    val canSave = isValid && !isDuplicate && keyText.isNotBlank()

    val errorText = when {
        keyText.isNotBlank() && !isValid -> stringResource(R.string.env_var_error_invalid_key)
        isDuplicate -> stringResource(R.string.env_var_error_duplicate)
        else -> null
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = if (isEditing) stringResource(R.string.env_var_form_edit_title)
                else stringResource(R.string.env_var_form_add_title),
                style = MaterialTheme.typography.titleMedium,
            )

            Text(
                text = stringResource(R.string.env_var_field_name),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(6.dp))
            DialogTextField(
                value = keyText,
                onValueChange = { keyText = it.uppercase() },
                singleLine = true,
                isError = errorText != null,
                textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
            )
            if (errorText != null) {
                Spacer(Modifier.height(4.dp))
                Text(
                    text = errorText,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            Text(
                text = stringResource(R.string.env_var_field_value),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(6.dp))
            DialogTextField(
                value = valueText,
                onValueChange = { valueText = it },
                singleLine = false,
                maxLines = 3,
                textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
            )

            Text(
                text = stringResource(R.string.env_var_field_note),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(6.dp))
            DialogTextField(
                value = noteText,
                onValueChange = { noteText = it },
                placeholder = stringResource(R.string.env_var_field_note_placeholder),
                singleLine = true,
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
            ) {
                MinisTextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.common_cancel))
                }
                MinisTextButton(
                    onClick = {
                        val success = if (isEditing) {
                            repository.updateVar(editVar!!.id, keyText, valueText, noteText)
                        } else {
                            repository.addVar(profileId, keyText, valueText, noteText)
                        }
                        if (success) onDismiss()
                    },
                    enabled = canSave,
                ) {
                    Text(if (isEditing) stringResource(R.string.common_save) else stringResource(R.string.env_var_add))
                }
            }
        }
    }
}
