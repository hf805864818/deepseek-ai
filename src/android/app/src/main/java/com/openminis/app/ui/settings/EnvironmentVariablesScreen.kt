package com.openminis.app.ui.settings

import com.openminis.app.R
import com.openminis.app.ui.components.DialogTextField
import com.openminis.app.ui.components.MinisTextButton

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.stringResource
import com.openminis.app.data.repository.EnvProfileRepository
import com.openminis.app.data.repository.EnvVarRepository
import com.openminis.app.deeplink.DeepLinkCoordinator

/**
 * Environment Variables \u2014 adopts the SettingsScaffold/SettingsSection
 * toolkit (T80). One section stringResource(R.string.env_var_section_header) carrying every defined key/
 * value pair as a SettingsRow, with the visibility/copy/delete actions
 * in each row's trailing slot. Add affordance lives in the top-bar
 * `actions` slot (T75-part1 already moved it off the FAB).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EnvironmentVariablesScreen(
    envVarRepository: EnvVarRepository,
    envProfileRepository: EnvProfileRepository,
    onBack: () -> Unit,
) {
    val entries by envVarRepository.entries.collectAsState()
    val profiles by envProfileRepository.profiles.collectAsState()
    // T-env-profiles-tab: 0 = Global (existing env-var list), 1 = Profiles
    // (config集 list). The top-bar + action switches behavior per tab.
    var selectedTab by remember { mutableStateOf(0) }
    var showAddSheet by remember { mutableStateOf(false) }
    var editEntryId by remember { mutableStateOf<String?>(null) }
    var deleteEntryId by remember { mutableStateOf<String?>(null) }
    // Profile-list state mirroring the global var flow above: add sheet,
    // long-press delete target, and the tapped detail overlay (tracked by id
    // so the live profile is rederived from the `profiles` flow).
    var showAddProfileSheet by remember { mutableStateOf(false) }
    var deleteProfile by remember { mutableStateOf<EnvProfileRepository.EnvProfile?>(null) }
    var selectedProfileId by remember { mutableStateOf<String?>(null) }
    // iOS parity (AIChatView.swift L1410-1411): when a deep link arrives
    // with `create_key`, the env screen should open with a prefilled Add
    // sheet so the user only has to paste the value.
    var prefill by remember { mutableStateOf<DeepLinkCoordinator.EnvVarCreate?>(null) }
    val visibleKeys = remember { mutableStateOf(setOf<String>()) }
    val clipboardManager = LocalClipboardManager.current

    LaunchedEffect(Unit) {
        DeepLinkCoordinator.consumePendingEnvVarCreate()?.let {
            prefill = it
            // Deep link always targets a global variable, so land on the
            // Global tab even if the user last viewed Profiles.
            selectedTab = 0
            showAddSheet = true
        }
    }

    val privacyEnabled by com.openminis.app.data.EnvVarPrivacyStore.enabled.collectAsState()

    SettingsScaffold(
        title = stringResource(R.string.env_var_title),
        onBack = onBack,
        // T75-part1 moved Add off a FAB onto the top-bar action slot;
        // kept here for visual continuity. The + now branches on the
        // active tab: Global → add a variable, Profiles → add a profile.
        actions = {
            IconButton(onClick = {
                if (selectedTab == 0) showAddSheet = true else showAddProfileSheet = true
            }) {
                Icon(Icons.Default.Add, contentDescription = stringResource(R.string.env_var_add))
            }
        },
    ) {
        TabRow(selectedTabIndex = selectedTab) {
            Tab(
                selected = selectedTab == 0,
                onClick = { selectedTab = 0 },
                text = { Text(stringResource(R.string.env_tab_global)) },
            )
            Tab(
                selected = selectedTab == 1,
                onClick = { selectedTab = 1 },
                text = { Text(stringResource(R.string.env_tab_profiles)) },
            )
        }
        Spacer(Modifier.height(8.dp))

        if (selectedTab == 0) {
        SettingsSection(
            header = stringResource(R.string.env_var_privacy_header),
            footer = stringResource(R.string.env_var_privacy_footer),
        ) {
            SettingsSwitchRow(
                title = stringResource(R.string.env_var_privacy_toggle),
                checked = privacyEnabled,
                onCheckedChange = { com.openminis.app.data.EnvVarPrivacyStore.setEnabled(it) },
                showDivider = false,
            )
        }

        SettingsSection(
            header = stringResource(R.string.env_var_section_header),
            footer = stringResource(R.string.env_var_section_footer),
        ) {
            if (entries.isEmpty()) {
                // Centred empty-state message inside the same card so the
                // section visually owns it (instead of an empty card +
                // separately-positioned text block).
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 24.dp),
                    horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally,
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
                entries.forEachIndexed { index, entry ->
                    val isVisible = entry.key in visibleKeys.value
                    val displayValue = if (isVisible) {
                        envVarRepository.getValue(entry.key) ?: ""
                    } else {
                        "\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022"
                    }
                    // iOS parity (EnvironmentVariablesView.swift:139-151): show
                    // value on one line and the optional note on a second.
                    // SettingsRow only has one subtitle slot, so concatenate
                    // with a newline; both render in the same secondary style.
                    val subtitleText = if (entry.note.isNotEmpty()) {
                        "$displayValue\n${entry.note}"
                    } else {
                        displayValue
                    }
                    SettingsRow(
                        title = entry.key,
                        subtitle = subtitleText,
                        showChevron = false,
                        showDivider = index < entries.size - 1,
                        onClick = { editEntryId = entry.id },
                        trailing = {
                            Row {
                                IconButton(onClick = {
                                    visibleKeys.value = if (isVisible)
                                        visibleKeys.value - entry.key
                                    else
                                        visibleKeys.value + entry.key
                                }) {
                                    Icon(
                                        if (isVisible) Icons.Default.Visibility else Icons.Default.VisibilityOff,
                                        contentDescription = stringResource(R.string.env_var_toggle_visibility),
                                        modifier = Modifier.size(20.dp),
                                    )
                                }
                                IconButton(onClick = {
                                    val v = envVarRepository.getValue(entry.key) ?: ""
                                    clipboardManager.setText(AnnotatedString("${entry.key}=$v"))
                                }) {
                                    Icon(
                                        Icons.Default.ContentCopy,
                                        contentDescription = stringResource(R.string.common_copy),
                                        modifier = Modifier.size(20.dp),
                                    )
                                }
                                IconButton(onClick = { deleteEntryId = entry.id }) {
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
            }
        }
        } else {
            // Profiles tab — embed the same list rendering the standalone
            // EnvProfileScreen uses (EnvProfileListSection), so tap/long-press
            // behavior is identical. Tap opens the var detail overlay; long
            // press prompts delete.
            EnvProfileListSection(
                profiles = profiles,
                onProfileClick = { selectedProfileId = it.id },
                onProfileLongClick = { deleteProfile = it },
                onProfileDelete = { deleteProfile = it },
            )
        }

        Spacer(Modifier.height(24.dp))
    }

    // Add/Edit sheet
    if (showAddSheet || editEntryId != null) {
        val editing = editEntryId?.let { id -> entries.find { it.id == id } }
        EnvVarFormSheet(
            editEntry = editing,
            prefillKey = prefill?.key.orEmpty(),
            prefillValue = prefill?.value.orEmpty(),
            prefillNote = prefill?.note.orEmpty(),
            envVarRepository = envVarRepository,
            onDismiss = {
                showAddSheet = false
                editEntryId = null
                prefill = null
            },
        )
    }

    // Delete confirmation
    if (deleteEntryId != null) {
        val entry = entries.find { it.id == deleteEntryId }
        AlertDialog(
            onDismissRequest = { deleteEntryId = null },
            title = { Text(stringResource(R.string.env_var_delete_confirm_title, entry?.key ?: "variable")) },
            text = { Text(stringResource(R.string.env_var_delete_confirm_text)) },
            confirmButton = {
                MinisTextButton(onClick = {
                    deleteEntryId?.let { envVarRepository.delete(it) }
                    deleteEntryId = null
                }) {
                    Text(stringResource(R.string.common_delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                MinisTextButton(onClick = { deleteEntryId = null }) {
                    Text(stringResource(R.string.common_cancel))
                }
            },
        )
    }

    // Profile add sheet (Profiles tab + action). Editing a profile's own
    // metadata (name / icon / set-as-default) is done from the
    // EnvProfileVarsScreen detail overlay below, so this list only opens the
    // sheet in create mode.
    if (showAddProfileSheet) {
        EnvProfileFormSheet(
            editProfile = null,
            repository = envProfileRepository,
            onDismiss = { showAddProfileSheet = false },
        )
    }

    // Profile long-press delete confirmation.
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

    // Profile variable detail overlay. Rendered last so it paints over the
    // tab UI; clearing the selection simply stops drawing it and returns to
    // the Profiles tab with the list still composed underneath. The profile
    // is rederived from the live `profiles` flow so a rename done inside the
    // detail surfaces here too, and deleting the profile closes the overlay.
    selectedProfileId?.let { id ->
        profiles.firstOrNull { it.id == id }
    }?.let { profile ->
        EnvProfileVarsScreen(
            profile = profile,
            repository = envProfileRepository,
            onBack = { selectedProfileId = null },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EnvVarFormSheet(
    editEntry: EnvVarRepository.EnvVarEntry?,
    envVarRepository: EnvVarRepository,
    onDismiss: () -> Unit,
    prefillKey: String = "",
    prefillValue: String = "",
    prefillNote: String = "",
) {
    val sheetState = rememberModalBottomSheetState()
    var keyText by remember { mutableStateOf(editEntry?.key ?: prefillKey) }
    var valueText by remember {
        mutableStateOf(editEntry?.let { envVarRepository.getValue(it.key) } ?: prefillValue)
    }
    var noteText by remember { mutableStateOf(editEntry?.note ?: prefillNote) }

    val isEditing = editEntry != null
    val normalizedKey = keyText.trim().uppercase()
    val isValid = envVarRepository.isValidKey(normalizedKey)
    val isDuplicate = envVarRepository.isDuplicateKey(normalizedKey, excludeId = editEntry?.id)
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
                text = if (isEditing) stringResource(R.string.env_var_form_edit_title) else stringResource(R.string.env_var_form_add_title),
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

            // iOS parity: optional human-readable note explaining what the
            // variable is for. Stored alongside the metadata, surfaced in the
            // list row below the value.
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
                            envVarRepository.update(editEntry!!.id, keyText, valueText, noteText)
                        } else {
                            envVarRepository.add(keyText, valueText, noteText)
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
