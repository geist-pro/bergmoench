// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import app.kartei.core.Backend
import app.kartei.core.CardsMethods
import app.kartei.core.DeckConfigMethods
import app.kartei.core.SchedulerMethods
import app.kartei.core.SearchMethods
import app.kartei.core.StatsMethods
import anki.deck_config.DeckConfig
import anki.deck_config.DeckConfigsForUpdate

/** Backend reads and writes for Browse, Stats, Pace and onboarding. Every function blocks: call from Dispatchers.IO. */

// ---------- Browse ----------

data class BrowseRow(
    val id: Long, val question: String, val deck: String, val state: Insights.State, val due: String, val flag: Int,
)

data class Timing(val daysElapsed: Int, val nextDayAt: Long)

fun Backend.timing(): Timing = call(SchedulerMethods.schedTimingToday, anki.generic.Empty.getDefaultInstance(), anki.scheduler.SchedTimingTodayResponse.parser())
    .let { Timing(it.daysElapsed, it.nextDayAt) }

/** Card ids matching an Anki search, sorted by due like the mockup. Throws BackendFailure on a search syntax error. */
fun Backend.searchCardIds(search: String, byDue: Boolean = true): List<Long> {
    val order = if (byDue) anki.search.SortOrder.newBuilder().setBuiltin(anki.search.SortOrder.Builtin.newBuilder().setColumn("cardDue")).build()
    else anki.search.SortOrder.newBuilder().setNone(anki.generic.Empty.getDefaultInstance()).build()
    return call(SearchMethods.searchCards, anki.search.SearchRequest.newBuilder().setSearch(search).setOrder(order).build(), anki.search.SearchResponse.parser()).idsList
}

/** The browser's active columns decide what BrowserRowForId returns; Kartei needs question and deck. */
fun Backend.useBrowserColumns() {
    run(SearchMethods.setActiveBrowserColumns, anki.generic.StringList.newBuilder().addVals("question").addVals("deck").build())
}

fun Backend.browseRow(id: Long, timing: Timing): BrowseRow {
    val row = call(SearchMethods.browserRowForId, anki.generic.Int64.newBuilder().setVal(id).build(), anki.search.BrowserRow.parser())
    val card = card(id)
    val state = Insights.state(card.queue, card.ctype)
    val due = if (card.originalDeckId != 0L && card.originalDue != 0) card.originalDue.toLong() else card.due.toLong()
    val days = Insights.daysUntilDue(card.queue, due, timing.daysElapsed, timing.nextDayAt)
    return BrowseRow(id, row.cellsList.getOrNull(0)?.text.orEmpty(), row.cellsList.getOrNull(1)?.text.orEmpty(), state, Insights.dueLabel(state, days), card.flags)
}

fun Backend.card(id: Long): anki.cards.Card = call(CardsMethods.getCard, anki.cards.CardId.newBuilder().setCid(id).build(), anki.cards.Card.parser())

fun Backend.setFlag(id: Long, flag: Int) {
    call(CardsMethods.setFlag, anki.cards.SetFlagRequest.newBuilder().addCardIds(id).setFlag(flag).build(), anki.collection.OpChangesWithCount.parser())
}

fun Backend.setSuspended(id: Long, suspended: Boolean) {
    if (suspended) call(SchedulerMethods.buryOrSuspendCards, anki.scheduler.BuryOrSuspendCardsRequest.newBuilder().addCardIds(id)
        .setMode(anki.scheduler.BuryOrSuspendCardsRequest.Mode.SUSPEND).build(), anki.collection.OpChangesWithCount.parser())
    else call(SchedulerMethods.restoreBuriedAndSuspendedCards, anki.cards.CardIds.newBuilder().addCids(id).build(), anki.collection.OpChanges.parser())
}

fun Backend.cardStats(id: Long): anki.stats.CardStatsResponse =
    call(StatsMethods.cardStats, anki.cards.CardId.newBuilder().setCid(id).build(), anki.stats.CardStatsResponse.parser())

fun Backend.reviewAnswers(id: Long): List<Insights.Answer> =
    call(StatsMethods.getReviewLogs, anki.cards.CardId.newBuilder().setCid(id).build(), anki.stats.ReviewLogs.parser()).entriesList
        .map { Insights.Answer(it.time, it.reviewKindValue, it.buttonChosen, it.lastInterval.toLong(), it.ease) }

// ---------- Stats ----------

fun Backend.graphs(search: String, days: Int = 35): anki.stats.GraphsResponse =
    call(StatsMethods.graphs, anki.stats.GraphsRequest.newBuilder().setSearch(search).setDays(days).build(), anki.stats.GraphsResponse.parser())

// ---------- Deck options (presets) ----------

fun Backend.configsFor(deckId: Long): DeckConfigsForUpdate =
    call(DeckConfigMethods.getDeckConfigsForUpdate, anki.decks.DeckId.newBuilder().setDid(deckId).build(), DeckConfigsForUpdate.parser())

/**
 * Save one preset through UpdateDeckConfigs, the call Anki's deck options screen uses. [deckId] must be a deck that already uses
 * the preset (the last config in the request is assigned to it). Collection-wide settings and the deck's own limits are copied
 * back unchanged, because the backend overwrites them from the request.
 */
fun Backend.savePreset(deckId: Long, config: DeckConfig, fsrs: Boolean = true) {
    val current = configsFor(deckId)
    call(DeckConfigMethods.updateDeckConfigs, anki.deck_config.UpdateDeckConfigsRequest.newBuilder()
        .setTargetDeckId(deckId)
        .addConfigs(config)
        .setMode(anki.deck_config.UpdateDeckConfigsMode.UPDATE_DECK_CONFIGS_MODE_NORMAL)
        .setCardStateCustomizer(current.cardStateCustomizer)
        .setLimits(current.currentDeck.limits)
        .setNewCardsIgnoreReviewLimit(current.newCardsIgnoreReviewLimit)
        .setFsrs(fsrs)
        .setApplyAllParentLimits(current.applyAllParentLimits)
        .setFsrsHealthCheck(current.fsrsHealthCheck)
        .build(), anki.collection.OpChanges.parser())
}

/** Relative review workload for each desired retention 70–99 %, from Anki's simulator over the preset's cards. */
fun Backend.retentionWorkload(config: DeckConfig): Map<Int, Float> {
    val params = config.config.let { c -> c.fsrsParams6List.ifEmpty { c.fsrsParams5List }.ifEmpty { c.fsrsParams4List } }
    val search = config.config.paramSearch.ifBlank { "preset:\"${config.name.replace("\\", "\\\\").replace("\"", "\\\"")}\" -is:suspended" }
    return call(DeckConfigMethods.getRetentionWorkload, anki.deck_config.GetRetentionWorkloadRequest.newBuilder().addAllW(params).setSearch(search).build(),
        anki.deck_config.GetRetentionWorkloadResponse.parser()).costsMap.mapKeys { it.key }
}

/** Fit FSRS parameters to the preset's review history; returns the new parameters and how many reviews they rest on. */
fun Backend.fitParams(config: DeckConfig): Pair<List<Float>, Int> {
    val c = config.config
    val search = c.paramSearch.ifBlank { "preset:\"${config.name.replace("\\", "\\\\").replace("\"", "\\\"")}\" -is:suspended" }
    val r = call(SchedulerMethods.computeFsrsParams, anki.scheduler.ComputeFsrsParamsRequest.newBuilder().setSearch(search)
        .addAllCurrentParams(c.fsrsParams6List).setNumOfRelearningSteps(c.relearnStepsCount).setHealthCheck(false).build(),
        anki.scheduler.ComputeFsrsParamsResponse.parser())
    return r.paramsList to r.fsrsItems
}

/** Collection-wide FSRS switch (rslib BoolKey::Fsrs, config key "fsrs"; off by default in Anki, on by default in Kartei). */
fun Backend.fsrsEnabled(deckId: Long): Boolean = configsFor(deckId).fsrs

/**
 * Onboarding's choices: new cards a day on every preset in use, FSRS on (docs/science-defaults.md). Desired retention, learning
 * steps and leech threshold already match Anki's defaults and are left as they are.
 */
fun Backend.applyStartingPace(deckIds: List<Long>, newPerDay: Int) {
    val seen = mutableSetOf<Long>()
    for (deck in deckIds) {
        val info = configsFor(deck)
        val id = info.currentDeck.configId
        if (!seen.add(id)) continue
        val conf = info.allConfigList.firstOrNull { it.config.id == id }?.config ?: continue
        savePreset(deck, conf.toBuilder().setConfig(conf.config.toBuilder().setNewPerDay(newPerDay)).build(), fsrs = true)
    }
}
