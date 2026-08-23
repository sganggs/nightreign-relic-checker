package com.nightreign.relicchecker.ui

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.nightreign.relicchecker.rules.CheckMode
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.nightreignSettings by preferencesDataStore(name = "nightreign_settings")

data class UserSettings(
    val defaultMode: CheckMode = CheckMode.CURRENT_NORMAL,
    val autoInspect: Boolean = true,
    val selectorShowUnavailable: Boolean = false,
    val libraryCompact: Boolean = false,
)

class SettingsRepository(private val context: Context) {
    val settings: Flow<UserSettings> = context.nightreignSettings.data.map { preferences ->
        UserSettings(
            defaultMode = preferences[Keys.DefaultMode]
                ?.let { stored -> CheckMode.entries.firstOrNull { it.name == stored } }
                ?: CheckMode.CURRENT_NORMAL,
            autoInspect = preferences[Keys.AutoInspect] ?: true,
            selectorShowUnavailable = preferences[Keys.SelectorShowUnavailable] ?: false,
            libraryCompact = preferences[Keys.LibraryCompact] ?: false,
        )
    }

    suspend fun setDefaultMode(mode: CheckMode) = update(Keys.DefaultMode, mode.name)
    suspend fun setAutoInspect(enabled: Boolean) = update(Keys.AutoInspect, enabled)
    suspend fun setSelectorShowUnavailable(enabled: Boolean) =
        update(Keys.SelectorShowUnavailable, enabled)
    suspend fun setLibraryCompact(enabled: Boolean) = update(Keys.LibraryCompact, enabled)

    private suspend fun <T> update(key: Preferences.Key<T>, value: T) {
        context.nightreignSettings.edit { preferences -> preferences[key] = value }
    }

    private object Keys {
        val DefaultMode = stringPreferencesKey("settings.default_mode")
        val AutoInspect = booleanPreferencesKey("settings.auto_inspect")
        val SelectorShowUnavailable =
            booleanPreferencesKey("settings.selector_show_unavailable")
        val LibraryCompact = booleanPreferencesKey("settings.library_compact")
    }
}
