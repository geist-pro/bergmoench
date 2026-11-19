// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kartei.DeckStore
import app.kartei.Insights
import app.kartei.Phase
import app.kartei.graphs
import app.kartei.reviewAnswers
import app.kartei.searchCardIds
import app.kartei.timing
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Everything the Stats tab shows, read in one pass on a background thread. */
private data class StatsData(
    val retention: Double?, val answers30: Int, val target: Double, val daily: List<Double?>,
    val forecast: List<Double>, val counts: Insights.Counts, val recallNow: Int?, val recallOf: Int, val reviewsWeek: Int, val leeches: Int,
)

/** Daily retention reads every reviewed card's log; above this many cards the line is skipped to keep the tab quick. */
private const val DAILY_CARD_LIMIT = 4000

/** Stats: true retention against the target leads; then the next 14 days in minutes, cards by state, leeches. No streaks. */
@Composable
fun StatsScreen(store: DeckStore) {
    var deck by remember { mutableStateOf<app.kartei.DeckRow?>(null) }
    var picking by remember { mutableStateOf(false) }
    var data by remember { mutableStateOf<StatsData?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(store.phase, store.rows, deck) {
        val backend = store.backend ?: return@LaunchedEffect
        if (store.phase != Phase.Ready) return@LaunchedEffect
        val scope = deck?.let { Insights.deckSearch(it.name) } ?: ""
        withContext(Dispatchers.IO) {
            runCatching {
                val g = backend.graphs(scope, 35)
                val m = g.trueRetention.month
                val passed = m.youngPassed + m.maturePassed; val failed = m.youngFailed + m.matureFailed
                val timing = backend.timing()
                val reviewed = backend.searchCardIds(listOf(scope, "rated:36").filter { it.isNotBlank() }.joinToString(" "), byDue = false)
                val daily = if (reviewed.size > DAILY_CARD_LIMIT) emptyList()
                    else Insights.dailyRetention(reviewed.flatMap { backend.reviewAnswers(it) }, timing.nextDayAt)
                val c = g.cardCounts.excludingInactive
                val counts = Insights.counts(c.newCards, c.learn, c.relearn, c.young, c.mature, c.suspended, c.buried)
                val perDay = g.reviews.countMap.mapValues { (_, r) -> r.learn + r.relearn + r.young + r.mature + r.filtered }
                val leeches = backend.searchCardIds(listOf(scope, "tag:leech").filter { it.isNotBlank() }.joinToString(" "), byDue = false).size
                val withRecall = g.retrievability.retrievabilityMap.values.sum()
                StatsData(
                    Insights.headlineRetention(passed, failed), passed + failed, store.retentionTarget, daily,
                    Insights.forecastMinutes(g.futureDue.futureDueMap, store.secondsPerCard), counts,
                    if (g.fsrs && withRecall > 0) g.retrievability.sumByCard.roundToInt() else null, withRecall,
                    Insights.reviewsThisWeek(perDay), leeches,
                )
            }.onSuccess { data = it; error = null }.onFailure { error = it.message ?: it.toString() }
        }
    }

    Column(Modifier.fillMaxSize().background(Ink.bg).systemBarsPadding().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
            BasicText("${deck?.name ?: "All decks"}, last 30 days", style = kBody(14, color = Ink.muted), modifier = Modifier.weight(1f))
            KLink(if (picking) "Close" else "Change", color = Ink.muted) { picking = !picking }
        }
        if (picking) {
            val choices = listOf<app.kartei.DeckRow?>(null) + store.rows.filter { it.depth == 0 }
            for (c in choices) {
                KFact(c?.name ?: "All decks", if (c?.id == deck?.id) "shown" else "", onClick = { deck = c; picking = false; data = null })
            }
            Spacer(Modifier.height(12.dp))
        }
        val d = data
        when {
            error != null && d == null -> BasicText("Stats could not be read: $error", style = kBody(15, color = Ink.muted), modifier = Modifier.padding(top = 16.dp))
            d == null -> BasicText("Counting your reviews…", style = kDisplay(22, false), modifier = Modifier.padding(top = 16.dp))
            else -> StatsBody(d, store.secondsPerCard)
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun StatsBody(d: StatsData, secondsPerCard: Double) {
    val target = (d.target * 100).roundToInt()
    val headline = buildAnnotatedString {
        if (d.retention != null) {
            withStyle(SpanStyle(fontWeight = FontWeight(800))) { append("${(d.retention * 100).roundToInt()}%") }
            append(" remembered. Your target is $target%.")
        } else append("Remembered: shown after ${Insights.MIN_RETENTION_ANSWERS} reviews. Your target is $target%.")
    }
    BasicText(headline, style = kDisplay(if (d.retention != null) 38 else 28, false, Ink.display).copy(lineHeight = (if (d.retention != null) 42 else 32).sp),
        modifier = Modifier.padding(top = 4.dp, bottom = 12.dp))
    if (d.daily.count { it != null } >= 2) {
        RetentionLine(d.daily, d.target)
        KCaption("Share of review cards you got right on the first try, a 7-day average for each day. ${d.answers30} answers in 30 days.", Modifier.padding(top = 6.dp))
    } else {
        KCaption(if (d.answers30 == 0) "The daily line appears once you have reviewed cards that already left the learning steps."
            else "The daily line needs a few more reviews: ${d.answers30} so far in 30 days.")
    }
    Spacer(Modifier.height(16.dp))
    val tomorrow = d.forecast.getOrNull(1) ?: 0.0
    KFact("Tomorrow", "${tomorrow.roundToInt()} min")
    d.recallNow?.let { KFact("Cards you'd recall today", String.format(Locale.ROOT, "%,d of %,d", it, d.recallOf).replace(',', ' ')) }

    Spacer(Modifier.height(20.dp))
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        BasicText("Next 14 days, minutes a day", style = kBody(14, 500, Ink.muted), modifier = Modifier.weight(1f))
        BasicText("at ${secondsPerCard.roundToInt()} s a card", style = kBody(13, color = Ink.muted))
    }
    Forecast(d.forecast)

    Spacer(Modifier.height(20.dp))
    StateBar(d.counts)
    Spacer(Modifier.height(12.dp))
    KFact("Reviews this week", "${d.reviewsWeek}")
    KFact("Cards that keep slipping", "${d.leeches}", sub = if (d.leeches > 0) "Find them in Browse under Keep slipping; they usually need rewriting." else null)
}

/** Daily true retention (7-day window) against the target, dashed. Single series, so no legend; the end value is labelled. */
@Composable
private fun RetentionLine(daily: List<Double?>, target: Double) {
    val values = daily.filterNotNull()
    val lo = minOf(values.min(), target) - 0.03
    val hi = maxOf(values.max(), target) + 0.02
    val last = values.last()
    val start = LocalDate.now().minusDays((daily.size - 1).toLong()).format(DateTimeFormatter.ofPattern("d MMM", Locale.getDefault()))
    val summary = "Retention over the last 30 days, from ${(values.first() * 100).roundToInt()}% to ${(last * 100).roundToInt()}%, " +
        "lowest ${(values.min() * 100).roundToInt()}%, highest ${(values.max() * 100).roundToInt()}%. Target ${(target * 100).roundToInt()}%."
    Column(Modifier.semantics(mergeDescendants = true) { contentDescription = summary }) {
        Box(Modifier.fillMaxWidth().height(120.dp)) {
            Canvas(Modifier.fillMaxSize().padding(top = 8.dp, bottom = 8.dp, end = 6.dp)) {
                fun x(i: Int) = i.toFloat() / (daily.size - 1) * size.width
                fun y(v: Double) = ((hi - v) / (hi - lo)).toFloat() * size.height
                drawLine(Ink.muted, Offset(0f, y(target)), Offset(size.width, y(target)), 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)))
                val path = Path(); var started = false
                daily.forEachIndexed { i, v ->
                    if (v == null) { started = false; return@forEachIndexed }
                    if (!started) { path.moveTo(x(i), y(v)); started = true } else path.lineTo(x(i), y(v))
                }
                drawPath(path, Ink.text, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
                val li = daily.indexOfLast { it != null }
                drawCircle(Ink.bg, 6.dp.toPx(), Offset(x(li), y(last)))
                drawCircle(Ink.accent, 4.dp.toPx(), Offset(x(li), y(last)))
                drawLine(Ink.rule, Offset(0f, size.height + 8.dp.toPx()), Offset(size.width, size.height + 8.dp.toPx()), 1.dp.toPx())
            }
            BasicText("target ${(target * 100).roundToInt()}%", style = kBody(13, color = Ink.muted), modifier = Modifier.align(Alignment.TopStart))
            BasicText("${(last * 100).roundToInt()}%", style = kBody(13, 700), modifier = Modifier.align(Alignment.TopEnd))
        }
        Row(Modifier.fillMaxWidth()) {
            BasicText(start, style = kBody(13, color = Ink.muted), modifier = Modifier.weight(1f))
            BasicText("today", style = kBody(13, color = Ink.muted))
        }
    }
}

/** 14 columns of minutes; today's includes anything overdue. Weekends drawn muted, like the mockup. */
@Composable
private fun Forecast(minutes: List<Double>) {
    val max = (minutes.maxOrNull() ?: 0.0).coerceAtLeast(1.0)
    val today = LocalDate.now()
    val dayName = DateTimeFormatter.ofPattern("EEE", Locale.getDefault())
    val summary = "Forecast, minutes a day for the next 14 days: " + minutes.mapIndexed { i, m -> "${today.plusDays(i.toLong()).format(dayName)} ${m.roundToInt()}" }.joinToString(", ")
    Column(Modifier.padding(top = 8.dp).semantics(mergeDescendants = true) { contentDescription = summary }) {
        Box(Modifier.fillMaxWidth().height(80.dp)) {
            Canvas(Modifier.fillMaxSize().padding(top = 14.dp)) {
                val slot = size.width / minutes.size; val w = minOf(24.dp.toPx(), slot - 2.dp.toPx())
                minutes.forEachIndexed { i, m ->
                    val h = (m / max).toFloat() * size.height
                    val weekend = today.plusDays(i.toLong()).dayOfWeek.value >= 6
                    val left = i * slot + (slot - w) / 2
                    if (h > 0.5f) {
                        val r = minOf(4.dp.toPx(), h)
                        drawRoundRect(if (weekend) Ink.muted else Ink.text, Offset(left, size.height - h), Size(w, h), CornerRadius(r, r))
                        drawRect(if (weekend) Ink.muted else Ink.text, Offset(left, size.height - minOf(h, r)), Size(w, minOf(h, r)))
                    }
                }
                drawLine(Ink.rule, Offset(0f, size.height), Offset(size.width, size.height), 1.dp.toPx())
            }
            val peak = minutes.indices.maxByOrNull { minutes[it] } ?: 0
            BasicText("most ${minutes[peak].roundToInt()} min, ${if (peak == 0) "today" else today.plusDays(peak.toLong()).format(dayName)}",
                style = kBody(13, color = Ink.muted), modifier = Modifier.align(Alignment.TopEnd))
        }
        Row(Modifier.fillMaxWidth().padding(top = 4.dp)) {
            BasicText("today", style = kBody(13, color = Ink.muted), modifier = Modifier.weight(1f))
            BasicText(today.plusDays(7).format(dayName), style = kBody(13, color = Ink.muted), modifier = Modifier.weight(1f))
            BasicText(today.plusDays(13).format(dayName), style = kBody(13, color = Ink.muted))
        }
    }
}

/** Cards by state as one stacked bar with 2 dp gaps, and a legend with the counts (colour is never the only cue). */
@Composable
private fun StateBar(c: Insights.Counts) {
    val parts = listOf(Triple("New", c.new, Ink.new), Triple("Learning", c.learning, Ink.learning), Triple("Young", c.young, Ink.muted), Triple("Mature", c.mature, Ink.text))
    val total = parts.sumOf { it.second }.coerceAtLeast(1)
    val summary = parts.joinToString(", ") { "${it.second} ${it.first.lowercase()}" } + if (c.suspended > 0) ", ${c.suspended} paused" else ""
    Column(Modifier.semantics(mergeDescendants = true) { contentDescription = "Cards by state: $summary" }) {
        Canvas(Modifier.fillMaxWidth().height(22.dp)) {
            val gap = 2.dp.toPx(); val shown = parts.filter { it.second > 0 }
            val usable = size.width - gap * (shown.size - 1).coerceAtLeast(0)
            var x = 0f
            for ((_, n, colour) in shown) {
                val w = usable * n / total
                drawRect(colour, Offset(x, 0f), Size(w.coerceAtLeast(2.dp.toPx()), size.height)); x += w + gap
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            for ((name, n, colour) in parts) Column {
                BasicText("$n", style = kBody(17, 700))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(10.dp).background(colour))
                    BasicText(" $name", style = kBody(14, color = Ink.muted))
                }
            }
        }
        if (c.suspended > 0) KCaption("${c.suspended} more suspended or buried.", Modifier.padding(top = 6.dp))
    }
}
