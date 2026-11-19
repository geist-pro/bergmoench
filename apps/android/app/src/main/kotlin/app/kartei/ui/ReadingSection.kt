// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kartei.DeckStore
import app.kartei.ReadingPrefs
import kotlin.math.roundToInt

/** Settings › Reading as a row in the settings list: the current card text size, and the way into [ReadingScreen]. */
@Composable
fun ReadingSection(open: () -> Unit) {
    val reading = ReadingPrefs.of(LocalContext.current)
    Column {
        KSectionHead("Reading")
        KFact("Card text, contrast, language", ReadingPrefs.STEP_NAMES[reading.cardStep],
            sub = if (reading.strongContrast) "Stronger contrast is on" else "Saved on this phone only", onClick = open)
    }
}

/** How a deck's language is offered: no entry (the device's voice), or one of the two the courses come in. */
private val LANGUAGES = listOf(null to "Automatic", "de" to "Deutsch", "en" to "English")

/**
 * The Reading page (mockups/a11y, mockup 5): card text size with a live preview, regular-weight questions, stronger
 * contrast, labels beside colours, and the card language per deck. Everything but the language is stored on this device.
 */
@Composable
fun ReadingScreen(store: DeckStore, close: () -> Unit) {
    val reading = ReadingPrefs.of(LocalContext.current)
    var languages by remember { mutableStateOf(false) }
    BackHandler { if (languages) languages = false else close() }
    Column(Modifier.fillMaxSize().background(Ink.bg).systemBarsPadding().padding(horizontal = 20.dp).verticalScroll(rememberScrollState())) {
        if (languages) {
            KNavBar("Card language", back = { languages = false })
            CardLanguages(store)
            return@Column
        }
        KNavBar("Reading", back = close)
        BasicText("Card text", style = kBody(13, 500, Ink.muted), modifier = Modifier.padding(top = 14.dp, bottom = 8.dp))
        CardTextSize(reading.cardStep, reading::updateCardStep)
        KCaption("On top of your system text size.", Modifier.padding(top = 4.dp))
        CardPreview(reading)
        ReachToggle("Regular weight questions", reading.regularQuestions, "Instead of the thin display weight.", reading::updateRegularQuestions)
        ReachToggle("Stronger contrast", reading.strongContrast, "Brighter secondary text, visible dividers.", reading::updateStrongContrast)
        ReachToggle("Label colours", reading.labelColours, "Names beside flags and queue counts.", reading::updateLabelColours)
        Spacer(Modifier.height(8.dp))
        KFact("Card language", "Per deck", sub = "For TalkBack and read-aloud.", onClick = { languages = true })
        Spacer(Modifier.height(24.dp))
    }
}

/** Five "A" cells of growing size, one chosen; each at least 48 dp, the chosen one filled in the accent. */
@Composable
private fun CardTextSize(step: Int, onChange: (Int) -> Unit) {
    val sizes = listOf(13, 15, 17, 20, 24)
    Row(Modifier.fillMaxWidth().border(1.dp, Ink.control, RoundedCornerShape(2.dp)).height(IntrinsicSize.Min).selectableGroup()) {
        sizes.forEachIndexed { i, size ->
            val on = i == step
            if (i > 0) Box(Modifier.width(1.dp).fillMaxHeight().background(Ink.control))
            Box(
                Modifier.weight(1f).fillMaxHeight().heightIn(min = 48.dp).background(if (on) Ink.accent else Ink.bg)
                    .selectable(selected = on, role = Role.RadioButton) { onChange(i) }
                    .semantics { contentDescription = "Card text ${ReadingPrefs.STEP_NAMES[i].lowercase()}, ${(ReadingPrefs.scaleFor(i) * 100).roundToInt()} percent" },
                contentAlignment = Alignment.Center,
            ) {
                BasicText("A", style = TextStyle(fontFamily = Type.display, fontSize = size.sp, fontWeight = FontWeight(800), color = if (on) Ink.onAccent else Ink.text))
            }
        }
    }
}

/** A question and an answer line set as on a card, at the chosen size and weight (the system font scale applies through sp). */
@Composable
private fun CardPreview(reading: ReadingPrefs) {
    val scale = reading.cardScale
    Column(Modifier.padding(top = 10.dp, bottom = 4.dp).fillMaxWidth().border(1.dp, Ink.control, RoundedCornerShape(2.dp)).padding(12.dp)
        .semantics(mergeDescendants = true) { contentDescription = "Preview of a card at this size" }) {
        BasicText("Was ist ein Stack?", style = TextStyle(fontFamily = Type.display, fontSize = (26 * scale).sp, lineHeight = (33 * scale).sp,
            fontWeight = FontWeight(if (reading.regularQuestions) 400 else 200), color = Ink.text))
        BasicText("Ein Stapel: zuletzt hinein, zuerst heraus.", style = TextStyle(fontFamily = Type.body, fontSize = (20 * scale).sp, lineHeight = (28 * scale).sp,
            fontWeight = FontWeight(500), color = Ink.text), modifier = Modifier.padding(top = 8.dp))
    }
}

/** Top-level decks with their card language; a tap moves to the next choice. */
@Composable
private fun CardLanguages(store: DeckStore) {
    KCaption("The language a deck's cards are written in, so TalkBack reads them with the right voice. Automatic leaves it to the phone. Course decks set theirs when added.",
        Modifier.padding(vertical = 8.dp))
    val decks = store.rows.filter { it.depth == 0 }
    if (decks.isEmpty()) KCaption("No decks yet.", Modifier.padding(top = 8.dp))
    for (deck in decks) {
        val tag = store.deckLang[deck.id]
        val at = LANGUAGES.indexOfFirst { it.first == tag }
        // A tag from elsewhere (another device, say "fr") is shown as it is; the next tap goes back to Automatic.
        val next = LANGUAGES[if (at < 0) 0 else (at + 1) % LANGUAGES.size]
        KFact(deck.name, if (at < 0) tag.orEmpty() else LANGUAGES[at].second, sub = "Tap for ${next.second}", onClick = { store.setLang(next.first, deck.id) })
    }
    Spacer(Modifier.height(24.dp))
}
