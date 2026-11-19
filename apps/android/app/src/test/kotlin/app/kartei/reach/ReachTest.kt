// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.reach

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReachTest {
    private val day = LocalDate.of(2026, 11, 14)
    private val snap = Snapshot(day, cards = 38, minutes = 5, secondsPerCard = 8.0,
        studied = setOf(day, day.minusDays(1), day.minusDays(30)), forecast = listOf(12, 0, 30, 31, 31, 40, 41))

    @Test fun snapshotRoundTrip() {
        assertEquals(snap, Snapshot.decode(snap.encode()))
        val empty = Snapshot(day, 0, 0, 8.0, emptySet())
        assertEquals(empty, Snapshot.decode(empty.encode()))
    }

    @Test fun snapshotRejectsJunk() {
        assertNull(Snapshot.decode(null))
        assertNull(Snapshot.decode(""))
        assertNull(Snapshot.decode("kartei-snapshot 2\nday=1"))
        assertNull(Snapshot.decode("kartei-snapshot 1\ncards=3"))
        assertNull(Snapshot.decode("kartei-snapshot 1\nday=x\ncards=1\nminutes=1"))
        val d = Snapshot.decode("kartei-snapshot 1\nday=${day.toEpochDay()}\ncards=-4\nminutes=2\nspc=NaN\nextra=1")!!
        assertEquals(0, d.cards); assertEquals(8.0, d.secondsPerCard, 0.0); assertTrue(d.studied.isEmpty())
    }

    @Test fun cardsOnDays() {
        assertEquals(38, snap.cardsOn(day))
        assertEquals(12, snap.cardsOn(day.plusDays(1)))
        assertEquals(0, snap.cardsOn(day.plusDays(2)))
        assertEquals(41, snap.cardsOn(day.plusDays(7)))
        assertEquals(41, snap.cardsOn(day.plusDays(30)))  // reviews only pile up while the app stays closed
        assertNull(snap.cardsOn(day.minusDays(1)))
        assertNull(snap.copy(forecast = emptyList()).cardsOn(day.plusDays(1)))
    }

    @Test fun minutesRounding() {
        assertEquals(0, Snapshot.minutesFor(0, 8.0))
        assertEquals(1, Snapshot.minutesFor(1, 8.0))
        assertEquals(5, Snapshot.minutesFor(38, 8.0))   // 304 s
        assertEquals(12, Snapshot.minutesFor(90, 8.0))  // 720 s
    }

    @Test fun reminderOnlyWhenDue() {
        assertEquals(ReminderText("5 min of cards today", "38 cards, whenever suits you."), reminderFor(snap, day))
        assertEquals(ReminderText("About 2 min of cards today", "12 cards, whenever suits you."), reminderFor(snap, day.plusDays(1)))
        assertNull(reminderFor(snap, day.plusDays(2)))
        assertNull(reminderFor(snap.copy(cards = 0, minutes = 0), day))
        assertNull(reminderFor(null, day))
        assertNull(reminderFor(snap.copy(forecast = emptyList()), day.plusDays(1)))
        assertEquals("1 card, whenever suits you.", reminderFor(snap.copy(cards = 1, minutes = 1), day)!!.body)
    }

    @Test fun reminderWordingHasNoGuilt() {
        val words = listOf("streak", "miss", "don't", "lose", "behind", "!", "still", "forgot")
        for (d in 0L..9L) reminderFor(snap, day.plusDays(d))?.let { r ->
            val all = (r.title + " " + r.body).lowercase()
            for (w in words) assertFalse("'$w' in $all", all.contains(w))
        }
    }

    private val berlin = ZoneId.of("Europe/Berlin")
    private fun z(y: Int, mo: Int, d: Int, h: Int, mi: Int, zone: ZoneId = berlin) = ZonedDateTime.of(LocalDateTime.of(y, mo, d, h, mi), zone)

    @Test fun nextTriggerSameDayAndTomorrow() {
        assertEquals(z(2026, 11, 14, 18, 30), nextTrigger(z(2026, 11, 14, 9, 0), LocalTime.of(18, 30)))
        assertEquals(z(2026, 11, 15, 18, 30), nextTrigger(z(2026, 11, 14, 18, 30), LocalTime.of(18, 30)))  // exactly now: tomorrow
        assertEquals(z(2026, 11, 15, 18, 30), nextTrigger(z(2026, 11, 14, 20, 0), LocalTime.of(18, 30)))
    }

    @Test fun nextTriggerAcrossMidnightAndYearEnd() {
        assertEquals(z(2026, 11, 15, 0, 0), nextTrigger(z(2026, 11, 14, 23, 59), LocalTime.MIDNIGHT))
        assertEquals(z(2027, 1, 1, 0, 5), nextTrigger(z(2026, 12, 31, 23, 30), LocalTime.of(0, 5)))
        assertEquals(z(2026, 11, 14, 23, 59), nextTrigger(z(2026, 11, 14, 0, 0), LocalTime.of(23, 59)))
    }

    @Test fun nextTriggerDstSpringGap() {
        // Berlin, 29 March 2026: clocks jump from 02:00 to 03:00. A 02:30 reminder fires at 03:30 that day.
        val t = nextTrigger(z(2026, 3, 28, 22, 0), LocalTime.of(2, 30))
        assertEquals(LocalDateTime.of(2026, 3, 29, 3, 30), t.toLocalDateTime())
        // And it is back at 02:30 the day after.
        assertEquals(LocalDateTime.of(2026, 3, 30, 2, 30), nextTrigger(t, LocalTime.of(2, 30)).toLocalDateTime())
        // A normal evening time on the switch day stays put, and is 23 h after the day before.
        val before = nextTrigger(z(2026, 3, 28, 12, 0), LocalTime.of(19, 0))
        val onSwitch = nextTrigger(before, LocalTime.of(19, 0))
        assertEquals(LocalDateTime.of(2026, 3, 29, 19, 0), onSwitch.toLocalDateTime())
        assertEquals(23 * 3600L, java.time.Duration.between(before, onSwitch).seconds)
    }

    @Test fun nextTriggerDstAutumnOverlap() {
        // Berlin, 25 October 2026: 02:00–03:00 happens twice. The reminder fires once, at the first 02:30.
        val first = nextTrigger(z(2026, 10, 24, 22, 0), LocalTime.of(2, 30))
        assertEquals(LocalDateTime.of(2026, 10, 25, 2, 30), first.toLocalDateTime())
        assertEquals(java.time.ZoneOffset.ofHours(2), first.offset)
        // After it fires (now = first), the next one is the following day, not the repeated 02:30.
        assertEquals(LocalDateTime.of(2026, 10, 26, 2, 30), nextTrigger(first, LocalTime.of(2, 30)).toLocalDateTime())
        val evening = nextTrigger(z(2026, 10, 24, 12, 0), LocalTime.of(19, 0))
        assertEquals(25 * 3600L, java.time.Duration.between(evening, nextTrigger(evening, LocalTime.of(19, 0))).seconds)
    }

    @Test fun nextTriggerOtherZones() {
        val ny = ZoneId.of("America/New_York")
        assertEquals(LocalDateTime.of(2026, 3, 8, 3, 15), nextTrigger(z(2026, 3, 7, 23, 0, ny), LocalTime.of(2, 15)).toLocalDateTime())
        val utc = ZoneId.of("UTC")
        assertEquals(z(2026, 6, 1, 7, 0, utc), nextTrigger(z(2026, 5, 31, 7, 1, utc), LocalTime.of(7, 0)))
    }

    @Test fun lateAlarmsAreSkipped() {
        assertFalse(tooLate(1_000_000, 1_000_000 + 60_000))
        assertFalse(tooLate(1_000_000, 1_000_000 + 3 * 3600_000L))
        assertTrue(tooLate(1_000_000, 1_000_000 + 3 * 3600_000L + 1))
        assertFalse(tooLate(0, 99_999_999))  // no scheduled time recorded
    }

    @Test fun clock() {
        assertEquals("00:00", clockText(0)); assertEquals("18:30", clockText(18 * 60 + 30)); assertEquals("23:59", clockText(1439))
    }
}
