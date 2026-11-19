// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import android.content.Context
import android.content.res.Configuration
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.kartei.ui.Family
import app.kartei.ui.Mode
import app.kartei.ui.Palette
import app.kartei.ui.Palettes

/** The little storage ThemePrefs needs; SharedPreferences on the device, a map in tests. */
interface KeyValue {
    fun get(key: String): String?
    fun put(key: String, value: String)
}

/**
 * Look and mode, stored per device (SharedPreferences, not the collection): a phone and a tablet syncing one collection
 * may well want different modes. Defaults follow core/themes.json: GEIST, dark. Unknown stored values fall
 * back to the defaults.
 */
class ThemePrefs(private val store: KeyValue) {
    var family by mutableStateOf(Family.of(store.get(FAMILY_KEY)) ?: DEFAULT_FAMILY); private set
    var mode by mutableStateOf(Mode.of(store.get(MODE_KEY)) ?: DEFAULT_MODE); private set

    fun updateFamily(f: Family) { family = f; store.put(FAMILY_KEY, f.key) }
    fun updateMode(m: Mode) { mode = m; store.put(MODE_KEY, m.key) }

    fun isDark(systemDark: Boolean) = mode.isDark(systemDark)
    fun palette(systemDark: Boolean): Palette = Palettes.of(family, isDark(systemDark))

    companion object {
        val DEFAULT_FAMILY = Family.Geist
        val DEFAULT_MODE = Mode.Dark
        const val FILE = "kartei-appearance"
        const val FAMILY_KEY = "family"
        const val MODE_KEY = "mode"

        fun sharedPrefs(context: Context): KeyValue {
            val sp = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            return object : KeyValue {
                override fun get(key: String) = sp.getString(key, null)
                override fun put(key: String, value: String) { sp.edit().putString(key, value).apply() }
            }
        }

        fun of(context: Context) = ThemePrefs(sharedPrefs(context))

        fun systemDark(context: Context) =
            (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    }
}
