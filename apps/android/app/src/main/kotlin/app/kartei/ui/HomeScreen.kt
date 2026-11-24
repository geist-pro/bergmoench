// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.compose.foundation.background
import android.app.DatePickerDialog
import android.content.DialogInterface
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextDecoration
import java.time.temporal.ChronoUnit
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
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kartei.DeckRow
import app.kartei.DeckStore
import app.kartei.firstToStudy
import app.kartei.Phase
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics

private fun body(size: Int, weight: Int = 400, color: Color = Ink.text) =
    TextStyle(fontFamily = Type.body, fontSize = size.sp, fontWeight = FontWeight(weight), color = color)

private fun display(size: Int, heavy: Boolean, color: Color = Ink.text) =
    TextStyle(fontFamily = Type.display, fontSize = size.sp, fontWeight = FontWeight(if (heavy) 800 else 200), color = color,
        letterSpacing = (-0.03 * size).sp)

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun HomeScreen(store: DeckStore, study: (DeckRow) -> Unit) {
    val context = LocalContext.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> if (uri != null) store.importPackage(uri) }
    var examDeck by remember { mutableStateOf<DeckRow?>(null) }
    var actionsDeck by remember { mutableStateOf<DeckRow?>(null) }
    var addMenu by remember { mutableStateOf(false) }
    var swipedOpen by remember { mutableStateOf<Long?>(null) }
    var confirmDelete by remember { mutableStateOf<DeckRow?>(null) }
    val fontScale = androidx.compose.ui.platform.LocalDensity.current.fontScale
    val large = kLargeText()
    Column(Modifier.fillMaxSize().background(Ink.bg).systemBarsPadding().padding(horizontal = 20.dp)) {
        Row(Modifier.heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
            BasicText(LocalDate.now().format(DateTimeFormatter.ofPattern("EEEE d MMMM", Locale.getDefault())), style = body(13, color = Ink.muted), modifier = Modifier.weight(1f))
            SyncStatusLink(store)
            BasicText("Add cards", style = body(15, 500).copy(textDecoration = TextDecoration.Underline),
                modifier = Modifier.heightIn(min = 48.dp).clickable(role = Role.Button) { addMenu = true }
                    .padding(start = 12.dp).wrapContentHeight())
        }
        store.importMessage?.let { BasicText(it, style = body(13, color = Ink.muted), modifier = Modifier.padding(bottom = 4.dp)) }
        if (addMenu) AddCardsDialog(store, importOwn = { picker.launch(arrayOf("application/octet-stream", "application/zip", "application/apkg", "*/*")) }) { addMenu = false }
        when (val phase = store.phase) {
            is Phase.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.CenterStart) { BasicText(phase.what, style = display(22, false)) }
            is Phase.Failed -> Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) {
                BasicText("The collection could not be opened.", style = display(22, false))
                BasicText(phase.why, style = body(13, color = Ink.muted), modifier = Modifier.padding(top = 8.dp))
            }
            Phase.Ready -> {
                examDeck?.let { ExamDialog(store, it) { examDeck = null } }
                actionsDeck?.let { DeckActions(store, it, exam = { d -> examDeck = d }, delete = { d -> confirmDelete = d }) { actionsDeck = null } }
                confirmDelete?.let { ConfirmDelete(store, it) { confirmDelete = null; swipedOpen = null } }
                // The hero numeral stops growing at 1.25 times, so it does not push the deck list off the screen.
                val hero = minOf(fontScale, 1.25f) / fontScale
                // The count columns widen with the font scale; from 1.3 on the counts become a line in each row instead.
                val countWidth = (44 * fontScale.coerceAtLeast(1f)).dp
                val summary: @Composable () -> Unit = {
                    Row(Modifier.padding(top = 12.dp).fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                        Row(Modifier.weight(1f), verticalAlignment = Alignment.Bottom) {
                            BasicText("${store.minutesToday}", style = display(96, true, Ink.display).copy(fontSize = (96 * hero).sp), modifier = Modifier.alignByBaseline())
                            Spacer(Modifier.width(10.dp))
                            BasicText("min", style = display(50, false, Ink.display).copy(fontSize = (50 * hero).sp), modifier = Modifier.alignByBaseline())
                        }
                        // At large font scales the calendar gives its room to the text; Stats has the history.
                        if (!large) StudyCalendar(store.studiedDays, Modifier.padding(start = 12.dp, bottom = 10.dp))
                    }
                    val decks = if (store.topLevelDecks == 1) "deck" else "decks"
                    BasicText("today, about ${store.cardsToday} cards across ${store.topLevelDecks} $decks. ${store.new} of them are new.",
                        style = body(13, color = Ink.muted), modifier = Modifier.padding(top = 6.dp, bottom = 10.dp))
                    // At large font scales the label and the value share no row: side by side they squeeze the label into a narrow column.
                    val value: @Composable () -> Unit = {
                        Row {
                            val r = store.retention
                            if (r != null) {
                                BasicText("${(r * 100).roundToInt()}% ", style = body(15, 700).copy(fontFeatureSettings = "tnum"))
                                BasicText("target ${(store.retentionTarget * 100).roundToInt()}%", style = body(15, color = Ink.muted))
                            } else {
                                BasicText("shown after 20 reviews", style = body(15, color = Ink.muted))
                            }
                        }
                    }
                    if (large) {
                        Column(Modifier.padding(vertical = 6.dp)) {
                            BasicText("Remembered, last 30 days", style = body(15))
                            value()
                        }
                    } else {
                        Row(Modifier.heightIn(min = 36.dp), verticalAlignment = Alignment.CenterVertically) {
                            BasicText("Remembered, last 30 days", style = body(15), modifier = Modifier.weight(1f).padding(end = 8.dp))
                            value()
                        }
                    }
                    Box(Modifier.fillMaxWidth().height(1.dp).background(Ink.rule))
                    Spacer(Modifier.height(16.dp))
                    if (!large) Row(Modifier.heightIn(min = 28.dp), verticalAlignment = Alignment.CenterVertically) {
                        BasicText("Deck", style = body(13, 500, Ink.muted), modifier = Modifier.weight(1f))
                        for (h in listOf("New", "Learn", "Due")) BasicText(h, style = body(13, 500, Ink.muted).copy(textAlign = TextAlign.End), maxLines = 1, modifier = Modifier.width(countWidth))
                    }
                    Box(Modifier.fillMaxWidth().height(2.dp).background(Ink.accentRule))
                }
                if (!large) summary()
                LazyColumn(Modifier.weight(1f)) {
                    // At large font scales the summary scrolls with the list, so the whole page scrolls and nothing is cut off.
                    if (large) item(key = "summary") { Column { summary() } }
                    items(store.rows, key = { it.id }) { row ->
                        SwipeToDelete(open = swipedOpen == row.id, onOpen = { swipedOpen = if (it) row.id else null }, delete = { confirmDelete = row }) {
                            Box(Modifier.background(Ink.bg).combinedClickable(onClickLabel = "Study this deck", onLongClickLabel = "Deck actions", onLongClick = { actionsDeck = row }) { study(row) }) {
                                DeckRowView(row, store.examDates[row.id], stacked = large, countWidth = countWidth)
                            }
                        }
                    }
                }
                val first = store.rows.firstToStudy()
                if (first != null && store.cardsToday > 0) {
                    Row(Modifier.padding(top = 12.dp).fillMaxWidth().heightIn(min = 56.dp).background(Ink.accent).clickable(role = Role.Button) { study(first) }.padding(horizontal = 20.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        BasicText("Study now", style = display(20, true).copy(color = Ink.onAccent, letterSpacing = 0.sp), modifier = Modifier.weight(1f))
                        BasicText("${store.cardsToday} cards", style = body(15, 500, Ink.onAccent))
                    }
                }
            }
        }
    }
}

/** "exam in 13 weeks", "exam in 9 days", "exam tomorrow", "exam today"; nothing once the date has passed. */
fun examCountdown(exam: LocalDate?): String? {
    if (exam == null) return null
    val days = ChronoUnit.DAYS.between(LocalDate.now(), exam)
    return when {
        days < 0 -> null
        days == 0L -> "exam today"
        days == 1L -> "exam tomorrow"
        days < 14 -> "exam in $days days"
        else -> "exam in ${days / 7} weeks"
    }
}

/** Long press on a deck: set its exam date, or delete it after a confirmation that says what goes with it. */
@Composable
private fun DeckActions(store: DeckStore, deck: DeckRow, exam: (DeckRow) -> Unit, delete: (DeckRow) -> Unit, dismiss: () -> Unit) {
    val context = LocalContext.current
    DisposableEffect(deck.id) {
        val dialog = android.app.AlertDialog.Builder(context, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle(deck.name)
            .setItems(arrayOf("Set exam date", "Delete deck…")) { _, which ->
                if (which == 0) exam(deck) else delete(deck)
            }
            .setOnDismissListener { dismiss() }
            .create()
        dialog.show()
        onDispose { dialog.setOnDismissListener(null); dialog.dismiss() }
    }
}

/** Asks before a deck goes; its subdecks, cards and review history go with it. */
@Composable
private fun ConfirmDelete(store: DeckStore, deck: DeckRow, dismiss: () -> Unit) {
    val context = LocalContext.current
    DisposableEffect(deck.id) {
        val dialog = android.app.AlertDialog.Builder(context, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("Delete ${deck.name}?")
            .setMessage("Its cards, any subdecks and their review history are deleted from this device. This can't be undone.")
            .setPositiveButton("Delete deck") { _, _ -> store.deleteDeck(deck) }
            .setNegativeButton("Cancel", null)
            .setOnDismissListener { dismiss() }
            .create()
        dialog.show()
        onDispose { dialog.setOnDismissListener(null); dialog.dismiss() }
    }
}

/** Swipe a row left to reveal Delete; a long swipe asks straight away. One row open at a time. */
@Composable
private fun SwipeToDelete(open: Boolean, onOpen: (Boolean) -> Unit, delete: () -> Unit, content: @Composable () -> Unit) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val width = with(density) { 88.dp.toPx() }
    var drag by remember { mutableStateOf(0f) }
    val offset = (if (open) -width else 0f) + drag
    Box(Modifier.fillMaxWidth().clipToBounds()
        .pointerInput(open) {
            detectHorizontalDragGestures(
                onDragEnd = {
                    val total = (if (open) -width else 0f) + drag
                    drag = 0f
                    when {
                        total < -width * 1.3f -> { onOpen(false); delete() }
                        total < -width / 2 -> onOpen(true)
                        else -> onOpen(false)
                    }
                },
                onDragCancel = { drag = 0f },
            ) { _, dx -> drag = (drag + dx).coerceIn(-width * 1.5f - (if (open) -width else 0f), if (open) width else 0f) }
        }) {
        if (offset < 0f) {
            Box(Modifier.matchParentSize().background(Ink.forgot).clickable(onClickLabel = "Delete deck") { delete() },
                contentAlignment = Alignment.CenterEnd) {
                BasicText("Delete", style = body(15, 700, Ink.onForgot), modifier = Modifier.padding(end = 18.dp))
            }
        }
        Box(Modifier.offset { androidx.compose.ui.unit.IntOffset(offset.toInt().coerceAtMost(0), 0) }) { content() }
    }
}

/** "Add cards": a course deck from the app, or the person's own Anki package. */
@Composable
private fun AddCardsDialog(store: DeckStore, importOwn: () -> Unit, dismiss: () -> Unit) {
    val context = LocalContext.current
    DisposableEffect(Unit) {
        val courses = app.kartei.CourseCatalogue.all
        val dialog = android.app.AlertDialog.Builder(context, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("Add cards")
            .setItems((courses.map { it.title } + "Import an Anki deck…").toTypedArray()) { _, which ->
                if (which < courses.size) store.importCourses(listOf(courses[which])) else importOwn()
            }
            .setOnDismissListener { dismiss() }
            .create()
        dialog.show()
        onDispose { dialog.setOnDismissListener(null); dialog.dismiss() }
    }
}

@Composable
private fun ExamDialog(store: DeckStore, deck: DeckRow, dismiss: () -> Unit) {
    val context = LocalContext.current
    DisposableEffect(deck.id) {
        val start = store.examDates[deck.id] ?: LocalDate.now().plusWeeks(8)
        val dialog = DatePickerDialog(context, android.R.style.Theme_DeviceDefault_Dialog, { _, y, m, d -> store.setExam(LocalDate.of(y, m + 1, d), deck.id) },
            start.year, start.monthValue - 1, start.dayOfMonth)
        dialog.setTitle("Exam date: ${deck.name}")
        dialog.datePicker.minDate = System.currentTimeMillis()
        if (store.examDates[deck.id] != null) dialog.setButton(DialogInterface.BUTTON_NEUTRAL, "Remove") { _, _ -> store.setExam(null, deck.id) }
        dialog.setOnDismissListener { dismiss() }
        dialog.show()
        onDispose { dialog.setOnDismissListener(null); dialog.dismiss() }
    }
}

/** "10 new", "2 learn", "31 due" for the counts that are not zero: the stacked deck row's labelled line. */
fun deckCountParts(new: Int, learning: Int, due: Int): List<Pair<Int, String>> =
    listOf(new to "new", learning to "learn", due to "due").filter { it.first > 0 }

/**
 * One deck: name and exam countdown with three count columns, or [stacked] (large font scales) the name, then one
 * labelled line "10 new · 2 learn · 31 due" with the colours on the numbers, then the exam line.
 */
@Composable
private fun DeckRowView(row: DeckRow, exam: LocalDate?, stacked: Boolean, countWidth: androidx.compose.ui.unit.Dp) {
    val name = body(if (row.depth == 0) 16 else 15, if (row.depth == 0) 500 else 400)
    Column {
        if (stacked) {
            Column(Modifier.heightIn(min = 48.dp).padding(start = (row.depth * 12).dp, top = 8.dp, bottom = 8.dp), verticalArrangement = Arrangement.Center) {
                BasicText(row.name, style = name)
                val parts = deckCountParts(row.new, row.learning, row.due)
                val colours = mapOf("new" to Ink.new, "learn" to Ink.learning, "due" to Ink.text)
                BasicText(androidx.compose.ui.text.buildAnnotatedString {
                    if (parts.isEmpty()) append("nothing due")
                    parts.forEachIndexed { i, (n, word) ->
                        if (i > 0) append(" · ")
                        pushStyle(androidx.compose.ui.text.SpanStyle(color = colours.getValue(word), fontWeight = FontWeight(500))); append("$n"); pop()
                        append("\u00A0$word")
                    }
                }, style = body(15, color = Ink.muted).copy(fontFeatureSettings = "tnum"))
                examCountdown(exam)?.let { BasicText(it, style = body(13, color = Ink.muted)) }
            }
        } else {
            Row(Modifier.heightIn(min = if (row.depth == 0) 48.dp else 40.dp).padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f).padding(start = (row.depth * 20).dp)) {
                    BasicText(row.name, style = name, maxLines = 2)
                    examCountdown(exam)?.let { BasicText(it, style = body(13, color = Ink.muted)) }
                }
                Count(row.new, Ink.new, countWidth); Count(row.learning, Ink.learning, countWidth); Count(row.due, Ink.text, countWidth)
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(Ink.rule))
    }
}

@Composable
private fun Count(n: Int, color: Color, width: androidx.compose.ui.unit.Dp) {
    BasicText(if (n == 0) "–" else "$n",
        style = body(15, 500, if (n == 0) Ink.muted else color).copy(textAlign = TextAlign.End, fontFeatureSettings = "tnum"),
        maxLines = 1, modifier = Modifier.width(width))
}

/** Days studied over the last five weeks, Monday first, this week in the bottom row. No streak number: a missed day is just an empty square. */
@Composable
fun StudyCalendar(studied: Set<Int>, modifier: Modifier = Modifier) {
    val weekday = LocalDate.now().dayOfWeek.value - 1  // Monday = 0
    val shape = RoundedCornerShape(1.dp)
    val count = studied.count { it > -35 }
    val control = Ink.control
    Column(modifier.semantics(mergeDescendants = true) { contentDescription = "Studied on $count of the last 35 days" }, horizontalAlignment = Alignment.End) {
        Row(Modifier.padding(bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (letter in listOf("M", "T", "W", "T", "F", "S", "S"))
                // 13 sp letters over 16 dp cells: allowed to overhang the cell a little instead of being cut.
                BasicText(letter, style = body(13, 500, Ink.muted).copy(textAlign = TextAlign.Center), softWrap = false,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Visible, modifier = Modifier.width(16.dp))
        }
        for (week in 0 until 5) {
            Row(Modifier.padding(bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                for (day in 0 until 7) {
                    val offset = (week - 4) * 7 + day - weekday
                    val cell = Modifier.size(16.dp)
                    when {
                        // Days to come: a dashed outline at full strength; fading it took it below 3:1.
                        offset > 0 -> Box(cell.drawBehind {
                            val w = 1.dp.toPx(); val dash = 2.dp.toPx()
                            drawRect(control, Offset(w / 2, w / 2), androidx.compose.ui.geometry.Size(size.width - w, size.height - w),
                                style = Stroke(w, pathEffect = PathEffect.dashPathEffect(floatArrayOf(dash, dash))))
                        })
                        offset == 0 -> Box(cell.background(if (0 in studied) Ink.text else Color.Transparent, shape).border(2.dp, Ink.accentRule, shape))
                        offset in studied -> Box(cell.background(Ink.text, shape))
                        else -> Box(cell.border(1.dp, control, shape))
                    }
                }
            }
        }
        BasicText("$count ${if (count == 1) "day" else "days"} in 5 weeks", style = body(13, color = Ink.muted), modifier = Modifier.padding(top = 2.dp))
    }
}
