// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import app.kartei.Insights.Answer
import app.kartei.Insights.Filter
import app.kartei.Insights.State
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkloadTest {
    @Test fun factorIsOneAtNinetyPercent() = assertEquals(1.0, Insights.retentionLoadFactor(0.9), 1e-9)

    @Test fun factorRisesSteeplyAboveNinety() {
        val f95 = Insights.retentionLoadFactor(0.95); val f97 = Insights.retentionLoadFactor(0.97)
        assertTrue("95% should cost more than twice 90%: $f95", f95 > 2.0)
        assertTrue("97% should cost far more than 95%: $f97 vs $f95", f97 > f95 * 1.5)
        assertTrue(Insights.retentionLoadFactor(0.8) < 0.5)
    }

    @Test fun factorIsMonotonicOverSliderRange() {
        val fs = (Insights.RETENTION_MIN..Insights.RETENTION_MAX).map { Insights.retentionLoadFactor(it / 100.0) }
        fs.zipWithNext().forEach { (a, b) -> assertTrue("$a < $b", a < b) }
    }

    @Test fun factorClampsOutOfRangeInput() {
        assertEquals(Insights.retentionLoadFactor(0.99), Insights.retentionLoadFactor(1.0), 1e-9)
        assertTrue(Insights.retentionLoadFactor(0.0).isFinite())
    }

    @Test fun minutesByRetentionUsesBackendCostRatios() {
        val costs = (70..99).associateWith { it.toFloat() }  // linear costs, easy to check
        val m = Insights.minutesByRetention(18.0, 90, costs)
        assertEquals(18.0, m.getValue(90), 1e-9)
        assertEquals(18.0 * 95 / 90, m.getValue(95), 1e-9)
        assertEquals((70..97).toList(), m.keys.sorted())
    }

    @Test fun minutesByRetentionFallsBackToModel() {
        val m = Insights.minutesByRetention(10.0, 90, null)
        assertEquals(10.0, m.getValue(90), 1e-9)
        assertEquals(10.0 * Insights.retentionLoadFactor(0.95), m.getValue(95), 1e-9)
    }

    @Test fun fallbackScalesFromCurrentRetentionNotNinety() {
        val m = Insights.minutesByRetention(10.0, 85, null)
        assertEquals(10.0, m.getValue(85), 1e-9)
        assertTrue(m.getValue(90) > 10.0)
    }

    @Test fun missingCostEntryFallsBackPerPoint() {
        val m = Insights.minutesByRetention(10.0, 90, mapOf(90 to 0f))
        assertEquals(10.0, m.getValue(90), 1e-9)
    }

    @Test fun aWorkloadWithoutReviewHistoryIsNotUsable() {
        // A new collection: the simulator answers with zero for every retention. Dividing by the cost at 90 % gave NaN,
        // and rounding it crashed Settings a few seconds after it opened.
        val zeros = (70..99).associateWith { 0f }
        assertEquals(null, Insights.usableWorkload(zeros))
        assertEquals(null, Insights.usableWorkload(zeros + (85 to Float.NaN)))
        assertEquals(null, Insights.usableWorkload(mapOf(90 to 3f)))
        assertEquals(null, Insights.usableWorkload(null))
        val real = (70..99).associateWith { it.toFloat() }
        assertEquals(real, Insights.usableWorkload(real))
    }

    @Test fun aSteadyStateWithoutAUsableFactorFallsBackToTheEstimate() {
        assertEquals(Insights.steadyReviews(10, 0.9), Insights.steadyReviews(10, 0.9, Double.NaN))
        assertEquals(Insights.steadyReviews(10, 0.9), Insights.steadyReviews(10, 0.9, Double.POSITIVE_INFINITY))
        assertEquals(Insights.retentionLoadFactor(0.95), Insights.workloadFactor(mapOf(90 to 0f, 95 to 0f), 0.95), 1e-9)
        assertEquals(2.0, Insights.workloadFactor(mapOf(90 to 3f, 95 to 6f), 0.95), 1e-9)
    }

    @Test fun steadyStateTenReviewsPerNewCard() {
        assertEquals(100, Insights.steadyReviews(10))
        assertEquals(0, Insights.steadyReviews(0))
        assertEquals(200, Insights.steadyReviews(20, 0.9))
        assertTrue(Insights.steadyReviews(10, 0.95) > 200)
    }

    @Test fun minutesRoundAndNeverShowZeroForWork() {
        assertEquals(13, Insights.minutesFor(100, 8.0))
        assertEquals(1, Insights.minutesFor(1, 8.0))
        assertEquals(0, Insights.minutesFor(0, 8.0))
    }

    @Test fun newCardsLineWording() {
        assertEquals("10 new settles at about 100 reviews a day, about 13 min.", Insights.newCardsLine(10, 8.0))
        assertEquals("No new cards: only reviews, and they shrink over time.", Insights.newCardsLine(0, 8.0))
        assertEquals("1 h 07 min", Insights.formatMinutes(67))
        assertEquals("45 min", Insights.formatMinutes(45))
    }
}

class SearchTest {
    @Test fun filterOnly() = assertEquals("is:due", Insights.buildSearch("  ", Filter.DueToday))
    @Test fun textOnly() = assertEquals("deck:Bio tag:exam", Insights.buildSearch(" deck:Bio tag:exam ", null))
    @Test fun textAndFilterAreGrouped() = assertEquals("(dog or cat) tag:leech", Insights.buildSearch("dog or cat", Filter.Slipping))
    @Test fun emptyIsEverything() = assertEquals("", Insights.buildSearch("", null))

    @Test fun filterQueries() {
        assertEquals(listOf("is:due", "is:new", "-flag:0", "is:suspended", "tag:leech"), Filter.entries.map { it.query })
        assertEquals("Keep slipping", Filter.Slipping.label)
    }

    @Test fun deckSearchEscapes() {
        assertEquals("deck:\"Sample deck\"", Insights.deckSearch("Sample deck"))
        assertEquals("deck:\"a\\\"b\"", Insights.deckSearch("a\"b"))
        assertEquals("deck:\"x\\_y\\*z\"", Insights.deckSearch("x_y*z"))
        assertEquals("deck:\"back\\\\slash\"", Insights.deckSearch("back\\slash"))
        assertEquals("deck:\"Parent::Child\"", Insights.deckSearch("Parent::Child"))
    }
}

class CardStateTest {
    @Test fun statesFromQueueAndType() {
        assertEquals(State.New, Insights.state(0, 0))
        assertEquals(State.Learning, Insights.state(1, 1))
        assertEquals(State.Review, Insights.state(2, 2))
        assertEquals(State.Relearning, Insights.state(1, 3))
        assertEquals(State.Learning, Insights.state(3, 1))
        assertEquals(State.Suspended, Insights.state(-1, 2))
        assertEquals(State.Buried, Insights.state(-2, 2))
        assertEquals(State.Buried, Insights.state(-3, 0))
    }

    @Test fun daysUntilDueForDayQueues() {
        assertEquals(0, Insights.daysUntilDue(2, 500, 500, 0))
        assertEquals(3, Insights.daysUntilDue(2, 503, 500, 0))
        assertEquals(-2, Insights.daysUntilDue(3, 498, 500, 0))
    }

    @Test fun daysUntilDueForIntradayLearning() {
        val next = 1_700_000_000L
        assertEquals(0, Insights.daysUntilDue(1, next - 600, 0, next))
        assertEquals(1, Insights.daysUntilDue(1, next + 60, 0, next))
        assertEquals(2, Insights.daysUntilDue(1, next + 86_400 + 60, 0, next))
    }

    @Test fun noDueForNewOrSuspended() {
        assertNull(Insights.daysUntilDue(0, 5, 100, 0))
        assertNull(Insights.daysUntilDue(-1, 5, 100, 0))
    }

    @Test fun dueLabels() {
        assertEquals("today", Insights.dueLabel(State.Review, 0))
        assertEquals("tomorrow", Insights.dueLabel(State.Review, 1))
        assertEquals("in 9 d", Insights.dueLabel(State.Review, 9))
        assertEquals("in 3 wk", Insights.dueLabel(State.Review, 21))
        assertEquals("in 4 mo", Insights.dueLabel(State.Review, 120))
        assertEquals("in 3 y", Insights.dueLabel(State.Review, 1100))
        assertEquals("2 d late", Insights.dueLabel(State.Review, -2))
        assertEquals("paused", Insights.dueLabel(State.Suspended, 4))
        assertEquals("unseen", Insights.dueLabel(State.New, null))
        assertEquals("tomorrow", Insights.dueLabel(State.Buried, null))
    }

    @Test fun spans() {
        assertEquals("45 s", Insights.span(45.0))
        assertEquals("10 min", Insights.span(600.0))
        assertEquals("3 h", Insights.span(3 * 3600.0))
        assertEquals("5 d", Insights.span(5 * 86_400.0))
        assertEquals("4 mo", Insights.span(120 * 86_400.0))
        assertEquals("2.0 y", Insights.span(730 * 86_400.0))
    }
}

class RetentionTest {
    private val next = 1_700_000_000L
    private fun review(daysAgo: Int, pass: Boolean, kind: Int = 1, last: Long = 5 * 86_400L, ease: Int = 2500) =
        Answer(next - 3600 - daysAgo * 86_400L, kind, if (pass) 3 else 1, last, ease)

    @Test fun countsOnlyAnswersOnCardsWithAnIntervalOfADay() {
        assertTrue(Insights.countsForRetention(review(0, true)))
        // learning-kind answer on a card whose last interval was 10 min: excluded
        assertTrue(!Insights.countsForRetention(review(0, true, kind = 0, last = 600)))
        // relearning answer with a last interval of 2 days: included, as in rslib
        assertTrue(Insights.countsForRetention(review(0, false, kind = 2, last = 2 * 86_400L)))
        // manual reschedule and cram (filtered with ease 0) don't count
        assertTrue(!Insights.countsForRetention(review(0, true, kind = 4)))
        assertTrue(!Insights.countsForRetention(review(0, true, kind = 5)))
        assertTrue(!Insights.countsForRetention(review(0, true, kind = 3, ease = 0)))
        assertTrue(Insights.countsForRetention(review(0, true, kind = 3, ease = 2500)))
        assertTrue(!Insights.countsForRetention(Answer(next - 10, 1, 0, 86_400, 2500)))
    }

    @Test fun dailyWindowAverages() {
        // 9 passes and 1 fail every day for 40 days: every point 90 %
        val answers = (0 until 40).flatMap { d -> List(9) { review(d, true) } + review(d, false) }
        val line = Insights.dailyRetention(answers, next)
        assertEquals(30, line.size)
        line.forEach { assertEquals(0.9, it!!, 1e-9) }
    }

    @Test fun quietWindowsAreNull() {
        val answers = List(12) { review(0, true) }  // only today
        val line = Insights.dailyRetention(answers, next)
        assertEquals(1.0, line.last()!!, 1e-9)
        assertNull(line[line.size - 8])  // the window ending 7 days ago doesn't reach today
        assertTrue(line.dropLast(7).all { it == null })
    }

    @Test fun windowCoversSevenDays() {
        // a burst of 10 fails 6 days ago, then 10 passes today: today's window holds both
        val answers = List(10) { review(6, false) } + List(10) { review(0, true) }
        val line = Insights.dailyRetention(answers, next)
        assertEquals(0.5, line.last()!!, 1e-9)
        assertEquals(0.0, line[line.size - 2]!!, 1e-9)  // yesterday's window: only the fails
    }

    @Test fun futureAndAncientAnswersIgnored() {
        val answers = List(10) { Answer(next + 100, 1, 3, 86_400, 2500) } + List(10) { review(400, true) }
        assertTrue(Insights.dailyRetention(answers, next).all { it == null })
    }

    @Test fun headlineNeedsTwentyAnswers() {
        assertNull(Insights.headlineRetention(15, 4))
        assertEquals(0.91, Insights.headlineRetention(91, 9)!!, 1e-9)
    }
}

class ForecastAndCountsTest {
    @Test fun overdueLandsOnToday() {
        val m = Insights.forecastMinutes(mapOf(-3 to 15, 0 to 15, 1 to 60, 20 to 99), 8.0)
        assertEquals(14, m.size)
        assertEquals(30 * 8.0 / 60, m[0], 1e-9)
        assertEquals(8.0, m[1], 1e-9)
        assertEquals(0.0, m[13], 1e-9)
    }

    @Test fun stateCounts() {
        val c = Insights.counts(322, 10, 4, 480, 746, 3, 2)
        assertEquals(Insights.Counts(322, 14, 480, 746, 5), c)
        assertEquals(1567, c.total)
    }

    @Test fun reviewsThisWeekIsSevenDaysWithToday() =
        assertEquals(70, Insights.reviewsThisWeek(mapOf(0 to 10, -6 to 60, -7 to 1000, 1 to 5)))

    @Test fun averageDailyMinutesOverAllDays() {
        val ms = mapOf(0 to 600_000L, -10 to 1_200_000L, -40 to 9_999_999L)  // 10 + 20 min in window
        assertEquals(1.0, Insights.averageDailyMinutes(ms, 30), 1e-9)
    }
}

class FsrsAndStepsTest {
    @Test fun recallIsNinetyPercentAfterStability() {
        assertEquals(0.9, Insights.recall(5.0, 5.0, 0.1542), 1e-9)
        assertEquals(0.9, Insights.recall(12.0, 12.0, 0.5), 1e-9)
        assertEquals(1.0, Insights.recall(0.0, 5.0, 0.5), 1e-9)
        assertTrue(Insights.recall(20.0, 5.0, 0.5) < 0.9)
        assertEquals(0.0, Insights.recall(1.0, 0.0, 0.5), 1e-9)
    }

    @Test fun decayFromParams() {
        assertEquals(0.5, Insights.decayFrom(List(19) { 1f }), 1e-9)
        assertEquals(0.2, Insights.decayFrom(List(20) { 1f } + 0.2f), 1e-6)
    }

    @Test fun parseSteps() {
        assertEquals(listOf(1f, 10f), Insights.parseSteps("1m 10m"))
        assertEquals(listOf(1f, 10f), Insights.parseSteps("1, 10"))
        assertEquals(listOf(0.5f, 60f, 1440f), Insights.parseSteps("30s 1h 1d"))
        assertEquals(emptyList<Float>(), Insights.parseSteps(""))
        assertNull(Insights.parseSteps("1x"))
        assertNull(Insights.parseSteps("-1m"))
        assertNull(Insights.parseSteps("m"))
    }

    @Test fun formatStepsRoundTrips() {
        assertEquals("1m 10m", Insights.formatSteps(listOf(1f, 10f)))
        assertEquals("30s 1h 1d", Insights.formatSteps(listOf(0.5f, 60f, 1440f)))
        assertEquals("none", Insights.formatSteps(emptyList()))
        listOf("1m 10m", "10m", "5m 1h 1d").forEach { assertEquals(it, Insights.formatSteps(Insights.parseSteps(it)!!)) }
    }

    @Test fun intervals() {
        assertEquals("no limit", Insights.formatInterval(36500))
        assertEquals("1 year", Insights.formatInterval(365))
        assertEquals("5 years", Insights.formatInterval(1825))
        assertEquals("6 months", Insights.formatInterval(180))
        assertEquals("45 days", Insights.formatInterval(45))
    }

    @Test fun easyDaysCycle() {
        assertEquals(0.5f, Insights.nextEasyDay(1f))
        assertEquals(0f, Insights.nextEasyDay(0.5f))
        assertEquals(1f, Insights.nextEasyDay(0f))
        assertEquals(listOf("normal", "half", "min"), listOf(1f, 0.5f, 0f).map { Insights.easyDayLabel(it) })
    }

    @Test fun defaultsMatchScienceDoc() {
        assertEquals(0.90, Insights.RETENTION_DEFAULT, 0.0)
        assertEquals(70, Insights.RETENTION_MIN); assertEquals(97, Insights.RETENTION_MAX); assertEquals(95, Insights.RETENTION_WARN_ABOVE)
        assertEquals(10, Insights.NEW_PER_DAY_DEFAULT)
        assertEquals(8, Insights.LEECH_THRESHOLD_DEFAULT)
        assertEquals(listOf(1f, 10f), Insights.LEARN_STEPS_DEFAULT)
        assertEquals(listOf(10f), Insights.RELEARN_STEPS_DEFAULT)
    }
}
