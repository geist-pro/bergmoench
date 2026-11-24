// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kartei.Course
import app.kartei.CourseCatalogue
import app.kartei.DeckStore
import app.kartei.Insights
import app.kartei.Phase
import app.kartei.StudyPrefs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * First run: welcome with one honest note on spacing, which course decks to bring in (or your own .apkg), Simple or Full,
 * new cards a day (default 10) with the workload it settles at, then five hand-picked cards. Skippable from every page.
 */
@Composable
fun OnboardingScreen(store: DeckStore, prefs: StudyPrefs, startFirstSession: (Long) -> Unit = {}) {
    var page by remember { mutableStateOf(0) }
    var newPerDay by remember { mutableStateOf(Insights.NEW_PER_DAY_DEFAULT) }
    var finishing by remember { mutableStateOf(false) }
    var chosen by remember { mutableStateOf(setOf<String>()) }
    var importing by remember { mutableStateOf(false) }
    val chosenCourses = CourseCatalogue.all.filter { it.id in chosen }
    val firstCourse = CourseCatalogue.firstSessionCourse(chosenCourses)
    val scope = rememberCoroutineScope()
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) store.importCourses(chosenCourses) { store.importPackage(uri) }
    }
    fun finish(firstSession: Boolean = false) {
        if (finishing) return
        finishing = true
        val course = if (firstSession) firstCourse else null
        scope.launch {
            store.applyOnboardingPace(newPerDay)
            val deck = course?.let { c -> store.backend?.let { b -> withContext(Dispatchers.IO) { CourseCatalogue.makeFirstSession(b, c) } } }
            store.refresh()
            prefs.finishOnboarding()
            deck?.let(startFirstSession)
        }
    }
    BackHandler(enabled = page > 0) { page-- }

    Column(Modifier.fillMaxSize().background(Ink.bg).systemBarsPadding().imePadding().padding(horizontal = 20.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f).semantics(mergeDescendants = true) { contentDescription = "Step ${page + 1} of 3" }, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (i in 0..2) Box(Modifier.size(8.dp).background(if (i <= page) Ink.text else Ink.control, CircleShape))
            }
            if (page < 2) KLink("Skip", color = Ink.muted) { finish() }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            when (page) {
                0 -> Welcome()
                1 -> Cards(store, chosen, toggle = { id -> chosen = if (id in chosen) chosen - id else chosen + id }) {
                    picker.launch(arrayOf("application/octet-stream", "application/zip", "application/apkg", "*/*"))
                }
                else -> Setup(prefs, newPerDay, store.secondsPerCard) { newPerDay = it }
            }
        }
        Spacer(Modifier.height(12.dp))
        when (page) {
            0 -> KButton("Next") { page = 1 }
            1 -> when {
                importing -> KButton(store.importMessage ?: "Importing…", enabled = false) {}
                chosen.isEmpty() -> KButton("Continue without a course", primary = false) { page = 2 }
                else -> KButton(if (chosen.size == 1) "Add this course" else "Add ${chosen.size} courses") {
                    importing = true
                    // A failed import stays on this page, where its message is shown.
                    store.importCourses(chosenCourses) { added -> importing = false; if (added > 0 || store.rows.isNotEmpty()) page = 2 }
                }
            }
            else -> if (firstCourse != null && store.rows.isNotEmpty()) {
                KButton(if (finishing) "Starting…" else "Start with five cards", enabled = !finishing,
                    trailing = if (newPerDay > 0) "then $newPerDay a day" else null) { finish(firstSession = true) }
            } else {
                KButton(if (finishing) "Starting…" else "Start with $newPerDay new a day", enabled = !finishing,
                    trailing = "≈${Insights.minutesFor(Insights.steadyReviews(newPerDay), store.secondsPerCard)} min a day") { finish() }
            }
        }
        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun Welcome() {
    BasicText("Bergmönch", style = kDisplay(56, true, Ink.display), modifier = Modifier.padding(top = 24.dp).semantics { heading() })
    BasicText("Flashcards that come back just before you'd forget them.", style = kDisplay(26, false).copy(lineHeight = 31.sp), modifier = Modifier.padding(top = 8.dp))
    Spacer(Modifier.height(28.dp))
    BasicText("Why the gaps grow", style = kBody(16, 700))
    BasicText(
        "A card you know comes back later each time: tomorrow, in 3 days, in 8, in 3 weeks. Recalling it just as it starts to fade " +
            "is what makes it last, so a little effort at the right moment beats a lot of rereading.",
        style = kBody(16, color = Ink.muted).copy(lineHeight = 23.sp), modifier = Modifier.padding(top = 4.dp),
    )
    Spacer(Modifier.height(16.dp))
    BasicText("Bergmönch runs Anki's own scheduler, so your decks and review history work the same here.", style = kBody(14, color = Ink.muted))
}

@Composable
private fun Cards(store: DeckStore, chosen: Set<String>, toggle: (String) -> Unit, pick: () -> Unit) {
    BasicText("Which course are you taking?", style = kDisplay(30, true, Ink.display).copy(lineHeight = 35.sp),
        modifier = Modifier.padding(top = 24.dp, bottom = 8.dp).semantics { heading() })
    BasicText("Tick one or more. The cards follow the lectures. You can add the others later from the Decks tab.", style = kBody(15, color = Ink.muted))
    Spacer(Modifier.height(12.dp))
    for (course in CourseCatalogue.all) KCheck(course.title, course.detail, course.id in chosen) { toggle(course.id) }
    Spacer(Modifier.height(20.dp))
    BasicText("Your own cards", style = kBody(13, 500, Ink.muted))
    Spacer(Modifier.height(6.dp))
    KButton("Import an Anki deck", primary = false, trailing = ".apkg", onClick = pick)
    store.importMessage?.let { BasicText(it, style = kBody(14), modifier = Modifier.padding(top = 10.dp)) }
}

@Composable
private fun Setup(prefs: StudyPrefs, newPerDay: Int, secondsPerCard: Double, onNew: (Int) -> Unit) {
    BasicText("How much do you want to see?", style = kDisplay(28, true, Ink.display).copy(lineHeight = 32.sp), modifier = Modifier.padding(top = 24.dp, bottom = 8.dp).semantics { heading() })
    DetailChoice(prefs)
    KCaption("Two buttons schedule as accurately as four. You can change this in Settings.", Modifier.padding(top = 4.dp))
    Spacer(Modifier.height(24.dp))
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            BasicText("New cards a day", style = kBody(16, 700))
            BasicText(Insights.newCardsLine(newPerDay, secondsPerCard), style = kBody(14, color = Ink.muted))
        }
        KStepper(newPerDay, 0..100, label = "new cards a day", onChange = onNew)
    }
    KCaption("New cards are what make the pile grow later, so start small and add more once the daily time feels right.", Modifier.padding(top = 12.dp))
}
