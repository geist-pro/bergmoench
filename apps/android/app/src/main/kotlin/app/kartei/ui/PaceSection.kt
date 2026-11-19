// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import anki.deck_config.DeckConfig
import app.kartei.DeckStore
import app.kartei.Insights
import app.kartei.Phase
import app.kartei.applyStartingPace
import app.kartei.configsFor
import app.kartei.fitParams
import app.kartei.graphs
import app.kartei.retentionWorkload
import app.kartei.savePreset
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

/** One preset (Anki deck options group) and the decks that use it. */
private data class Preset(val config: DeckConfig, val decks: List<Long>, val useCount: Int)

private class PaceState {
    var presets by mutableStateOf(listOf<Preset>())
    var index by mutableStateOf(0)
    var fsrs by mutableStateOf(true)
    /** Average daily minutes over the last 30 days, at the retention the preset had when the screen opened. */
    var measuredMinutes by mutableStateOf<Double?>(null)
    var baseRetention by mutableStateOf(90)
    var costs by mutableStateOf<Map<Int, Float>?>(null)
    var error by mutableStateOf<String?>(null)
    /** Preset the workload curve was computed for; saving doesn't recompute it, switching presets does. */
    var curveFor: Long? = null
    val preset get() = presets.getOrNull(index)
}

/** Settings › Pace: desired retention with its workload, new cards a day, lighter days, and Anki's advanced deck options. */
@Composable
fun PaceSection(store: DeckStore) {
    val state = remember { PaceState() }
    val scope = rememberCoroutineScope()
    var reload by remember { mutableStateOf(0) }
    LaunchedEffect(store.phase, store.rows, reload) {
        val backend = store.backend ?: return@LaunchedEffect
        if (store.phase != Phase.Ready) return@LaunchedEffect
        withContext(Dispatchers.IO) {
            runCatching {
                val byConfig = linkedMapOf<Long, MutableList<Long>>()
                var all = listOf<anki.deck_config.DeckConfigsForUpdate.ConfigWithExtra>()
                var fsrs = true
                for (row in store.rows.ifEmpty { listOf(app.kartei.DeckRow(1, "Default", 0, 0, 0, 0)) }) {
                    val info = backend.configsFor(row.id)
                    all = info.allConfigList; fsrs = info.fsrs
                    byConfig.getOrPut(info.currentDeck.configId) { mutableListOf() } += row.id
                }
                val presets = byConfig.mapNotNull { (id, decks) -> all.firstOrNull { it.config.id == id }?.let { Preset(it.config, decks, it.useCount) } }
                val minutes = runCatching { Insights.averageDailyMinutes(backend.graphs("", 31).reviews.timeMap.mapValues { (_, t) -> (t.learn + t.relearn + t.young + t.mature + t.filtered).toLong() }) }.getOrNull()
                state.presets = presets
                state.index = state.index.coerceIn(0, maxOf(0, presets.size - 1))
                state.fsrs = fsrs
                state.measuredMinutes = minutes?.takeIf { it >= 0.5 }
                state.preset?.takeIf { it.config.id != state.curveFor }?.let { p ->
                    state.curveFor = p.config.id
                    state.baseRetention = (p.config.config.desiredRetention * 100).roundToInt().coerceIn(Insights.RETENTION_MIN, 99)
                    state.costs = runCatching { backend.retentionWorkload(p.config) }.getOrNull()?.takeIf { it.isNotEmpty() }
                }
            }.onFailure { state.error = it.message }
        }
    }

    val preset = state.preset ?: run {
        KSectionHead("Pace")
        KCaption(state.error?.let { "Pace settings could not be read: $it" } ?: "Reading your deck options…", Modifier.padding(bottom = 8.dp))
        return
    }
    val conf = preset.config.config

    fun save(edit: (DeckConfig.Config.Builder) -> Unit, fsrs: Boolean = state.fsrs) {
        val backend = store.backend ?: return
        val updated = preset.config.toBuilder().setConfig(preset.config.config.toBuilder().also(edit)).build()
        state.presets = state.presets.toMutableList().also { it[state.index] = preset.copy(config = updated) }
        scope.launch(Dispatchers.IO) {
            runCatching { backend.savePreset(preset.decks.first(), updated, fsrs) }
                .onSuccess { store.refresh() }
                .onFailure { state.error = "Could not save: ${it.message}" }
        }
    }

    Column {
        KSectionHead("Pace")
        val others = if (preset.useCount == 1) "Used by 1 deck." else "Shared by ${preset.useCount} decks. Changes apply to all of them."
        KFact("Preset: ${preset.config.name}", if (state.presets.size > 1) "${state.index + 1} of ${state.presets.size}" else "",
            sub = others, onClick = if (state.presets.size > 1) ({ state.index = (state.index + 1) % state.presets.size; state.costs = null; state.curveFor = null; reload++ }) else null)

        RetentionBlock(state, (conf.desiredRetention * 100).roundToInt().coerceIn(Insights.RETENTION_MIN, Insights.RETENTION_MAX), store.secondsPerCard, conf.newPerDay) { r ->
            save({ it.desiredRetention = r / 100f })
        }
        KRule()
        NewCardsBlock(conf.newPerDay, store.secondsPerCard, conf.desiredRetention.toDouble(), state) { n -> save({ it.newPerDay = n }) }
        KRule()
        LighterDays(conf.easyDaysPercentagesList) { days -> save({ it.clearEasyDaysPercentages().addAllEasyDaysPercentages(days) }) }
        KRule()
        FsrsToggle(state.fsrs) { on -> state.fsrs = on; save({}, fsrs = on) }
        var advanced by remember { mutableStateOf(false) }
        KFact("Advanced", "", sub = "Learning steps, leech threshold, FSRS parameters", onClick = { advanced = true })
        if (advanced) AdvancedDialog(store, preset.config, state.fsrs, close = { advanced = false }) { updated -> save({ it.clear().mergeFrom(updated.config) }) }
        state.error?.let { KCaption(it, Modifier.padding(top = 8.dp)) }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun RetentionBlock(state: PaceState, saved: Int, secondsPerCard: Double, newPerDay: Int, onSave: (Int) -> Unit) {
    var value by remember(saved) { mutableStateOf(saved) }
    val measured = state.measuredMinutes
    val base = measured ?: (Insights.steadyReviews(newPerDay, state.baseRetention / 100.0) * secondsPerCard / 60)
    val curve = Insights.minutesByRetention(base, state.baseRetention.coerceAtMost(Insights.RETENTION_MAX).coerceAtLeast(Insights.RETENTION_MIN), state.costs)
    val minutes = (curve[value] ?: base).roundToInt().coerceAtLeast(if (base > 0) 1 else 0)
    Column(Modifier.padding(top = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            BasicText("How much should stick", style = kBody(16, 700), modifier = Modifier.weight(1f))
            BasicText("default 90%", style = kBody(13, color = Ink.muted))
        }
        Row(verticalAlignment = Alignment.Bottom) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.Bottom) {
                BasicText("$value", style = kDisplay(72, true, Ink.display), modifier = Modifier.alignByBaseline())
                BasicText(" %", style = kDisplay(36, false, Ink.display), modifier = Modifier.alignByBaseline())
            }
            Column(Modifier.padding(bottom = 10.dp), horizontalAlignment = Alignment.End) {
                BasicText("costs about ${Insights.formatMinutes(minutes)} a day", style = kBody(14, 700).copy(textAlign = TextAlign.End))
                BasicText(when {
                    measured != null && state.costs != null -> "from your last 30 days"
                    measured != null -> "from your last 30 days, estimated"
                    else -> "estimate for $newPerDay new a day"
                }, style = kBody(13, color = Ink.muted).copy(textAlign = TextAlign.End))
            }
        }
        WorkloadCurve(curve, value)
        KSlider(value, Insights.RETENTION_MIN..Insights.RETENTION_MAX, "Desired retention",
            describe = { "$it percent, about ${(curve[it] ?: base).roundToInt()} minutes a day" },
            onChange = { value = it }, onDone = { if (it != saved) onSave(it) })
        val warn = value > Insights.RETENTION_WARN_ABOVE
        KCaption(
            if (warn) "Above 95% the work climbs steeply: every extra point costs more reviews than the one before."
            else "The share of cards you'll still recall when they come back. 90% balances work and memory for most people.",
            Modifier.padding(bottom = 12.dp).semantics { if (warn) stateDescription = "Warning" },
        )
    }
}

/** Minutes a day against desired retention (70–97 %), with the chosen value marked. */
@Composable
private fun WorkloadCurve(curve: Map<Int, Double>, value: Int) {
    val lo = Insights.RETENTION_MIN; val hi = Insights.RETENTION_MAX
    val maxMin = (curve.values.maxOrNull() ?: 1.0).coerceAtLeast(1.0)
    val summary = "Minutes a day by desired retention: 70% ${curve[lo]?.roundToInt()} min, 90% ${curve[90]?.roundToInt()} min, 97% ${curve[hi]?.roundToInt()} min."
    Column(Modifier.semantics(mergeDescendants = true) { contentDescription = summary }) {
        Box(Modifier.fillMaxWidth().height(96.dp)) {
            Canvas(Modifier.fillMaxWidth().height(96.dp).padding(top = 18.dp)) {
                fun x(r: Int) = (r - lo).toFloat() / (hi - lo) * size.width
                fun y(m: Double) = size.height - (m / maxMin).toFloat() * (size.height - 4.dp.toPx())
                val line = Path(); val area = Path()
                for (r in lo..hi) {
                    val p = Offset(x(r), y(curve[r] ?: 0.0))
                    if (r == lo) { line.moveTo(p.x, p.y); area.moveTo(p.x, size.height); area.lineTo(p.x, p.y) } else { line.lineTo(p.x, p.y); area.lineTo(p.x, p.y) }
                }
                area.lineTo(size.width, size.height); area.close()
                drawPath(area, Ink.text.copy(alpha = 0.10f))
                drawPath(line, Ink.text, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round))
                drawLine(Ink.rule, Offset(0f, size.height), Offset(size.width, size.height), 1.dp.toPx())
                val m = Offset(x(value), y(curve[value] ?: 0.0))
                drawLine(Ink.accent, m, Offset(m.x, size.height), 2.dp.toPx())
                drawCircle(Ink.bg, 6.dp.toPx(), m); drawCircle(Ink.accent, 4.dp.toPx(), m)
            }
            BasicText("${curve[hi]?.roundToInt()} min", style = kBody(13, color = Ink.muted), modifier = Modifier.align(Alignment.TopEnd))
            BasicText("${curve[lo]?.roundToInt()} min", style = kBody(13, color = Ink.muted), modifier = Modifier.align(Alignment.BottomStart).padding(bottom = 10.dp))
        }
        Row(Modifier.fillMaxWidth().padding(top = 2.dp)) {
            BasicText("70%", style = kBody(13, color = Ink.muted), modifier = Modifier.weight(1f))
            BasicText("97%", style = kBody(13, color = Ink.muted))
        }
    }
}

@Composable
private fun NewCardsBlock(saved: Int, secondsPerCard: Double, retention: Double, state: PaceState, onSave: (Int) -> Unit) {
    var value by remember(saved) { mutableStateOf(saved) }
    LaunchedEffect(value) { if (value != saved) { delay(700); onSave(value) } }
    val factor = state.costs?.let { c -> c[(retention * 100).roundToInt()]?.let { a -> c[90]?.let { b -> (a / b).toDouble() } } } ?: Insights.retentionLoadFactor(retention)
    val reviews = Insights.steadyReviews(value, retention, factor)
    Row(Modifier.fillMaxWidth().padding(vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            BasicText("New cards a day", style = kBody(16, 700))
            BasicText(if (value == 0) "No new cards: only reviews, and they shrink over time."
                else "$value new settles at about $reviews reviews a day, about ${Insights.formatMinutes(Insights.minutesFor(reviews, secondsPerCard))}.",
                style = kBody(14, color = Ink.muted))
        }
        KStepper(value, 0..200, label = "new cards a day") { value = it }
    }
}

@Composable
private fun LighterDays(saved: List<Float>, onSave: (List<Float>) -> Unit) {
    val days = if (saved.size == 7) saved else List(7) { 1f }
    val names = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
    Column(Modifier.padding(vertical = 16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            BasicText("Lighter days", style = kBody(16, 700), modifier = Modifier.weight(1f))
            BasicText("reviews move to the other days", style = kBody(13, color = Ink.muted))
        }
        // 2 dp gaps: seven day cells are as near 48 dp wide as a narrow phone allows.
        Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            days.forEachIndexed { i, v ->
                val label = Insights.easyDayLabel(v)
                Column(
                    Modifier.weight(1f).heightIn(min = 52.dp).background(if (label == "half") Ink.surface2 else Ink.bg).border(1.dp, if (label == "normal") Ink.control else Ink.text)
                        .clickable(role = Role.Button, onClickLabel = "Change") { onSave(days.toMutableList().also { it[i] = Insights.nextEasyDay(v) }) }
                        .semantics(mergeDescendants = true) { contentDescription = "${names[i]}: $label load" },
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                ) {
                    BasicText(names[i].take(1), style = kBody(15, 700))
                    if (label != "normal") BasicText(label, style = kBody(13, color = Ink.muted), maxLines = 1)
                }
            }
        }
        KCaption("Tap a day to make it half or minimum. The total stays the same; it is spread differently.", Modifier.padding(top = 8.dp))
    }
}

@Composable
private fun FsrsToggle(on: Boolean, onChange: (Boolean) -> Unit) {
    Column {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Switch) { onChange(!on) }
                .semantics(mergeDescendants = true) { toggleableState = ToggleableState(on); contentDescription = "FSRS scheduler" }
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                BasicText("FSRS scheduler", style = kBody(16))
                BasicText(if (on) "On. Beats Anki's older SM-2 for 99.6% of users in the open benchmark." else "Off: SM-2, Anki's older scheduler.",
                    style = kBody(13, color = Ink.muted))
            }
            KSwitch(on, Modifier.padding(start = 12.dp))
        }
        KRule()
    }
}

// ---------- Advanced ----------

private val INTERVAL_CHOICES = listOf(180, 365, 730, 1825, 3650, 36500)

@Composable
private fun AdvancedDialog(store: DeckStore, original: DeckConfig, fsrs: Boolean, close: () -> Unit, onSave: (DeckConfig) -> Unit) {
    var conf by remember { mutableStateOf(original) }
    var learn by remember { mutableStateOf(Insights.formatSteps(original.config.learnStepsList)) }
    var relearn by remember { mutableStateOf(Insights.formatSteps(original.config.relearnStepsList)) }
    var fitNote by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    fun edit(f: (DeckConfig.Config.Builder) -> Unit) { conf = conf.toBuilder().setConfig(conf.config.toBuilder().also(f)).build() }
    val learnOk = Insights.parseSteps(learn); val relearnOk = Insights.parseSteps(relearn)
    val finish = {
        learnOk?.let { s -> edit { it.clearLearnSteps().addAllLearnSteps(s) } }
        relearnOk?.let { s -> edit { it.clearRelearnSteps().addAllRelearnSteps(s) } }
        if (conf != original) onSave(conf)
        close()
    }
    Dialog(onDismissRequest = finish, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        BackHandler(onBack = finish)
        Column(Modifier.fillMaxSize().background(Ink.bg).systemBarsPadding().padding(horizontal = 20.dp).verticalScroll(rememberScrollState())) {
            KNavBar("Advanced", back = finish, trailing = "Done", onTrailing = finish)
            KCaption("Preset: ${conf.name}. These are Anki's deck options under their usual names. The defaults suit most people.", Modifier.padding(vertical = 8.dp))
            StepsField("Learning steps", "default 1m 10m", learn, learnOk != null) { learn = it }
            StepsField("Relearning steps", "default 10m", relearn, relearnOk != null) { relearn = it }
            KFact("Maximum interval", Insights.formatInterval(conf.config.maximumReviewInterval.toInt()), sub = "Tap to change", onClick = {
                val i = INTERVAL_CHOICES.indexOfFirst { it >= conf.config.maximumReviewInterval.toInt() }.let { if (it < 0) 0 else (it + 1) % INTERVAL_CHOICES.size }
                edit { it.maximumReviewInterval = INTERVAL_CHOICES[i] }
            })
            Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f).padding(end = 12.dp)) {
                    BasicText("Leech threshold", style = kBody(16))
                    BasicText("After this many lapses Bergmönch asks you to rewrite, split or suspend the card. Default 8.", style = kBody(13, color = Ink.muted))
                }
                KStepper(conf.config.leechThreshold, 2..30, label = "lapses") { n -> edit { it.leechThreshold = n } }
            }
            KRule()
            BasicText("FSRS", style = kBody(13, 500, Ink.muted), modifier = Modifier.padding(top = 24.dp, bottom = 4.dp))
            val params = conf.config.fsrsParams6List.ifEmpty { conf.config.fsrsParams5List }
            KFact("Parameters", if (params.isEmpty()) "defaults" else params.take(3).joinToString(", ") { "%.2f".format(it) } + " …",
                sub = fitNote ?: if (params.isEmpty()) "Not yet fitted to your reviews" else "${params.size} values")
            if (!fsrs) KCaption("FSRS is off, so these parameters aren't used.", Modifier.padding(top = 6.dp))
            Spacer(Modifier.height(12.dp))
            KButton("Fit to my reviews", primary = false) {
                val backend = store.backend ?: return@KButton
                fitNote = "Fitting…"
                scope.launch(Dispatchers.IO) {
                    runCatching { backend.fitParams(conf) }.onSuccess { (p, n) ->
                        if (p.isEmpty()) fitNote = "Not enough reviews yet ($n). Defaults stay."
                        else { edit { it.clearFsrsParams6().addAllFsrsParams6(p) }; fitNote = "Fitted on $n reviews" }
                    }.onFailure { fitNote = "Could not fit: ${it.message}" }
                }
            }
            Spacer(Modifier.height(8.dp))
            KButton("Back to the defaults", primary = false) {
                learn = Insights.formatSteps(Insights.LEARN_STEPS_DEFAULT); relearn = Insights.formatSteps(Insights.RELEARN_STEPS_DEFAULT)
                edit { it.leechThreshold = Insights.LEECH_THRESHOLD_DEFAULT; it.maximumReviewInterval = 36500 }
            }
            KCaption("Defaults: steps 1m 10m, relearning 10m, no interval limit, leech after 8 lapses. FSRS parameters are kept.", Modifier.padding(vertical = 12.dp))
        }
    }
}

@Composable
private fun StepsField(label: String, hint: String, text: String, ok: Boolean, onChange: (String) -> Unit) {
    Column(Modifier.padding(vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            BasicText(label, style = kBody(16), modifier = Modifier.weight(1f))
            BasicText(hint, style = kBody(13, color = Ink.muted))
        }
        BasicTextField(
            text, onChange, singleLine = true, textStyle = kBody(16, 500),
            cursorBrush = SolidColor(Ink.accent),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            modifier = Modifier.fillMaxWidth().padding(top = 6.dp).heightIn(min = 48.dp).border(1.dp, if (ok) Ink.control else Ink.forgot)
                .padding(horizontal = 12.dp, vertical = 13.dp).semantics { contentDescription = label },
        )
        if (!ok) BasicText("Use times like 1m 10m 1h 1d.", style = kBody(13, color = Ink.forgot), modifier = Modifier.padding(top = 4.dp))
    }
}

/** Used by onboarding: the steady-state line for a number of new cards a day. */
internal fun newCardsSummary(newPerDay: Int, secondsPerCard: Double) = Insights.newCardsLine(newPerDay, secondsPerCard)

/** Used by onboarding to write its choices. */
internal suspend fun DeckStore.applyOnboardingPace(newPerDay: Int) {
    val backend = backend ?: return
    val ids = rows.map { it.id }.ifEmpty { listOf(1L) }
    withContext(Dispatchers.IO) { runCatching { backend.applyStartingPace(ids, newPerDay) } }
}
