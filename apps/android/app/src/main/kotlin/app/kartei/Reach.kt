// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import android.app.Application
import android.content.Context
import app.kartei.core.Backend
import app.kartei.core.DeckConfigMethods
import app.kartei.core.SearchMethods
import app.kartei.reach.KarteiWidget
import app.kartei.reach.Reminders
import app.kartei.reach.Snapshot
import java.io.File
import java.time.LocalDate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Hooks for widget and reminders; called whenever the deck counts or the study calendar change.
 * Writes a small snapshot file so the widget and the reminder never need to open the collection.
 */
object Reach {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pending: Job? = null
    const val FORECAST_DAYS = 7

    fun storeDidUpdate(store: DeckStore) {
        if (store.phase != Phase.Ready) return
        val context: Context = store.getApplication<Application>()
        val today = LocalDate.now()
        val base = Snapshot(
            day = today,
            cards = store.cardsToday,
            minutes = store.minutesToday,
            secondsPerCard = store.secondsPerCard,
            studied = store.studiedDays.map { today.plusDays(it.toLong()) }.toSet(),
            family = ThemePrefs.of(context).family.key,
        )
        pending?.cancel()
        pending = scope.launch {
            val forecast = store.backend?.let { runCatching { forecast(it, store.new) }.getOrNull() }.orEmpty()
            val snap = base.copy(forecast = forecast)
            write(context, snap)
            KarteiWidget.updateAll(context)
            Reminders.schedule(context)
        }
    }

    private fun count(backend: Backend, search: String): Int =
        backend.call(SearchMethods.searchCards, anki.search.SearchRequest.newBuilder().setSearch(search).build(), anki.search.SearchResponse.parser()).idsCount

    /**
     * Estimated cards for each of the next days if nothing is studied before then: reviews due by that day (capped at
     * the default preset's review limit) plus new cards at the default preset's daily limit while unseen ones last.
     */
    private fun forecast(backend: Backend, newLeftToday: Int): List<Int> {
        val conf = runCatching {
            backend.call(DeckConfigMethods.getDeckConfig, anki.deck_config.DeckConfigId.newBuilder().setDcid(1).build(), anki.deck_config.DeckConfig.parser()).config
        }.getOrNull()
        val newPerDay = conf?.newPerDay ?: 10
        val reviewLimit = conf?.reviewsPerDay?.takeIf { it > 0 } ?: 9999
        val unseen = count(backend, "is:new -is:suspended -is:buried")
        return (1..FORECAST_DAYS).map { k ->
            val reviews = minOf(reviewLimit, count(backend, "prop:due<=$k"))
            val fresh = minOf(newPerDay, maxOf(0, unseen - newLeftToday - newPerDay * (k - 1)))
            reviews + fresh
        }
    }

    private fun file(context: Context) = File(context.filesDir, "reach-snapshot.txt")

    fun read(context: Context): Snapshot? = runCatching { Snapshot.decode(file(context).readText()) }.getOrNull()

    private fun write(context: Context, snap: Snapshot) {
        val target = file(context)
        val tmp = File(target.parentFile, target.name + ".tmp")
        tmp.writeText(snap.encode())
        if (!tmp.renameTo(target)) { target.writeText(snap.encode()); tmp.delete() }
    }
}
