// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kartei.DeckStore
import app.kartei.StudyPrefs
import app.kartei.ThemePrefs

/**
 * Settings: each section lives in its own file (AppearanceSection, ReadingSection, StudySection, PaceSection,
 * RemindersSection, SyncSection). Reading is a row here that opens its own page.
 */
@Composable
fun SettingsScreen(store: DeckStore, prefs: StudyPrefs, theme: ThemePrefs) {
    // Remembered above the page switch, so coming back from Reading lands where the list was.
    val scroll = rememberScrollState()
    var reading by remember { mutableStateOf(false) }
    if (reading) {
        ReadingScreen(store) { reading = false }
        return
    }
    Column(Modifier.fillMaxSize().background(Ink.bg).systemBarsPadding().imePadding().verticalScroll(scroll).padding(horizontal = 20.dp)) {
        BasicText("Settings", style = TextStyle(fontFamily = Type.display, fontSize = 34.sp, fontWeight = FontWeight(800), color = Ink.display), modifier = Modifier.padding(top = 12.dp, bottom = 16.dp))
        AppearanceSection(store, theme)
        ReadingSection { reading = true }
        StudySection(store, prefs)
        TouchSection(prefs)
        PaceSection(store)
        RemindersSection(store)
        SyncSection(store)
    }
}
