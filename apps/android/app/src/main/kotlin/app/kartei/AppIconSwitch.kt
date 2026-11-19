// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/**
 * The home-screen icon: Bergmönch "Mountain 1 · Range" in GEIST colours (default) or Gruvbox colours.
 * Each is a launcher activity-alias in the manifest; exactly one is enabled. Some launchers take a moment to redraw.
 */
enum class AppIcon(val alias: String, val label: String) {
    Geist(".LauncherGeist", "GEIST"),
    Gruvbox(".LauncherGruvbox", "Gruvbox");

    companion object {
        /** Which alias to enable for [choice], and which to disable; pure so it can be unit-tested. */
        fun states(choice: AppIcon): Map<AppIcon, Boolean> = entries.associateWith { it == choice }
    }
}

object AppIconSwitch {
    fun current(context: Context): AppIcon {
        val pm = context.packageManager
        return AppIcon.entries.firstOrNull { icon ->
            val state = pm.getComponentEnabledSetting(ComponentName(context.packageName, CODE_NAMESPACE + icon.alias))
            state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && icon == AppIcon.Geist)
        } ?: AppIcon.Geist
    }

    fun apply(context: Context, choice: AppIcon) {
        val pm = context.packageManager
        // Enable the new entry first, so there is never a moment without a launcher icon.
        for ((icon, on) in AppIcon.states(choice).entries.sortedByDescending { it.value }) {
            pm.setComponentEnabledSetting(
                ComponentName(context.packageName, CODE_NAMESPACE + icon.alias),
                if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}

/** Activity-alias names resolve against the code namespace (app.kartei), not the applicationId (pro.geist.bergmoench). */
internal const val CODE_NAMESPACE = "app.kartei"
