// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import app.kartei.ui.AppShell
import app.kartei.ui.ThemeState

class MainActivity : ComponentActivity() {
    private val store: DeckStore by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        val theme = ThemePrefs.of(this)
        // Reading it applies "Stronger contrast" to ThemeState before the first frame.
        ReadingPrefs.of(this)
        // Before the first frame: bars and window background already in the chosen look (values-night covers the launch window).
        applyWindow(theme.family, theme.isDark(ThemePrefs.systemDark(this)))
        super.onCreate(savedInstanceState)
        setContent {
            val prefs = remember { theme }
            val dark = prefs.isDark(isSystemInDarkTheme())
            ThemeState.apply(prefs.family, dark)
            DisposableEffect(prefs.family, dark) {
                applyWindow(prefs.family, dark)
                onDispose {}
            }
            AppShell(store, prefs)
        }
    }

    private fun applyWindow(family: app.kartei.ui.Family, dark: Boolean) {
        ThemeState.apply(family, dark)
        val bg = ThemeState.palette.bg.toInt()
        val transparent = android.graphics.Color.TRANSPARENT
        // Edge to edge with transparent bars; only the icon colour follows the mode.
        val style = if (dark) SystemBarStyle.dark(transparent) else SystemBarStyle.light(transparent, transparent)
        enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
        window.setBackgroundDrawable(ColorDrawable(bg))
    }
}
