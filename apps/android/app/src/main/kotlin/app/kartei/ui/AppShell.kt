// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kartei.DeckStore
import app.kartei.FirstRunDefaults
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import app.kartei.Phase
import app.kartei.Reach
import app.kartei.ReviewSession
import app.kartei.StudyPrefs
import app.kartei.ThemePrefs

enum class Tab(val label: String) { Decks("Decks"), Browse("Browse"), Stats("Stats"), Settings("Settings") }

/** Top-level navigation: onboarding on first run, otherwise the four tabs, and the review screen over everything. */
@Composable
fun AppShell(store: DeckStore, theme: ThemePrefs) {
    val prefs = remember { StudyPrefs() }
    var tab by remember { mutableStateOf(Tab.Decks) }
    var session by remember { mutableStateOf<ReviewSession?>(null) }
    var firstSessionDeck by remember { mutableStateOf<Long?>(null) }
    LaunchedEffect(store.phase) { if (store.phase == Phase.Ready && !prefs.loaded) store.backend?.let { prefs.load(it) } }
    // Once onboarded (or for collections that skip it), switch FSRS on a single time.
    LaunchedEffect(prefs.loaded, prefs.onboarded) {
        val backend = store.backend
        if (prefs.loaded && prefs.onboarded && backend != null) withContext(Dispatchers.IO) { FirstRunDefaults.enableFsrsOnce(backend) }
    }
    LaunchedEffect(store.rows, store.studiedDays) { Reach.storeDidUpdate(store) }
    // A guided first session that was cut short leaves its filtered deck behind; send its cards home.
    LaunchedEffect(store.rows, session) {
        val backend = store.backend ?: return@LaunchedEffect
        if (session != null || firstSessionDeck != null) return@LaunchedEffect
        val leftover = app.kartei.CourseCatalogue.leftoverFirstSessions(store.rows)
        if (leftover.isEmpty()) return@LaunchedEffect
        withContext(Dispatchers.IO) { leftover.forEach { app.kartei.CourseCatalogue.removeFirstSession(backend, it) } }
        store.refresh()
    }

    val current = session
    when {
        current != null -> {
            val close = {
                session = null
                val deck = firstSessionDeck
                val backend = store.backend
                if (deck != null && backend != null) {
                    firstSessionDeck = null
                    Thread { app.kartei.CourseCatalogue.removeFirstSession(backend, deck); store.refresh() }.start()
                } else {
                    store.refresh()
                }
            }
            BackHandler(onBack = close)
            ReviewScreen(current, store.mediaFolder, prefs, close)
        }
        prefs.loaded && !prefs.onboarded -> OnboardingScreen(store, prefs) { deck ->
            store.backend?.let { firstSessionDeck = deck; session = ReviewSession(it, deck, app.kartei.CourseCatalogue.FIRST_SESSION_NAME, store.examDates, store.langFor(deck)) }
        }
        else -> Column(Modifier.fillMaxSize().background(Ink.bg)) {
            Box(Modifier.weight(1f)) {
                when (tab) {
                    Tab.Decks -> HomeScreen(store) { row -> store.backend?.let { session = ReviewSession(it, row.id, row.name, store.examDates, store.langFor(row.id)) } }
                    Tab.Browse -> BrowseScreen(store)
                    Tab.Stats -> StatsScreen(store)
                    Tab.Settings -> SettingsScreen(store, prefs, theme)
                }
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(Ink.rule))
            // Four labels share the width, so they stop growing at 1.5 times: beyond that "Settings" would break mid-word.
            val scale = LocalDensity.current.fontScale
            val labelSize = (13f * minOf(scale, 1.5f) / scale).sp
            Row(Modifier.navigationBarsPadding().height(IntrinsicSize.Min)) {
                for (t in Tab.entries) {
                    val on = t == tab
                    Box(Modifier.weight(1f).fillMaxHeight().heightIn(min = 48.dp).semantics { selected = on }.clickable(role = Role.Tab) { tab = t }, contentAlignment = Alignment.Center) {
                        if (on) Box(Modifier.align(Alignment.TopCenter).fillMaxWidth().height(2.dp).background(Ink.text))
                        BasicText(t.label, maxLines = 1, modifier = Modifier.padding(vertical = 8.dp),
                            style = TextStyle(fontFamily = Type.body, fontSize = labelSize, fontWeight = FontWeight(if (on) 700 else 500), color = if (on) Ink.text else Ink.muted))
                    }
                }
            }
        }
    }
}
