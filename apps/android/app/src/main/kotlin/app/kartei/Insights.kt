// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * Pure maths and wording behind Browse, Stats, Pace and onboarding. No backend calls here, so all of it runs in JVM unit tests.
 * Defaults follow docs/science-defaults.md.
 */
object Insights {
    /** Desired retention: Anki's default, slider 70–97 %, warning above 95 % (workload rises steeply). */
    const val RETENTION_DEFAULT = 0.90
    const val RETENTION_MIN = 70
    const val RETENTION_MAX = 97
    const val RETENTION_WARN_ABOVE = 95
    const val NEW_PER_DAY_DEFAULT = 10
    /** Rule of thumb from docs/science-defaults.md: at 90 % each new card a day settles at about ten reviews a day. */
    const val REVIEWS_PER_NEW_CARD = 10.0
    const val LEECH_THRESHOLD_DEFAULT = 8
    val LEARN_STEPS_DEFAULT = listOf(1f, 10f)
    val RELEARN_STEPS_DEFAULT = listOf(10f)
    /** Seconds per card until there is review history (README: "cards x 8 seconds"). */
    const val SECONDS_PER_CARD_FALLBACK = 8.0
    /** FSRS-6 default decay (fsrs-rs DEFAULT_PARAMETERS[20]); FSRS-5 used 0.5. */
    const val FSRS6_DEFAULT_DECAY = 0.1542

    // ---------- Workload ----------

    /**
     * Fallback estimate of how review load scales with desired retention R, relative to 90 %, used only when the backend's
     * GetRetentionWorkload (the simulator Anki's own deck options use) is unavailable.
     *
     * Model: with the FSRS forgetting curve R(t) = (1 + F·t/S)^-d, the interval at which recall falls to R is
     * I = S/F · (R^(-1/d) − 1), so reviews per day scale with 1 / (R^(-1/d) − 1). Every lapse adds one relearning answer,
     * hence the (1 + (1 − R)) cost per review. It ignores that stability grows less after easy reviews, so it understates
     * the cost of very low retention; it is labelled an estimate wherever it is shown.
     */
    fun retentionLoadFactor(retention: Double, decay: Double = FSRS6_DEFAULT_DECAY): Double {
        fun load(r: Double) = (1 + (1 - r)) / (r.pow(-1 / decay) - 1)
        return load(retention.coerceIn(0.5, 0.99)) / load(RETENTION_DEFAULT)
    }

    /**
     * Daily minutes at each retention from 70 to 97 %, scaled from today's measured minutes.
     * [costs] is the backend's relative workload per whole percent (GetRetentionWorkload); null uses [retentionLoadFactor].
     */
    fun minutesByRetention(baseMinutes: Double, current: Int, costs: Map<Int, Float>?): Map<Int, Double> {
        val base = costs?.get(current)?.toDouble()?.takeIf { it > 0 }
        return (RETENTION_MIN..RETENTION_MAX).associateWith { r ->
            val c = costs?.get(r)?.toDouble()
            if (base != null && c != null) baseMinutes * c / base
            else baseMinutes * retentionLoadFactor(r / 100.0) / retentionLoadFactor(current / 100.0)
        }
    }

    /** Reviews a day that [newPerDay] new cards settle at, at [retention] (≈10 per new card at 90 %). */
    fun steadyReviews(newPerDay: Int, retention: Double = RETENTION_DEFAULT, factor: Double = retentionLoadFactor(retention)): Int =
        (newPerDay * REVIEWS_PER_NEW_CARD * (factor.takeIf { it.isFinite() && it > 0 } ?: retentionLoadFactor(retention))).roundToInt()

    /**
     * The backend's workload per retention when it can be used: it covers the slider range, every value is a finite
     * number and it is not all zero. A collection without review history gets zeros from the simulator.
     * Same rule as Workload.usable in the Apple app.
     */
    fun usableWorkload(costs: Map<Int, Float>?): Map<Int, Float>? =
        costs?.takeIf { c -> (RETENTION_MIN..RETENTION_MAX).all { c[it]?.isFinite() == true } && c.values.any { it > 0f } }

    /** Reviews at [retention] relative to 90 %: from the simulator's [costs] when they give a number, else the estimate. */
    fun workloadFactor(costs: Map<Int, Float>?, retention: Double): Double {
        val at = costs?.get((retention * 100).roundToInt())?.toDouble()
        val at90 = costs?.get(90)?.toDouble()
        val simulated = if (at != null && at90 != null && at90 > 0) at / at90 else null
        return simulated?.takeIf { it.isFinite() && it > 0 } ?: retentionLoadFactor(retention)
    }

    fun minutesFor(cards: Int, secondsPerCard: Double): Int = if (cards <= 0) 0 else max(1, ((cards * secondsPerCard + 30) / 60).toInt())

    /** "10 new settles at about 100 reviews a day, about 13 min." */
    fun newCardsLine(newPerDay: Int, secondsPerCard: Double, retention: Double = RETENTION_DEFAULT): String {
        if (newPerDay == 0) return "No new cards: only reviews, and they shrink over time."
        val reviews = steadyReviews(newPerDay, retention)
        return "$newPerDay new settles at about $reviews reviews a day, about ${formatMinutes(minutesFor(reviews, secondsPerCard))}."
    }

    fun formatMinutes(min: Int): String = if (min < 60) "$min min" else "${min / 60} h ${(min % 60).toString().padStart(2, '0')} min"

    // ---------- Search ----------

    enum class Filter(val label: String, val query: String) {
        DueToday("Due today", "is:due"),
        New("New", "is:new"),
        Flagged("Flagged", "-flag:0"),
        Suspended("Suspended", "is:suspended"),
        Slipping("Keep slipping", "tag:leech"),
    }

    /** Anki search for the browser: the typed text (Anki syntax, passed through) narrowed by the quick filter. */
    fun buildSearch(text: String, filter: Filter?): String {
        val t = text.trim()
        return when {
            filter == null -> t
            t.isEmpty() -> filter.query
            else -> "($t) ${filter.query}"
        }
    }

    /** `deck:"name"` with Anki's escaping: backslash before `\` and `"`, and before the wildcards `*` and `_`. */
    fun deckSearch(name: String): String {
        val escaped = buildString { for (c in name) { if (c in "\\\"*_") append('\\'); append(c) } }
        return "deck:\"$escaped\""
    }

    // ---------- Card state and due ----------

    enum class State(val label: String) { New("new"), Learning("learning"), Review("review"), Relearning("relearning"), Suspended("suspended"), Buried("buried") }

    /** From Anki's card queue and type (rslib card/mod.rs: queue −3/−2 buried, −1 suspended; type 0 new, 1 learn, 2 review, 3 relearn). */
    fun state(queue: Int, type: Int): State = when {
        queue == -1 -> State.Suspended
        queue <= -2 -> State.Buried
        type == 0 -> State.New
        type == 1 -> State.Learning
        type == 3 -> State.Relearning
        else -> State.Review
    }

    /**
     * Days from today until a card is due; null for new, suspended and buried cards.
     * Review and day-learning queues (2, 3) store a day number; the intraday learning queue (1) a Unix time.
     */
    fun daysUntilDue(queue: Int, due: Long, daysElapsed: Int, nextDayAtSecs: Long): Int? = when (queue) {
        2, 3 -> (due - daysElapsed).toInt()
        1, 4 -> if (due < nextDayAtSecs) 0 else (((due - nextDayAtSecs) / 86_400) + 1).toInt()
        else -> null
    }

    fun dueLabel(state: State, days: Int?): String = when {
        state == State.Suspended -> "paused"
        state == State.Buried -> "tomorrow"
        state == State.New || days == null -> "unseen"
        days < 0 -> "${-days} d late"
        days == 0 -> "today"
        days == 1 -> "tomorrow"
        days < 14 -> "in $days d"
        days < 60 -> "in ${days / 7} wk"
        days < 730 -> "in ${days / 30} mo"
        else -> "in ${days / 365} y"
    }

    /** "5 d", "3 h", "10 min", "4 mo", "2.1 y": a span in seconds, short. */
    fun span(seconds: Double): String {
        val m = seconds / 60; val h = m / 60; val d = h / 24
        return when {
            seconds < 60 -> "${seconds.roundToInt()} s"
            m < 60 -> "${m.roundToInt()} min"
            h < 24 -> "${h.roundToInt()} h"
            d < 30 -> "${d.roundToInt()} d"
            d < 365 -> "${(d / 30).roundToInt()} mo"
            else -> "%.1f y".format(java.util.Locale.ROOT, d / 365)
        }
    }

    // ---------- Retention ----------

    /** One answer from a card's review log, reduced to what true retention needs. */
    data class Answer(val timeSecs: Long, val kind: Int, val button: Int, val lastIntervalSecs: Long, val ease: Int)

    /**
     * Whether an answer counts towards true retention, matching rslib stats/graphs/retention.rs: it has a rating, is not cram
     * (filtered with ease 0), manual or rescheduled, and the card had an interval of at least a day (review kind, or a
     * last interval ≥ 1 day, which in the stats log's seconds is ≥ 86 400 either sign).
     */
    fun countsForRetention(a: Answer): Boolean {
        val rated = a.button in 1..4 && a.kind != 4 && a.kind != 5
        val cram = a.kind == 3 && a.ease == 0
        return rated && !cram && (a.kind == 1 || a.lastIntervalSecs >= 86_400)
    }

    data class Tally(val passed: Int, val failed: Int) {
        val total get() = passed + failed
        val rate: Double? get() = if (total == 0) null else passed.toDouble() / total
    }

    /**
     * Daily true retention as a trailing window, oldest first: element i is day (i − days + 1) relative to today, covering
     * the [window] days ending that day. A point is null when its window has fewer than [minAnswers] answers, so a quiet
     * day doesn't swing the line.
     */
    fun dailyRetention(answers: List<Answer>, nextDayAtSecs: Long, days: Int = 30, window: Int = 7, minAnswers: Int = 10): List<Double?> {
        val passed = IntArray(days + window); val failed = IntArray(days + window)
        for (a in answers) {
            if (!countsForRetention(a)) continue
            val ago = ((nextDayAtSecs - 1 - a.timeSecs) / 86_400).toInt()  // 0 = today
            if (a.timeSecs >= nextDayAtSecs || ago >= days + window - 1) continue
            val idx = days + window - 1 - ago
            if (a.button == 1) failed[idx]++ else passed[idx]++
        }
        return (0 until days).map { i ->
            val end = i + window  // inclusive end index in the padded arrays
            var p = 0; var f = 0
            for (j in end - window + 1..end) { p += passed[j]; f += failed[j] }
            if (p + f < minAnswers) null else p.toDouble() / (p + f)
        }
    }

    /** "91% remembered" headline needs this many answers before it means much (same threshold as home). */
    const val MIN_RETENTION_ANSWERS = 20

    fun headlineRetention(passed: Int, failed: Int): Double? = if (passed + failed < MIN_RETENTION_ANSWERS) null else passed.toDouble() / (passed + failed)

    // ---------- Forecast and counts ----------

    /** Minutes for each of the next [days] days from Anki's future_due map (day 0 = today; overdue days, negative, land on today). */
    fun forecastMinutes(futureDue: Map<Int, Int>, secondsPerCard: Double, days: Int = 14): List<Double> {
        val cards = IntArray(days)
        for ((d, n) in futureDue) { if (d < days) cards[max(d, 0)] += n }
        return cards.map { it * secondsPerCard / 60 }
    }

    data class Counts(val new: Int, val learning: Int, val young: Int, val mature: Int, val suspended: Int) {
        val total get() = new + learning + young + mature + suspended
    }

    /** Card counts by state from Anki's card_counts (inactive cards counted separately); buried cards join suspended as "paused". */
    fun counts(newCards: Int, learn: Int, relearn: Int, young: Int, mature: Int, suspended: Int, buried: Int) =
        Counts(newCards, learn + relearn, young, mature, suspended + buried)

    /** Reviews over the last 7 days including today, from Anki's per-day review counts (day 0 = today, −1 = yesterday). */
    fun reviewsThisWeek(perDay: Map<Int, Int>): Int = perDay.filterKeys { it in -6..0 }.values.sum()

    /** Average daily study minutes over the last [days] days (all days, studied or not) from per-day answer milliseconds. */
    fun averageDailyMinutes(millisPerDay: Map<Int, Long>, days: Int = 30): Double =
        millisPerDay.filterKeys { it in -(days - 1)..0 }.values.sum() / 60_000.0 / days

    // ---------- FSRS ----------

    /** FSRS forgetting curve: chance of recall [days] after a review that left stability [stability] (days), with [decay]. */
    fun recall(days: Double, stability: Double, decay: Double): Double {
        if (stability <= 0) return 0.0
        val factor = 0.9.pow(-1 / decay) - 1
        // A review dated after the device's clock (synced from a device that runs ahead) counts as just now.
        return (1 + factor * days.coerceAtLeast(0.0) / stability).pow(-decay)
    }

    /** Decay from a card's FSRS parameters: the 21st parameter in FSRS-6, otherwise FSRS-5's fixed 0.5. */
    fun decayFrom(params: List<Float>): Double = if (params.size >= 21) params[20].toDouble() else 0.5

    // ---------- Steps ----------

    /** "1m 10m" or "1, 10" (minutes) or "30s 1h 1d" → minutes; null if any part can't be read. */
    fun parseSteps(text: String): List<Float>? {
        val parts = text.split(',', ' ').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
        return parts.map { p ->
            val unit = p.takeLastWhile { it.isLetter() }
            val n = p.dropLast(unit.length).toFloatOrNull()?.takeIf { it > 0 } ?: return null
            when (unit) { "s" -> n / 60; "", "m", "min" -> n; "h" -> n * 60; "d" -> n * 1440; else -> return null }
        }
    }

    fun formatSteps(steps: List<Float>): String = if (steps.isEmpty()) "none" else steps.joinToString(" ") { m ->
        when {
            m < 1 -> "${(m * 60).roundToInt()}s"
            m >= 1440 && m % 1440 == 0f -> "${(m / 1440).toInt()}d"
            m >= 60 && m % 60 == 0f -> "${(m / 60).toInt()}h"
            m % 1 == 0f -> "${m.toInt()}m"
            else -> "${m}m"
        }
    }

    /** Max interval in days, shown in the largest whole unit. */
    fun formatInterval(days: Int): String = when {
        days >= 36500 -> "no limit"
        days % 365 == 0 -> "${days / 365} ${if (days == 365) "year" else "years"}"
        days >= 60 && days % 30 == 0 -> "${days / 30} months"
        else -> "$days days"
    }

    /** Easy Days: Anki stores one factor per weekday, Monday first; 1.0 normal, 0.5 reduced, 0.0 minimum. */
    fun nextEasyDay(v: Float): Float = when { v >= 0.75f -> 0.5f; v >= 0.25f -> 0f; else -> 1f }
    fun easyDayLabel(v: Float): String = when { v >= 0.75f -> "normal"; v >= 0.25f -> "half"; else -> "min" }
}
