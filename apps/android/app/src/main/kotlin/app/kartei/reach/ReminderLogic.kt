// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.reach

import java.time.Duration
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZonedDateTime

/** Pure reminder rules, unit-tested on the JVM. */

data class ReminderText(val title: String, val body: String)

/**
 * The reminder for [today], or null when nothing is due (or we can't tell). Specific and forgiving:
 * the minutes and cards waiting, no streaks, no "you missed", no pressure about when.
 */
fun reminderFor(snapshot: Snapshot?, today: LocalDate): ReminderText? {
    val s = snapshot ?: return null
    val cards = s.cardsOn(today) ?: return null
    if (cards <= 0) return null
    val minutes = s.minutesFor(cards)
    val live = s.day == today
    val title = (if (live) "" else "About ") + "$minutes min of cards today"
    val body = (if (cards == 1) "1 card" else "$cards cards") + ", whenever suits you."
    return ReminderText(title, body)
}

/** The next time the clock shows [at] after [now], in now's zone. Handles midnight, DST gaps (moved forward) and overlaps (earlier one). */
fun nextTrigger(now: ZonedDateTime, at: LocalTime): ZonedDateTime {
    val today = ZonedDateTime.of(now.toLocalDate(), at, now.zone)
    if (today.isAfter(now)) return today
    return ZonedDateTime.of(now.toLocalDate().plusDays(1), at, now.zone)
}

/** An inexact alarm can arrive late (Doze); a reminder hours after the chosen time is noise, so it is skipped. */
fun tooLate(scheduledMillis: Long, nowMillis: Long, grace: Duration = Duration.ofHours(3)): Boolean =
    scheduledMillis > 0 && nowMillis - scheduledMillis > grace.toMillis()

/** "18:30" from minutes after midnight. */
fun clockText(minuteOfDay: Int): String = "%02d:%02d".format(minuteOfDay / 60, minuteOfDay % 60)
