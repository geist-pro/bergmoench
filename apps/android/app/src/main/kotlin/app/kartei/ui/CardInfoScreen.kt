// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.kartei.BrowseRow
import app.kartei.DeckStore
import app.kartei.Insights
import app.kartei.browseRow
import app.kartei.cardStats
import app.kartei.setFlag
import app.kartei.setSuspended
import app.kartei.timing
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val shortDate = DateTimeFormatter.ofPattern("d MMM", Locale.getDefault())
private val longDate = DateTimeFormatter.ofPattern("d MMMM yyyy", Locale.getDefault())
private fun day(secs: Long) = Instant.ofEpochSecond(secs).atZone(ZoneId.systemDefault()).toLocalDate()

/** Card info (info.html): FSRS stability, recall now, difficulty, lapses, the recall curve and the review log. */
@Composable
fun CardInfoScreen(store: DeckStore, cardId: Long, close: () -> Unit) {
    var stats by remember { mutableStateOf<anki.stats.CardStatsResponse?>(null) }
    var row by remember { mutableStateOf<BrowseRow?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var version by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(cardId, version) {
        val backend = store.backend ?: return@LaunchedEffect
        withContext(Dispatchers.IO) {
            runCatching { backend.cardStats(cardId) to backend.browseRow(cardId, backend.timing()) }
                .onSuccess { stats = it.first; row = it.second }.onFailure { error = it.message }
        }
    }
    fun act(block: (app.kartei.core.Backend) -> Unit) {
        val backend = store.backend ?: return
        scope.launch(Dispatchers.IO) { runCatching { block(backend) }; version++; store.refresh() }
    }

    Column(Modifier.fillMaxSize().background(Ink.bg).systemBarsPadding().padding(horizontal = 20.dp).verticalScroll(rememberScrollState())) {
        KNavBar("Card info", back = close)
        val s = stats; val r = row
        if (s == null || r == null) {
            BasicText(error?.let { "Card info could not be read: $it" } ?: "Reading the card…", style = kBody(15, color = Ink.muted), modifier = Modifier.padding(top = 12.dp))
            return@Column
        }
        BasicText(r.question.ifBlank { "(empty question)" }, style = kDisplay(24, false), modifier = Modifier.padding(top = 4.dp, bottom = 16.dp).semantics { heading() })
        val memory = if (s.hasMemoryState()) s.memoryState else null
        Row(Modifier.fillMaxWidth()) {
            Kv(memory?.let { Insights.span(it.stability * 86_400.0) } ?: "–", "Stability", Modifier.weight(1f))
            Kv(if (s.hasFsrsRetrievability()) "${(s.fsrsRetrievability * 100).roundToInt()}%" else "–", "Recall now", Modifier.weight(1f))
            Kv(memory?.let { "%.1f".format(it.difficulty) } ?: "–", "Difficulty", Modifier.weight(1f))
            Kv("${s.lapses}", "Lapses", Modifier.weight(1f))
        }
        if (memory == null) KCaption(if (s.fsrsEnabled) "FSRS values appear after the first review." else "FSRS is off, so stability and recall aren't tracked.", Modifier.padding(top = 6.dp))
        KCaption("Stability: days until recall drops to 90%. Difficulty: 1 (easy) to 10 (hard).", Modifier.padding(top = 6.dp))

        val entries = s.revlogList.sortedBy { it.time }
        if (s.fsrsEnabled && entries.count { it.hasMemoryState() } >= 1) {
            Spacer(Modifier.height(16.dp))
            BasicText("Chance of recalling it, since you first saw it", style = kBody(14, 500, Ink.muted))
            RecallCurve(entries, Insights.decayFrom(s.fsrsParamsList), s.desiredRetention.takeIf { s.hasDesiredRetention() }?.toDouble() ?: 0.9)
        }

        Spacer(Modifier.height(16.dp))
        KFlagGrid(r.flag, Modifier.padding(bottom = 12.dp)) { f -> act { it.setFlag(cardId, f) } }
        val suspended = r.state == Insights.State.Suspended
        KButton(if (suspended) "Unsuspend" else "Suspend", primary = false, trailing = if (suspended) "back into reviews" else "leave out of reviews") {
            act { it.setSuspended(cardId, !suspended) }
        }

        if (entries.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            Row(Modifier.heightIn(min = 28.dp), verticalAlignment = Alignment.CenterVertically) {
                for ((h, w) in listOf("Date" to 1f, "Answer" to 1.2f, "Next in" to 1f, "Took" to 0.8f))
                    BasicText(h, style = kBody(13, 500, Ink.muted).copy(textAlign = if (h == "Date" || h == "Answer") TextAlign.Start else TextAlign.End), modifier = Modifier.weight(w))
            }
            KRule()
            for (e in entries.reversed()) LogRow(e)
        }
        Spacer(Modifier.height(12.dp))
        val due = when {
            r.state == Insights.State.New -> "Not yet studied."
            s.hasDueDate() -> "Due ${day(s.dueDate).format(longDate)}."
            else -> ""
        }
        KCaption("${s.notetype} note, ${s.cardType}. In ${s.deck}. Added ${day(s.added).format(longDate)}. $due Preset: ${s.preset}.", Modifier.padding(bottom = 24.dp))
    }
}

@Composable
private fun Kv(value: String, label: String, modifier: Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}) {
        BasicText(value, style = kBody(20, 700))
        BasicText(label, style = kBody(13, color = Ink.muted))
    }
}

private fun answerName(kind: Int, button: Int) = when {
    kind == 4 -> "Reset"
    kind == 5 -> "Rescheduled"
    else -> listOf("–", "Forgot", "Hard", "Good", "Easy").getOrElse(button) { "–" }
}

@Composable
private fun LogRow(e: anki.stats.CardStatsResponse.StatsRevlogEntry) {
    val forgot = e.buttonChosen == 1 && e.reviewKindValue < 4
    Row(Modifier.heightIn(min = 36.dp).semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
        BasicText(day(e.time).format(shortDate), style = kBody(14), modifier = Modifier.weight(1f))
        Row(Modifier.weight(1.2f), verticalAlignment = Alignment.CenterVertically) {
            if (forgot) Box(Modifier.padding(end = 6.dp).size(8.dp).background(Ink.forgot))
            BasicText(answerName(e.reviewKindValue, e.buttonChosen), style = kBody(14, 700))
        }
        BasicText(if (e.interval > 0) Insights.span(e.interval.toDouble()) else "–", style = kBody(14).copy(textAlign = TextAlign.End), modifier = Modifier.weight(1f))
        BasicText("${e.takenSecs.roundToInt()} s", style = kBody(14, color = Ink.muted).copy(textAlign = TextAlign.End), modifier = Modifier.weight(0.8f))
    }
}

/**
 * Estimated recall between reviews from each review's FSRS stability: R(t) = (1 + F·t/S)^-decay, restarting at 100 % after
 * every answer. Misses get a red dot. Single series, so no legend; the desired retention is the dashed line.
 */
@Composable
private fun RecallCurve(entries: List<anki.stats.CardStatsResponse.StatsRevlogEntry>, decay: Double, desired: Double) {
    val now = System.currentTimeMillis() / 1000
    val first = entries.first().time
    val span = (now - first).coerceAtLeast(86_400).toDouble()
    val nowR = entries.lastOrNull { it.hasMemoryState() }?.let { Insights.recall((now - it.time) / 86_400.0, it.memoryState.stability.toDouble(), decay) }
    val misses = entries.count { it.buttonChosen == 1 }
    val summary = "Recall curve over ${(span / 86_400).roundToInt()} days, ${entries.size} reviews, $misses forgotten" + (nowR?.let { ", about ${(it * 100).roundToInt()}% now" } ?: "") + "."
    Column(Modifier.padding(top = 8.dp).semantics(mergeDescendants = true) { contentDescription = summary }) {
        Box(Modifier.fillMaxWidth().height(110.dp)) {
            Canvas(Modifier.fillMaxSize().padding(top = 6.dp, bottom = 6.dp, end = 6.dp)) {
                val lo = 0.4
                fun x(t: Long) = ((t - first) / span).toFloat() * size.width
                fun y(r: Double) = ((1 - r) / (1 - lo)).toFloat().coerceIn(0f, 1f) * size.height
                drawLine(Ink.muted, Offset(0f, y(desired)), Offset(size.width, y(desired)), 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)))
                val path = Path(); var started = false
                entries.forEachIndexed { i, e ->
                    if (!e.hasMemoryState()) return@forEachIndexed
                    val end = entries.getOrNull(i + 1)?.time ?: now
                    val steps = 24
                    for (k in 0..steps) {
                        val t = e.time + (end - e.time) * k / steps
                        val p = Offset(x(t), y(Insights.recall((t - e.time) / 86_400.0, e.memoryState.stability.toDouble(), decay)))
                        if (!started) { path.moveTo(p.x, p.y); started = true } else path.lineTo(p.x, p.y)
                    }
                }
                drawPath(path, Ink.text, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
                entries.forEachIndexed { i, e ->
                    if (e.buttonChosen != 1 || i == 0) return@forEachIndexed
                    val prev = entries.subList(0, i).lastOrNull { it.hasMemoryState() } ?: return@forEachIndexed
                    val p = Offset(x(e.time), y(Insights.recall((e.time - prev.time) / 86_400.0, prev.memoryState.stability.toDouble(), decay)))
                    drawCircle(Ink.bg, 6.dp.toPx(), p); drawCircle(Ink.forgot, 4.dp.toPx(), p)
                }
                nowR?.let { val p = Offset(size.width, y(it)); drawCircle(Ink.bg, 6.dp.toPx(), p); drawCircle(Ink.accent, 4.dp.toPx(), p) }
                drawLine(Ink.rule, Offset(0f, size.height + 6.dp.toPx()), Offset(size.width, size.height + 6.dp.toPx()), 1.dp.toPx())
            }
            BasicText("${(desired * 100).roundToInt()}%", style = kBody(13, color = Ink.muted), modifier = Modifier.align(Alignment.TopStart).padding(top = 2.dp))
        }
        Row(Modifier.fillMaxWidth()) {
            BasicText(day(first).format(shortDate), style = kBody(13, color = Ink.muted), modifier = Modifier.weight(1f))
            if (misses > 0) Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(8.dp).background(Ink.forgot)); Spacer(Modifier.width(4.dp)); BasicText("forgot", style = kBody(13, color = Ink.muted))
            }
            BasicText("today", style = kBody(13, color = Ink.muted))
        }
    }
}
