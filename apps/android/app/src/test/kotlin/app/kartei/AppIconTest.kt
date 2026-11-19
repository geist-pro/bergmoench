// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AppIconTest {
    @Test fun exactlyOneLauncherIsEnabled() {
        for (choice in AppIcon.entries) {
            val states = AppIcon.states(choice)
            assertEquals(1, states.values.count { it })
            assertEquals(true, states[choice])
        }
    }

    @Test fun manifestDeclaresEveryAliasWithGeistAsDefault() {
        val manifest = File("src/main/AndroidManifest.xml").readText()
        for (icon in AppIcon.entries) assertTrue(icon.alias, manifest.contains("android:name=\"${icon.alias}\""))
        val geist = manifest.substringAfter("android:name=\".LauncherGeist\"").substringBefore(">")
        val gruvbox = manifest.substringAfter("android:name=\".LauncherGruvbox\"").substringBefore(">")
        assertTrue(geist.contains("android:enabled=\"true\""))
        assertTrue(gruvbox.contains("android:enabled=\"false\""))
    }

    @Test fun bothIconSetsExistAtEveryDensity() {
        for (d in listOf("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")) for (n in listOf("ic_launcher", "ic_launcher_gruvbox"))
            for (suffix in listOf("", "_foreground", "_background", "_monochrome"))
                assertTrue("$d/$n$suffix", File("src/main/res/mipmap-$d/$n$suffix.png").exists())
    }
}
