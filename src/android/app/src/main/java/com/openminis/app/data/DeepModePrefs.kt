package com.openminis.app.data

import android.content.Context
import android.content.SharedPreferences
import com.openminis.app.agent.DeepModeLevel

/**
 * Global defaults for Deep Mode (深度龙虾Ai), persisted in SharedPreferences.
 *
 * Two-layer model (mirrors MemoryGlobalPrefs):
 *   - **Global** (this file): default for newly-created sessions.
 *     Toggled from Settings → Deep Mode.
 *   - **Per-session** (future: ChatSessionEntity column): override
 *     for a specific chat, toggled via `/deepmode` slash command.
 *
 * When a fresh draft VM is mounted before any DB row exists, we read
 * the global default and seed `_deepModeEnabled` with it.
 */
object DeepModePrefs {
    private const val PREFS = "minis_deepmode_prefs"
    private const val KEY_GLOBAL_ENABLED = "deepmode.global.enabled"
    private const val KEY_GLOBAL_LEVEL = "deepmode.global.level"

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isGlobalEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_GLOBAL_ENABLED, false)

    fun setGlobalEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_GLOBAL_ENABLED, enabled).apply()
    }

    fun globalLevel(context: Context): DeepModeLevel =
        DeepModeLevel.fromRaw(prefs(context).getString(KEY_GLOBAL_LEVEL, null))

    fun setGlobalLevel(context: Context, level: DeepModeLevel) {
        prefs(context).edit().putString(KEY_GLOBAL_LEVEL, level.rawValue).apply()
    }
}
