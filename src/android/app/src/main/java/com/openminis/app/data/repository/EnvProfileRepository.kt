package com.openminis.app.data.repository

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * Manages environment variable profiles (配置集).
 * Each profile groups a set of env vars; profile vars override global vars
 * when resolved for shell injection. Mirrors iOS EnvProfileStore.
 *
 * Storage layout:
 * - Metadata: env-profiles.json (profiles) + env-profile-vars.json (vars)
 * - Values: EncryptedSharedPreferences with key prefix "profile:<profileId>:<key>"
 */
class EnvProfileRepository(private val context: Context) {

    companion object {
        private const val TAG = "EnvProfileRepository"
        private const val PROFILES_FILE = "env-profiles.json"
        private const val VARS_FILE = "env-profile-vars.json"
        private const val ENCRYPTED_PREFS_NAME = "env_var_values"
        private val KEY_REGEX = Regex("^[A-Za-z][A-Za-z0-9_]*$")

        fun profileKey(profileId: String, key: String) = "profile:$profileId:$key"
    }

    data class EnvProfile(
        val id: String = UUID.randomUUID().toString(),
        val name: String,
        val icon: String? = null,
        val color: String? = null,
        val isDefault: Boolean = false,
        val createdAt: Long = System.currentTimeMillis(),
        val updatedAt: Long = System.currentTimeMillis(),
    )

    data class EnvProfileVar(
        val id: String = UUID.randomUUID().toString(),
        val profileId: String,
        val key: String,
        val note: String = "",
        val createdAt: Long = System.currentTimeMillis(),
        val updatedAt: Long = System.currentTimeMillis(),
    )

    private val _profiles = MutableStateFlow<List<EnvProfile>>(emptyList())
    val profiles: StateFlow<List<EnvProfile>> = _profiles.asStateFlow()

    private val _vars = MutableStateFlow<List<EnvProfileVar>>(emptyList())
    val vars: StateFlow<List<EnvProfileVar>> = _vars.asStateFlow()

    private val encryptedPrefs: SharedPreferences by lazy {
        com.openminis.app.util.EncryptedPrefsFactory.safeCreate(context, ENCRYPTED_PREFS_NAME)
    }

    private val profilesFile: File get() = File(context.filesDir, PROFILES_FILE)
    private val varsFile: File get() = File(context.filesDir, VARS_FILE)

    init {
        loadMetadata()
    }

    // -- Queries --

    val defaultProfile: EnvProfile? get() = _profiles.value.firstOrNull { it.isDefault }

    fun profile(id: String): EnvProfile? = _profiles.value.firstOrNull { it.id == id }

    fun vars(for profileId: String): List<EnvProfileVar> =
        _vars.value.filter { it.profileId == profileId }.sortedBy { it.key }

    fun value(profileId: String, key: String): String? =
        encryptedPrefs.getString(profileKey(profileId, key), null)

    // -- Validation --

    fun isValidKey(key: String): Boolean = KEY_REGEX.matches(key)

    private fun sanitizeValue(value: String): String =
        value.filter { ch -> val c = ch.code; (c in 0x20..0x7E) || c == 0x09 }

    fun isDuplicateKey(profileId: String, key: String, excludeId: String? = null): Boolean =
        _vars.value.any {
            it.profileId == profileId &&
            it.key.equals(key, ignoreCase = true) &&
            it.id != excludeId
        }

    // -- Profile CRUD --

    fun addProfile(name: String, icon: String? = null, isDefault: Boolean = false): Boolean {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return false
        val now = System.currentTimeMillis()
        val profile = EnvProfile(name = trimmed, icon = icon, isDefault = isDefault, createdAt = now, updatedAt = now)
        _profiles.value = _profiles.value + profile
        if (isDefault) {
            _profiles.value = _profiles.value.map { p -> if (p.id == profile.id) p else p.copy(isDefault = false) }
        }
        saveProfiles()
        Log.i(TAG, "Added profile: ${profile.name} (default=$isDefault)")
        return true
    }

    fun updateProfile(id: String, name: String, icon: String?, isDefault: Boolean): Boolean {
        val idx = _profiles.value.indexOfFirst { it.id == id }
        if (idx < 0) return false
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return false
        _profiles.value = _profiles.value.mapIndexed { i, p ->
            if (i == idx) p.copy(name = trimmed, icon = icon, isDefault = isDefault, updatedAt = System.currentTimeMillis())
            else if (isDefault) p.copy(isDefault = false)
            else p
        }
        saveProfiles()
        Log.i(TAG, "Updated profile: $trimmed (default=$isDefault)")
        return true
    }

    fun deleteProfile(id: String) {
        // Delete all vars for this profile
        val profileVars = _vars.value.filter { it.profileId == id }
        for (v in profileVars) {
            encryptedPrefs.edit().remove(profileKey(id, v.key)).apply()
        }
        _vars.value = _vars.value.filter { it.profileId != id }
        _profiles.value = _profiles.value.filter { it.id != id }
        saveProfiles()
        saveVars()
        Log.i(TAG, "Deleted profile id=$id (${profileVars.size} vars removed)")
    }

    // -- Var CRUD --

    fun addVar(profileId: String, key: String, value: String, note: String = ""): Boolean {
        val normalizedKey = key.trim().uppercase()
        if (!isValidKey(normalizedKey)) return false
        if (isDuplicateKey(profileId, normalizedKey)) return false
        val now = System.currentTimeMillis()
        val entry = EnvProfileVar(profileId = profileId, key = normalizedKey, note = note.trim(), createdAt = now, updatedAt = now)
        _vars.value = _vars.value + entry
        encryptedPrefs.edit().putString(profileKey(profileId, normalizedKey), sanitizeValue(value)).apply()
        saveVars()
        Log.i(TAG, "Added profile var: $normalizedKey to profile=$profileId")
        return true
    }

    fun updateVar(id: String, newKey: String, newValue: String, newNote: String = ""): Boolean {
        val normalizedKey = newKey.trim().uppercase()
        if (!isValidKey(normalizedKey)) return false
        val current = _vars.value.find { it.id == id } ?: return false
        if (isDuplicateKey(current.profileId, normalizedKey, excludeId = id)) return false
        if (current.key != normalizedKey) {
            encryptedPrefs.edit().remove(profileKey(current.profileId, current.key)).apply()
        }
        _vars.value = _vars.value.map {
            if (it.id == id) it.copy(key = normalizedKey, note = newNote.trim(), updatedAt = System.currentTimeMillis())
            else it
        }
        encryptedPrefs.edit().putString(profileKey(current.profileId, normalizedKey), sanitizeValue(newValue)).apply()
        saveVars()
        Log.i(TAG, "Updated profile var: ${current.key} -> $normalizedKey")
        return true
    }

    fun deleteVar(id: String) {
        val entry = _vars.value.find { it.id == id } ?: return
        encryptedPrefs.edit().remove(profileKey(entry.profileId, entry.key)).apply()
        _vars.value = _vars.value.filter { it.id != id }
        saveVars()
        Log.i(TAG, "Deleted profile var: ${entry.key}")
    }

    // -- Resolved env (global + profile, profile overrides global) --

    /**
     * Returns the resolved env vars: global vars merged with profile vars
     * (profile values override global values with the same key).
     * Pass null [profileId] for global-only.
     */
    fun resolvedEnv(
        profileId: String?,
        globalRepository: EnvVarRepository,
    ): Map<String, String> {
        val result = globalRepository.allAsDict().toMutableMap()
        if (profileId != null) {
            for (v in _vars.value.filter { it.profileId == profileId }) {
                val value = encryptedPrefs.getString(profileKey(profileId, v.key), null)
                if (value != null) {
                    result[v.key] = value
                }
            }
        }
        return result
    }

    // -- Metadata Persistence --

    private fun saveProfiles() {
        try {
            val array = JSONArray()
            for (p in _profiles.value) {
                val obj = JSONObject()
                obj.put("id", p.id)
                obj.put("name", p.name)
                if (!p.icon.isNullOrEmpty()) obj.put("icon", p.icon)
                if (!p.color.isNullOrEmpty()) obj.put("color", p.color)
                obj.put("isDefault", p.isDefault)
                obj.put("createdAt", p.createdAt)
                obj.put("updatedAt", p.updatedAt)
                array.put(obj)
            }
            profilesFile.writeText(array.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save profiles: ${e.message}")
        }
    }

    private fun saveVars() {
        try {
            val array = JSONArray()
            for (v in _vars.value) {
                val obj = JSONObject()
                obj.put("id", v.id)
                obj.put("profileId", v.profileId)
                obj.put("key", v.key)
                if (v.note.isNotEmpty()) obj.put("note", v.note)
                obj.put("createdAt", v.createdAt)
                obj.put("updatedAt", v.updatedAt)
                array.put(obj)
            }
            varsFile.writeText(array.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save vars: ${e.message}")
        }
    }

    private fun loadMetadata() {
        try {
            if (profilesFile.exists()) {
                val array = JSONArray(profilesFile.readText())
                val list = mutableListOf<EnvProfile>()
                for (i in 0 until array.length()) {
                    val o = array.getJSONObject(i)
                    list.add(EnvProfile(
                        id = o.optString("id", UUID.randomUUID().toString()),
                        name = o.optString("name", ""),
                        icon = if (o.has("icon")) o.getString("icon") else null,
                        color = if (o.has("color")) o.getString("color") else null,
                        isDefault = o.optBoolean("isDefault", false),
                        createdAt = o.optLong("createdAt", 0),
                        updatedAt = o.optLong("updatedAt", 0),
                    ))
                }
                _profiles.value = list
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load profiles: ${e.message}")
        }
        try {
            if (varsFile.exists()) {
                val array = JSONArray(varsFile.readText())
                val list = mutableListOf<EnvProfileVar>()
                for (i in 0 until array.length()) {
                    val o = array.getJSONObject(i)
                    list.add(EnvProfileVar(
                        id = o.optString("id", UUID.randomUUID().toString()),
                        profileId = o.optString("profileId", ""),
                        key = o.optString("key", ""),
                        note = o.optString("note", ""),
                        createdAt = o.optLong("createdAt", 0),
                        updatedAt = o.optLong("updatedAt", 0),
                    ))
                }
                _vars.value = list
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load vars: ${e.message}")
        }
    }
}
