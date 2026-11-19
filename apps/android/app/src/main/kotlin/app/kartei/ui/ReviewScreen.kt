// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kartei.Rating
import app.kartei.ReviewPhase
import app.kartei.ReviewSession
import java.io.File
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.semantics.stateDescription
import app.kartei.CardAudioPlayer
import app.kartei.StudyPrefs
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import app.kartei.SwipeGrade
import app.kartei.TouchPrefs
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.graphics.graphicsLayer


private fun body(size: Int, weight: Int = 400, color: Color = Ink.text) =
    TextStyle(fontFamily = Type.body, fontSize = size.sp, fontWeight = FontWeight(weight), color = color, fontFeatureSettings = "tnum")

private fun display(size: Int, heavy: Boolean, color: Color = Ink.text) =
    TextStyle(fontFamily = Type.display, fontSize = size.sp, fontWeight = FontWeight(if (heavy) 800 else 200), color = color)

@Composable
fun ReviewScreen(session: ReviewSession, mediaFolder: File, prefs: app.kartei.StudyPrefs, close: () -> Unit) {
    val context = LocalContext.current
    val view = androidx.compose.ui.platform.LocalView.current
    // TalkBack hears that the answer appeared; the card page itself is a WebView and does not say so.
    LaunchedEffect(session.phase) { if (session.phase == ReviewPhase.Answer) view.announceForAccessibility("Answer shown") }
    DisposableEffect(session) {
        val player = CardAudioPlayer(context, mediaFolder)
        session.attach(player)
        session.start()
        onDispose { player.release() }
    }
    var actions by remember { mutableStateOf(false) }
    BackHandler(enabled = actions) { actions = false }
    Box(Modifier.fillMaxSize()) {
    Column(Modifier.fillMaxSize().background(Ink.bg).systemBarsPadding().imePadding()) {
        Row(Modifier.heightIn(min = 48.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(48.dp).clickable(role = Role.Button, onClick = close).semantics { contentDescription = "Back to decks" }, contentAlignment = Alignment.Center) {
                Canvas(Modifier.size(16.dp)) {
                    drawLine(Ink.text, Offset(size.width * 0.65f, 0f), Offset(size.width * 0.2f, size.height / 2), 1.5.dp.toPx(), StrokeCap.Round)
                    drawLine(Ink.text, Offset(size.width * 0.2f, size.height / 2), Offset(size.width * 0.65f, size.height), 1.5.dp.toPx(), StrokeCap.Round)
                }
            }
            BasicText(session.deckName, style = body(15, 500), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Box(Modifier.heightIn(min = 48.dp).alpha(if (session.canUndo) 1f else 0.35f)
                .clickable(enabled = session.canUndo, role = Role.Button, onClick = session::undo).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                BasicText("Undo", style = body(15, 500))
            }
            Box(Modifier.size(48.dp).alpha(if (session.hasCard) 1f else 0.35f)
                .clickable(enabled = session.hasCard, role = Role.Button) { actions = true }
                .semantics { contentDescription = "Card actions" }, contentAlignment = Alignment.Center) {
                BasicText("•••", style = body(13, 700))
            }
        }
        Box(Modifier.padding(horizontal = 20.dp).fillMaxWidth().height(2.dp).background(Ink.control)) {
            Box(Modifier.fillMaxWidth(session.progress).fillMaxHeight().background(Ink.text))
        }
        when (val phase = session.phase) {
            ReviewPhase.Done -> Done(session, close)
            is ReviewPhase.Failed -> Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.Center) {
                BasicText("Something went wrong.", style = display(22, false))
                BasicText(phase.why, style = body(13, color = Ink.muted), modifier = Modifier.padding(top = 8.dp))
            }
            else -> Card(session, mediaFolder, prefs.detail == StudyPrefs.Detail.Simple)
        }
    }
    if (actions) ActionSheet(session) { actions = false }
    }
}

@Composable
private fun ActionSheet(session: ReviewSession, dismiss: () -> Unit) {
    Box(Modifier.fillMaxSize().background(Ink.scrim).clickable(onClickLabel = "Close card actions", onClick = dismiss), contentAlignment = Alignment.BottomCenter) {
        Column(Modifier.fillMaxWidth().background(Ink.bg).clickable(enabled = false) {}.drawBehind { drawLine(Ink.accentRule, Offset(0f, 0f), Offset(size.width, 0f), 2.dp.toPx()) }
            .navigationBarsPadding().verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 20.dp)) {
            BasicText("Flag", style = body(13, 500, Ink.muted), modifier = Modifier.heightIn(min = 24.dp))
            // A flag's own cell clears it again, as before; None does the same from anywhere.
            KFlagGrid(session.flag, Modifier.padding(top = 8.dp, bottom = 14.dp)) { f ->
                if (f != 0) session.toggleFlag(f) else if (session.flag != 0) session.toggleFlag(session.flag)
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(Ink.rule))
            ActionRow("Bury until tomorrow", null) { dismiss(); session.putAway(false) }
            ActionRow("Suspend card", "until you bring it back") { dismiss(); session.putAway(true) }
        }
    }
}

@Composable
private fun ActionRow(label: String, detail: String?, onClick: () -> Unit) {
    // The detail sits under the label, not beside it, so it survives larger text.
    Column(Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Button, onClick = onClick).padding(vertical = 6.dp), verticalArrangement = Arrangement.Center) {
        BasicText(label, style = body(16, 500))
        if (detail != null) BasicText(detail, style = body(13, color = Ink.muted))
    }
    Box(Modifier.fillMaxWidth().height(1.dp).background(Ink.rule))
}

@Composable
private fun Card(session: ReviewSession, mediaFolder: File, simple: Boolean) {
    val isAnswer = session.phase == ReviewPhase.Answer
    val loading = session.phase == ReviewPhase.Loading
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp).padding(bottom = 8.dp)) {
        val reading = app.kartei.ReadingPrefs.of(LocalContext.current)
        val large = kLargeText()
        if (large) {
            // At large font scales the counts go on their own line and may wrap.
            Column(Modifier.padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BasicText("${session.remaining} left", style = body(13, color = Ink.muted))
                    if (session.flag > 0) FlagChip(session.flag, reading.labelColours)
                }
                QueueCounts(session, reading.labelColours, wrap = true)
            }
        } else {
            Row(Modifier.heightIn(min = 40.dp).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                BasicText("${session.remaining} left", style = body(13, color = Ink.muted))
                if (session.flag > 0) FlagChip(session.flag, reading.labelColours)
                Spacer(Modifier.weight(1f))
                QueueCounts(session, reading.labelColours, wrap = false)
            }
        }
        Box(Modifier.fillMaxWidth().height(2.dp).background(Ink.accentRule))
        if (session.deckName == app.kartei.CourseCatalogue.FIRST_SESSION_NAME) {
            FirstSessionCoach.line(session.answered, isAnswer, session.typeAnswer != null)?.let {
                BasicText(it, style = body(15), modifier = Modifier.fillMaxWidth().padding(top = 14.dp).semantics { contentDescription = "Tip: $it" })
            }
        }
        SwipeStage(session, mediaFolder, simple, isAnswer, loading, Modifier.weight(1f).fillMaxWidth().padding(top = 24.dp))
        val touch = TouchPrefs.of(androidx.compose.ui.platform.LocalContext.current)
        if (isAnswer && touch.showHint && !loading) SwipeHint(simple)
        var lastAnswered by remember { mutableStateOf(session.answered) }
        LaunchedEffect(session.answered) {
            // The hint shows for the first few answers, however they were given.
            if (session.answered > lastAnswered && touch.showHint) touch.hintSeen()
            lastAnswered = session.answered
        }
        if (session.replayTags.isNotEmpty() && !loading) AudioRow(session)
        val typing = session.phase == ReviewPhase.Question && session.typeAnswer != null
        if (typing) TypeField(session)
        val shown = if (simple) setOf(Rating.Forgot, Rating.Good) else Rating.entries.toSet()
        val note = session.examNote
        if (isAnswer && note != null && session.cappedRatings.any { it in shown }) {
            BasicText(note, style = body(13, color = Ink.muted), modifier = Modifier.padding(top = 10.dp))
        }
        // The bars have a minimum height and grow with their labels (IntrinsicSize keeps the buttons equally tall).
        val dim = Modifier.alpha(if (SwipeState.dragging) 0.35f else 1f)
        if (isAnswer && simple) {
            // Simple mode (mockups/screens/answer-simple.html): Forgot in the fail colour, Got it (Good) in the accent, 1fr : 2fr.
            Row(Modifier.padding(top = 12.dp).heightIn(min = 72.dp).height(IntrinsicSize.Min).then(dim), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Simple(session, Rating.Forgot, "Forgot", "back in", Ink.forgot, Ink.onForgot, 1f, short = large)
                Box(Modifier.padding(horizontal = 3.dp, vertical = 6.dp).width(1.dp).fillMaxHeight().background(Ink.rule))
                Simple(session, Rating.Good, "Got it", "next in", Ink.accent, Ink.onAccent, 2f, short = large)
            }
        } else if (isAnswer && large) {
            // Four labels in one row do not fit at large font scales: a 2 × 2 grid, Forgot top left, Good below it.
            Column(Modifier.padding(top = 12.dp).then(dim), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(Modifier.heightIn(min = 64.dp).height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Rate(session, Rating.Forgot, "Forgot", Ink.forgot, Ink.onForgot)
                    Rate(session, Rating.Hard, "Hard", Ink.surface2, Ink.text, outline = true)
                }
                Row(Modifier.heightIn(min = 64.dp).height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Rate(session, Rating.Good, "Good", Ink.accent, Ink.onAccent)
                    Rate(session, Rating.Easy, "Easy", Ink.surface2, Ink.text, outline = true)
                }
            }
        } else if (isAnswer) {
            // Two colours only: Forgot stands apart in the fail colour, Good is the accent, Hard and Easy stay neutral with an outline.
            Row(Modifier.padding(top = 12.dp).heightIn(min = 64.dp).height(IntrinsicSize.Min).then(dim), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Rate(session, Rating.Forgot, "Forgot", Ink.forgot, Ink.onForgot)
                Box(Modifier.padding(horizontal = 3.dp, vertical = 6.dp).width(1.dp).fillMaxHeight().background(Ink.control))
                Rate(session, Rating.Hard, "Hard", Ink.surface2, Ink.text, outline = true)
                Rate(session, Rating.Good, "Good", Ink.accent, Ink.onAccent)
                Rate(session, Rating.Easy, "Easy", Ink.surface2, Ink.text, outline = true)
            }
        } else {
            BasicText(if (typing) "Type it, then look." else "Try to say it before you look.", style = body(13, color = Ink.muted), modifier = Modifier.padding(top = 12.dp, bottom = 12.dp))
            Primary("Show answer", enabled = !loading, onClick = session::showAnswer)
        }
    }
}

/**
 * Native field rather than an <input> in the page: TalkBack labels and the IME work as everywhere else in the app,
 * and the value needs no JS round trip. "Done" on the keyboard shows the answer, as Enter does in Anki.
 */
@Composable
private fun TypeField(session: ReviewSession) {
    val focus = remember { FocusRequester() }
    var focused by remember { mutableStateOf(false) }
    // Code cards ({{type:Output}}) ask for console output over several lines: Enter starts a new line, Show answer compares.
    val multi = session.typeAnswer?.field == "Output"
    BasicTextField(
        value = session.typed,
        onValueChange = { session.typed = it },
        singleLine = !multi,
        maxLines = if (multi) 8 else 1,
        textStyle = if (multi) body(17, 400).copy(fontFamily = androidx.compose.ui.text.font.FontFamily(androidx.compose.ui.text.font.Font(
            if (ThemeState.family == Family.Geist) app.kartei.R.font.courier_prime else app.kartei.R.font.dm_mono))) else body(20, 500),
        cursorBrush = SolidColor(Ink.accent),
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false,
            imeAction = if (multi) ImeAction.Default else ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { session.showAnswer() }),
        modifier = Modifier.padding(top = 12.dp).fillMaxWidth().heightIn(min = 52.dp).focusRequester(focus).onFocusChanged { focused = it.isFocused }
            .semantics { contentDescription = if (multi) "The program's output" else "Your answer" },
        decorationBox = { inner ->
            Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).background(Ink.surface, RoundedCornerShape(2.dp))
                .border(if (focused) 2.dp else 1.dp, if (focused) Ink.accent else Ink.control, RoundedCornerShape(2.dp))
                .padding(horizontal = 14.dp, vertical = if (multi) 14.dp else 0.dp),
                contentAlignment = Alignment.CenterStart) {
                if (session.typed.isEmpty()) BasicText(if (multi) "Type the exact output" else "Type the answer", style = body(20, 400, Ink.muted))
                inner()
            }
        },
    )
    LaunchedEffect(session.typeAnswer) { runCatching { focus.requestFocus() } }
}

/** One replay row per side (mockups/screens/answer.html): plays the side's sound and speech in order. */
@Composable
private fun AudioRow(session: ReviewSession) {
    val playing = session.audioPlaying
    Row(Modifier.padding(top = 12.dp).heightIn(min = 48.dp).border(1.dp, Ink.control, RoundedCornerShape(2.dp))
        .clickable(role = Role.Button, onClickLabel = if (playing) "Stop audio" else "Play audio again") { session.toggleAudio() }
        .semantics(mergeDescendants = true) { contentDescription = if (playing) "Stop audio" else "Play audio again" }
        .padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Canvas(Modifier.size(14.dp)) {
            if (playing) drawRect(Ink.text)
            else drawPath(androidx.compose.ui.graphics.Path().apply { moveTo(0f, 0f); lineTo(size.width, size.height / 2); lineTo(0f, size.height); close() }, Ink.text)
        }
        BasicText(if (playing) "Stop" else "Play audio", style = body(15, 500))
        if (session.replayTags.size > 1) BasicText("${session.replayTags.size} clips", style = body(13, color = Ink.muted))
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.Simple(session: ReviewSession, rating: Rating, label: String, lead: String, fill: Color, ink: Color, weight: Float, short: Boolean = false) {
    val interval = session.intervals[rating.ordinal]
    val capped = if (rating in session.cappedRatings) ", shortened for the exam" else ""
    Column(Modifier.weight(weight).fillMaxHeight().clip(RoundedCornerShape(2.dp)).background(fill)
        .clickable(role = Role.Button) { session.answer(rating) }.semantics(mergeDescendants = true) { contentDescription = "$label, $lead $interval$capped" }
        .padding(horizontal = 4.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        BasicText(label, style = display(20, true, ink).copy(textAlign = TextAlign.Center))
        // At large font scales only the interval: "back in" would wrap in the narrow button.
        BasicText(if (short) interval else "$lead $interval", style = body(13, color = ink).copy(textAlign = TextAlign.Center))
    }
}

/** The set flag beside "n left": a flag mark, in an outlined chip with the flag's name when [named] (Label colours). */
@Composable
private fun FlagChip(flag: Int, named: Boolean) {
    val name = KFlagNames[flag - 1]
    val chip = if (named) Modifier.border(1.dp, Ink.control, RoundedCornerShape(2.dp)).padding(horizontal = 7.dp, vertical = 2.dp) else Modifier
    Row(Modifier.padding(start = 8.dp).then(chip).semantics(mergeDescendants = true) { contentDescription = "$name flag" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        KFlagMark(flag, width = 10, height = 12)
        if (named) BasicText(name, style = body(13))
    }
}

/**
 * New, learning and due counts in their colours, the active queue underlined. With [labelled] (Label colours) each number
 * carries its word, "5 new · 2 learn · 20 due", so colour and order are not the only cue. [wrap] sets them as one
 * paragraph that can break, for large font scales.
 */
@Composable
private fun QueueCounts(session: ReviewSession, labelled: Boolean, wrap: Boolean) {
    val parts = listOf(
        Triple(session.newCount, "new", Ink.new) to (session.activeQueue == anki.scheduler.QueuedCards.Queue.NEW),
        Triple(session.learningCount, "learn", Ink.learning) to (session.activeQueue == anki.scheduler.QueuedCards.Queue.LEARNING),
        Triple(session.reviewCount, "due", Ink.text) to (session.activeQueue == anki.scheduler.QueuedCards.Queue.REVIEW),
    )
    val spoken = Modifier.semantics(mergeDescendants = true) { contentDescription = "${session.newCount} new, ${session.learningCount} learning, ${session.reviewCount} to review" }
    if (wrap) {
        val text = androidx.compose.ui.text.buildAnnotatedString {
            parts.forEachIndexed { i, (part, active) ->
                val (n, word, colour) = part
                if (i > 0) append(if (labelled) " · " else "   ")
                pushStyle(androidx.compose.ui.text.SpanStyle(color = colour, fontWeight = FontWeight(500),
                    textDecoration = if (active) androidx.compose.ui.text.style.TextDecoration.Underline else null))
                append("$n"); pop()
                if (labelled) append("\u00A0$word")
            }
        }
        BasicText(text, style = body(13, color = Ink.muted), modifier = spoken)
        return
    }
    Row(spoken, horizontalArrangement = Arrangement.spacedBy(if (labelled) 5.dp else 12.dp), verticalAlignment = Alignment.CenterVertically) {
        parts.forEachIndexed { i, (part, active) ->
            val (n, word, colour) = part
            if (labelled && i > 0) BasicText("·", style = body(13, color = Ink.muted))
            BasicText("$n", style = body(13, 500, colour), modifier = Modifier.drawBehind {
                if (active) drawLine(colour, Offset(0f, size.height + 2.dp.toPx()), Offset(size.width, size.height + 2.dp.toPx()), 2.dp.toPx())
            })
            if (labelled) BasicText(word, style = body(13, color = Ink.muted))
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.Rate(session: ReviewSession, rating: Rating, label: String, fill: Color, ink: Color, outline: Boolean = false) {
    val interval = session.intervals[rating.ordinal]
    val shape = RoundedCornerShape(2.dp)
    // Hard and Easy are filled in surface2, which barely differs from the page: the outline is what shows the button.
    Column(Modifier.weight(1f).fillMaxHeight().clip(shape).background(fill).then(if (outline) Modifier.border(1.dp, Ink.control, shape) else Modifier)
        .clickable(role = Role.Button) { session.answer(rating) }.semantics(mergeDescendants = true) { contentDescription = "$label, next in $interval" + if (rating in session.cappedRatings) ", shortened for the exam" else "" }
        .padding(horizontal = 4.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        BasicText(label, style = body(16, 700, ink).copy(textAlign = TextAlign.Center))
        BasicText(interval, style = body(13, color = ink).copy(textAlign = TextAlign.Center))
    }
}

@Composable
private fun Primary(label: String, enabled: Boolean = true, onClick: () -> Unit) {
    Box(Modifier.fillMaxWidth().heightIn(min = 56.dp).clip(RoundedCornerShape(2.dp)).background(Ink.accent)
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick).padding(horizontal = 20.dp, vertical = 8.dp), contentAlignment = Alignment.CenterStart) {
        BasicText(label, style = display(20, true, Ink.onAccent))
    }
}

@Composable
private fun Done(session: ReviewSession, close: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp).padding(bottom = 8.dp)) {
        // The summary scrolls above the pinned button, so large text is not cut off.
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            BasicText(androidx.compose.ui.text.buildAnnotatedString {
                pushStyle(androidx.compose.ui.text.SpanStyle(fontWeight = FontWeight(800))); append("Done "); pop(); append("for today.")
            }, style = display(34, false, Ink.display), modifier = Modifier.padding(top = 24.dp))
            if (session.answered > 0) {
                BasicText("${session.answered} cards in ${session.minutesSpent} min.", style = display(34, false))
                Spacer(Modifier.height(24.dp))
                Fact("Remembered", "${session.remembered} of ${session.answered}")
                Fact("Forgot", "${session.answered - session.remembered}")
            } else {
                BasicText("Nothing is due in this deck right now.", style = body(15, color = Ink.muted), modifier = Modifier.padding(top = 12.dp))
            }
        }
        Spacer(Modifier.height(12.dp))
        Primary("Back to decks", onClick = close)
    }
}

@Composable
private fun Fact(name: String, value: String) {
    Row(Modifier.heightIn(min = 36.dp), verticalAlignment = Alignment.CenterVertically) {
        BasicText(name, style = body(15), modifier = Modifier.weight(1f))
        BasicText(value, style = body(15, 700))
    }
    Box(Modifier.fillMaxWidth().height(1.dp).background(Ink.rule))
}

/** One short tip per card in the first session (same lines as the Apple app's FirstSessionCoach). */
object FirstSessionCoach {
    private val question = listOf(
        "Say the answer to yourself before you look. Trying first is what makes it stick.",
        "Not sure? Guess anyway. A wrong try followed by the answer still helps you remember.",
        "Pictures count too: name what is hidden before you look.",
        "A short answer is enough. You only need the key idea.",
        "Last one of the five.",
    )
    private val answer = listOf(
        "Grade honestly: Got it only if you recalled it before looking.",
        "Forgot is the only fail. It brings the card back soon, which is what you want.",
        "Each card you get right comes back later: tomorrow, then in a few days, then weeks.",
        "Cards you know well spread out on their own, so there is no need to drill them now.",
        "That's it. From tomorrow, Bergmönch shows you what is due, a few minutes a day.",
    )

    fun line(index: Int, answerShown: Boolean, typed: Boolean): String? {
        if (index !in 0..4) return null
        if (typed) return if (answerShown) "Compare line by line. Got it only if your output matched." else "Type the exact output, line by line. Enter starts a new line."
        return if (answerShown) answer[index] else question[index]
    }
}

/** Whether a swipe is under way, so the rating buttons can dim (one review screen at a time). */
private object SwipeState { var dragging by mutableStateOf(false) }

/**
 * Swipe to grade (Touch.kt): the card page follows the finger over a strip that names the grade and its interval;
 * past the grading point a tick, on release past it the card flies off and the grade goes in.
 */
@Composable
private fun SwipeStage(session: ReviewSession, mediaFolder: File, simple: Boolean, isAnswer: Boolean, loading: Boolean, modifier: Modifier) {
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val view = androidx.compose.ui.platform.LocalView.current
    val touch = TouchPrefs.of(ctx)
    val scope = rememberCoroutineScope()
    val density = androidx.compose.ui.platform.LocalDensity.current
    val minPx = with(density) { 80.dp.toPx() }
    val ox = remember { androidx.compose.animation.core.Animatable(0f) }
    val oy = remember { androidx.compose.animation.core.Animatable(0f) }
    var size by remember { mutableStateOf(androidx.compose.ui.unit.IntSize.Zero) }
    var past by remember { mutableStateOf(false) }
    val full = !simple
    val enabled = isAnswer && touch.swipeToGrade && !loading
    LaunchedEffect(session.answered, session.phase) { if (session.phase != ReviewPhase.Answer) { ox.snapTo(0f); oy.snapTo(0f); SwipeState.dragging = false } }

    fun springBack() = scope.launch {
        SwipeState.dragging = false
        launch { ox.animateTo(0f, androidx.compose.animation.core.spring()) }
        oy.animateTo(0f, androidx.compose.animation.core.spring())
    }

    val handler: ((CardDrag) -> Unit)? = if (!enabled) null else { d ->
        when (d) {
            is CardDrag.Changed -> {
                SwipeState.dragging = true
                scope.launch { ox.snapTo(d.dx); oy.snapTo(d.dy) }
                val r = SwipeGrade.candidate(d.dx, d.dy, full, touch.swipeEasy, touch.swipeHard)
                val now = r != null && SwipeGrade.progress(d.dx, d.dy, r, size.width.toFloat(), size.height.toFloat(), minPx) >= 1f
                if (now != past) {
                    past = now
                    if (now && touch.haptics) view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK)
                }
            }
            is CardDrag.Ended -> {
                past = false
                val r = SwipeGrade.release(d.dx, d.dy, full, touch.swipeEasy, touch.swipeHard, size.width.toFloat(), size.height.toFloat(), minPx)
                if (r == null) springBack() else scope.launch {
                    val far = maxOf(size.width, size.height) * 1.3f
                    val tween = androidx.compose.animation.core.tween<Float>(180)
                    when (r) {
                        Rating.Good -> ox.animateTo(far, tween)
                        Rating.Forgot -> ox.animateTo(-far, tween)
                        Rating.Easy -> oy.animateTo(-far, tween)
                        Rating.Hard -> oy.animateTo(far, tween)
                    }
                    session.answer(r)
                    SwipeState.dragging = false
                }
            }
            CardDrag.Cancelled -> { past = false; springBack() }
        }
    }

    val dx = ox.value; val dy = oy.value
    val candidate = if (dx != 0f || dy != 0f) SwipeGrade.candidate(dx, dy, full, touch.swipeEasy, touch.swipeHard) else null
    Box(modifier.clip(RoundedCornerShape(2.dp)).onSizeChanged { size = it }) {
        if (candidate != null) {
            val progress = SwipeGrade.progress(dx, dy, candidate, size.width.toFloat(), size.height.toFloat(), minPx)
            val (fill, ink) = when (candidate) {
                Rating.Good -> Ink.accent to Ink.onAccent
                Rating.Forgot -> Ink.forgot to Ink.onForgot
                else -> Ink.surface2 to Ink.text
            }
            val align = when (candidate) {
                Rating.Good -> Alignment.CenterStart
                Rating.Forgot -> Alignment.CenterEnd
                Rating.Easy -> Alignment.BottomCenter
                Rating.Hard -> Alignment.TopCenter
            }
            val lead = if (candidate == Rating.Forgot) "back in" else "next in"
            Box(Modifier.matchParentSize().background(fill.copy(alpha = 0.45f + 0.55f * progress)).padding(horizontal = 16.dp, vertical = 20.dp), contentAlignment = align) {
                Column(horizontalAlignment = when (candidate) { Rating.Forgot -> Alignment.End; Rating.Good -> Alignment.Start; else -> Alignment.CenterHorizontally }) {
                    BasicText(SwipeGrade.label(candidate, simple), style = display(22, true, ink))
                    BasicText("$lead ${session.intervals[candidate.ordinal]}", style = body(13, color = ink))
                }
            }
        }
        val reveals = !isAnswer && touch.tapToReveal && session.typeAnswer == null && session.replayTags.isEmpty() && !loading
        val reading = app.kartei.ReadingPrefs.of(ctx)
        CardWeb(CardPage.html(session.questionHtml, if (isAnswer) session.answerHtml else null, session.css,
                regularQuestions = reading.regularQuestions, lang = session.lang), mediaFolder,
            Modifier.fillMaxSize()
                .graphicsLayer {
                    translationX = dx; translationY = dy
                    rotationZ = dx / 28f / density.density
                    transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 1f)
                }
                .background(Ink.bg)
                .then(if (dx != 0f || dy != 0f) Modifier.border(1.dp, Ink.rule, RoundedCornerShape(2.dp)) else Modifier)
                .alpha(if (loading) 0f else 1f),
            onMessage = session::play, onDrag = handler, allowVertical = touch.vertical(full),
            textZoom = app.kartei.ReadingPrefs.textZoom(density.fontScale, reading.cardStep),
            onTap = if (reveals) ({ session.showAnswer() }) else null)
    }
}

/** For the first few answers: which way is which, and that the buttons still work. */
@Composable
private fun SwipeHint(simple: Boolean) {
    val good = if (simple) "Got it" else "Good"
    Column(Modifier.padding(top = 12.dp).fillMaxWidth().semantics(mergeDescendants = true) {
        contentDescription = "Swipe the card left for Forgot or right for $good, or use the buttons"
    }) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(Ink.rule))
        Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            BasicText("‹ Forgot", style = body(13, 500, Ink.forgot))
            BasicText("swipe the card, or use the buttons", style = body(13, color = Ink.muted), modifier = Modifier.weight(1f).padding(horizontal = 8.dp))
            BasicText("$good ›", style = body(13, 500, Ink.text))
        }
    }
}
