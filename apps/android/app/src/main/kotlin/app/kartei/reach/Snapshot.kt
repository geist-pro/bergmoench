// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.reach

import java.time.LocalDate

/**
 * What the widget and the reminder need, written by Reach.storeDidUpdate so neither has to open the collection.
 * [forecast] holds estimated cards for the next days (index 0 = tomorrow) as of [day].
 */
data class Snapshot(
    val day: LocalDate,
    val cards: Int,
    val minutes: Int,
    val secondsPerCard: Double,
    val studied: Set<LocalDate>,
    val forecast: List<Int> = emptyList(),
    /** The look chosen in Settings, "gruvbox" or "geist" (core/themes.json); snapshots written before it existed have none. */
    val family: String? = null,
) {
    fun encode(): String = buildString {
        append("kartei-snapshot 1\n")
        append("day=").append(day.toEpochDay()).append('\n')
        append("cards=").append(cards).append('\n')
        append("minutes=").append(minutes).append('\n')
        append("spc=").append(secondsPerCard).append('\n')
        append("studied=").append(studied.map { it.toEpochDay() }.sorted().joinToString(",")).append('\n')
        append("forecast=").append(forecast.joinToString(",")).append('\n')
        family?.let { append("family=").append(it).append('\n') }
    }

    /** Estimated cards on [date]: today's live count, a forecast day, or the last forecast day as a floor further on. */
    fun cardsOn(date: LocalDate): Int? {
        val ahead = date.toEpochDay() - day.toEpochDay()
        return when {
            ahead < 0 -> null
            ahead == 0L -> cards
            forecast.isEmpty() -> null
            ahead <= forecast.size -> forecast[(ahead - 1).toInt()]
            else -> forecast.last()
        }
    }

    fun minutesFor(cardCount: Int): Int = minutesFor(cardCount, secondsPerCard)

    companion object {
        /** Same rounding as DeckStore.minutesToday: nearest minute, at least 1 when any card is due. */
        fun minutesFor(cards: Int, secondsPerCard: Double): Int =
            if (cards <= 0) 0 else maxOf(1, ((cards * secondsPerCard + 30) / 60).toInt())

        fun decode(text: String?): Snapshot? {
            if (text == null) return null
            val lines = text.lines()
            if (lines.firstOrNull() != "kartei-snapshot 1") return null
            val kv = lines.drop(1).filter { '=' in it }.associate { it.substringBefore('=') to it.substringAfter('=') }
            return runCatching {
                fun ints(s: String?) = s.orEmpty().split(',').filter { it.isNotBlank() }.map { it.trim().toLong() }
                Snapshot(
                    day = LocalDate.ofEpochDay(kv.getValue("day").toLong()),
                    cards = kv.getValue("cards").toInt().coerceAtLeast(0),
                    minutes = kv.getValue("minutes").toInt().coerceAtLeast(0),
                    secondsPerCard = kv["spc"]?.toDouble()?.takeIf { it.isFinite() && it > 0 } ?: 8.0,
                    studied = ints(kv["studied"]).map(LocalDate::ofEpochDay).toSet(),
                    forecast = ints(kv["forecast"]).map { it.toInt().coerceAtLeast(0) },
                    family = kv["family"]?.takeIf { it.isNotBlank() },
                )
            }.getOrNull()
        }
    }
}
