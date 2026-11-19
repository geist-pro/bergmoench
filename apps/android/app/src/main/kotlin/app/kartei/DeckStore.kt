// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.kartei.core.Backend
import app.kartei.core.CollectionMethods
import app.kartei.core.DeckConfigMethods
import app.kartei.core.StatsMethods
import app.kartei.core.DecksMethods
import app.kartei.core.ImportExportMethods
import android.net.Uri
import app.kartei.core.ConfigMethods
import java.io.File
import java.time.LocalDate
import org.json.JSONObject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

data class DeckRow(val id: Long, val name: String, val depth: Int, val new: Int, val learning: Int, val due: Int)

sealed interface Phase {
    data class Loading(val what: String) : Phase
    data object Ready : Phase
    data class Failed(val why: String) : Phase
}

private const val EXAM_KEY = "kartei.examDates"
private const val LANG_KEY = "kartei.deckLang"

/** Finding a deck's top-level ancestor in the flattened deck list (rows in tree order, children after their parent). */
object DeckRows {
    fun topLevel(rows: List<DeckRow>, deck: Long): Long? {
        val at = rows.indexOfFirst { it.id == deck }
        if (at < 0) return null
        return (at downTo 0).firstOrNull { rows[it].depth == 0 }?.let { rows[it].id }
    }
}

class DeckStore(app: Application) : AndroidViewModel(app) {
    var phase by mutableStateOf<Phase>(Phase.Loading("Opening your collection")); private set
    var rows by mutableStateOf(listOf<DeckRow>()); private set
    var new by mutableStateOf(0); private set
    var learning by mutableStateOf(0); private set
    var due by mutableStateOf(0); private set
    var topLevelDecks by mutableStateOf(0); private set
    var ankiVersion by mutableStateOf(""); private set
    var backend: Backend? = null; private set
    /** Exam dates per deck, kept in the collection's config under "kartei.examDates" as {"deckId": "yyyy-MM-dd"}. */
    var examDates by mutableStateOf(mapOf<Long, LocalDate>()); private set
    /** Card language per top-level deck, in the collection's config under "kartei.deckLang" as {"deckId": "de"}; no entry means automatic. */
    var deckLang by mutableStateOf(mapOf<Long, String>()); private set
    var importMessage by mutableStateOf<String?>(null); private set
    val mediaFolder: File get() = File(getApplication<Application>().filesDir, "collection/media")

    /** Average answer time of the last 30 days, or 8 s until there are 50 answers. */
    var secondsPerCard by mutableStateOf(8.0); private set
    /** Days with at least one answer, as offsets from today (0 = today, -1 = yesterday), over the last five weeks. */
    var studiedDays by mutableStateOf(setOf<Int>()); private set
    /** Share of review cards remembered on the first try over the last 30 days; null until there are 20 such reviews. */
    var retention by mutableStateOf<Double?>(null); private set
    var retentionTarget by mutableStateOf(0.9); private set

    val cardsToday get() = new + learning + due
    val minutesToday get() = if (cardsToday == 0) 0 else maxOf(1, ((cardsToday * secondsPerCard + 30) / 60).toInt())

    init { viewModelScope.launch(Dispatchers.IO) { load() } }

    private fun tree(backend: Backend) = backend.call(
        DecksMethods.deckTree,
        anki.decks.DeckTreeRequest.newBuilder().setNow(System.currentTimeMillis() / 1000).build(),
        anki.decks.DeckTreeNode.parser(),
    )

    private fun load() {
        try {
            val ctx = getApplication<Application>()
            val dir = File(ctx.filesDir, "collection").apply { mkdirs() }
            File(dir, "media").mkdirs()
            val backend = Backend().also { this.backend = it }
            ankiVersion = Backend.ankiVersion
            backend.run(
                CollectionMethods.openCollection,
                anki.collection.OpenCollectionRequest.newBuilder()
                    .setCollectionPath(File(dir, "collection.anki2").path)
                    .setMediaFolderPath(File(dir, "media").path)
                    .setMediaDbPath(File(dir, "media.db").path).build(),
            )
            // First run starts empty: onboarding asks which course decks to bring in (Courses.kt).
            val root = tree(backend)
            show(root)
            loadExams(backend)
            loadLangs(backend)
            phase = Phase.Ready
        } catch (e: Throwable) {
            phase = Phase.Failed(e.message ?: e.toString())
        }
    }

    private fun loadExams(backend: Backend) {
        val json = runCatching {
            backend.call(ConfigMethods.getConfigJson, anki.generic.String.newBuilder().setVal(EXAM_KEY).build(), anki.generic.Json.parser())
        }.getOrNull() ?: return
        val obj = runCatching { JSONObject(json.json.toStringUtf8()) }.getOrNull() ?: return
        examDates = obj.keys().asSequence().mapNotNull { k ->
            val id = k.toLongOrNull(); val day = runCatching { LocalDate.parse(obj.getString(k)) }.getOrNull()
            if (id != null && day != null) id to day else null
        }.toMap()
    }

    private fun loadLangs(backend: Backend) {
        val json = runCatching {
            backend.call(ConfigMethods.getConfigJson, anki.generic.String.newBuilder().setVal(LANG_KEY).build(), anki.generic.Json.parser())
        }.getOrNull() ?: return
        val obj = runCatching { JSONObject(json.json.toStringUtf8()) }.getOrNull() ?: return
        deckLang = obj.keys().asSequence().mapNotNull { k ->
            val id = k.toLongOrNull(); val lang = obj.optString(k)
            if (id != null && lang.isNotEmpty()) id to lang else null
        }.toMap()
    }

    /** The card language of [deck]: that of its top-level ancestor, or null when none is set. */
    fun langFor(deck: Long): String? = deckLang[DeckRows.topLevel(rows, deck) ?: deck]

    /** Set or clear (null: automatic) the card language of a top-level deck. */
    fun setLang(lang: String?, deck: Long) = setLangs(mapOf(deck to lang))

    private fun setLangs(changes: Map<Long, String?>) {
        val backend = backend ?: return
        val langs = deckLang.toMutableMap().apply { changes.forEach { (deck, lang) -> if (lang == null) remove(deck) else put(deck, lang) } }
        if (langs == deckLang) return
        deckLang = langs
        val obj = JSONObject().apply { langs.forEach { (k, v) -> put(k.toString(), v) } }
        viewModelScope.launch(Dispatchers.IO) {
            runCatching {
                backend.run(ConfigMethods.setConfigJsonNoUndo, anki.config.SetConfigJsonRequest.newBuilder().setKey(LANG_KEY)
                    .setValueJson(com.google.protobuf.ByteString.copyFromUtf8(obj.toString())).setUndoable(false).build())
            }
        }
    }

    /** Set or clear (null) the exam date of a deck. */
    fun setExam(date: LocalDate?, deck: Long) {
        val backend = backend ?: return
        val dates = examDates.toMutableMap().apply { if (date == null) remove(deck) else put(deck, date) }
        examDates = dates
        val obj = JSONObject().apply { dates.forEach { (k, v) -> put(k.toString(), v.toString()) } }
        viewModelScope.launch(Dispatchers.IO) {
            runCatching {
                backend.run(ConfigMethods.setConfigJsonNoUndo, anki.config.SetConfigJsonRequest.newBuilder().setKey(EXAM_KEY)
                    .setValueJson(com.google.protobuf.ByteString.copyFromUtf8(obj.toString())).setUndoable(false).build())
            }
        }
    }

    /** Bring in course decks from the assets (onboarding's picker or Home's Add cards), then [done] on the main thread. */
    fun importCourses(courses: List<Course>, done: (Int) -> Unit = {}) {
        val backend = backend ?: return done(0)
        if (courses.isEmpty()) return done(0)
        val ctx = getApplication<Application>()
        importMessage = "Importing " + (if (courses.size == 1) courses[0].title else "${courses.size} courses")
        viewModelScope.launch(Dispatchers.IO) {
            val added = try {
                CourseCatalogue.importCourses(ctx, backend, courses) { i, n -> if (n > 1) importMessage = "Importing deck $i of $n" }
                    .also { importMessage = "Added $it notes." }
            } catch (e: Throwable) {
                importMessage = "Could not import: ${e.message ?: e}"; 0
            }
            runCatching {
                val root = tree(backend)
                show(root)
                // A course knows its language; a choice already made for that deck is kept.
                setLangs(courses.mapNotNull { c -> root.childrenList.firstOrNull { it.name == c.root }?.deckId?.takeIf { it !in deckLang }?.let { it to c.lang } }.toMap())
            }
            kotlinx.coroutines.withContext(Dispatchers.Main) { done(added) }
        }
    }

    /** Delete a deck with its subdecks and cards (Anki's RemoveDecks), then show what went. */
    fun deleteDeck(row: DeckRow) {
        val backend = backend ?: return
        viewModelScope.launch(Dispatchers.IO) {
            importMessage = try {
                val n = backend.call(DecksMethods.removeDecks, anki.decks.DeckIds.newBuilder().addDids(row.id).build(),
                    anki.collection.OpChangesWithCount.parser()).count
                "Deleted ${row.name} and $n cards."
            } catch (e: Throwable) {
                "Could not delete ${row.name}: ${e.message ?: e}"
            }
            runCatching { show(tree(backend)) }
        }
    }

    fun importPackage(uri: Uri) {
        val backend = backend ?: return
        val ctx = getApplication<Application>()
        importMessage = "Importing deck"
        viewModelScope.launch(Dispatchers.IO) {
            val local = File(ctx.cacheDir, "import-${System.currentTimeMillis()}.apkg")
            try {
                ctx.contentResolver.openInputStream(uri)!!.use { input -> local.outputStream().use { input.copyTo(it) } }
                val result = backend.call(
                    ImportExportMethods.importAnkiPackage,
                    anki.import_export.ImportAnkiPackageRequest.newBuilder().setPackagePath(local.path)
                        .setOptions(anki.import_export.ImportAnkiPackageOptions.newBuilder().setMergeNotetypes(true).setWithScheduling(true)).build(),
                    anki.import_export.ImportResponse.parser(),
                )
                val updated = result.log.updatedCount
                importMessage = "Added ${result.log.newCount} notes" + (if (updated > 0) ", updated $updated" else "") + "."
                show(tree(backend))
            } catch (e: Throwable) {
                importMessage = "Could not import: ${e.message ?: e}"
            } finally {
                local.delete()
            }
        }
    }

    /** Read the deck tree again, after a study session changed the counts. */
    fun refresh() {
        val backend = backend ?: return
        viewModelScope.launch(Dispatchers.IO) { runCatching { show(tree(backend)) } }
    }

    /** Review history from Anki's stats service: which days had answers, average answer time, true retention. */
    private fun history(backend: Backend) {
        val g = runCatching {
            backend.call(StatsMethods.graphs, anki.stats.GraphsRequest.newBuilder().setSearch("").setDays(35).build(), anki.stats.GraphsResponse.parser())
        }.getOrNull() ?: return
        val days = mutableSetOf<Int>()
        var answers = 0; var millis = 0L
        for ((day, c) in g.reviews.countMap) {
            val n = c.learn + c.relearn + c.young + c.mature + c.filtered
            if (n > 0 && day > -35) days += day
            if (day > -30) answers += n
        }
        for ((day, t) in g.reviews.timeMap) if (day > -30) millis += (t.learn + t.relearn + t.young + t.mature + t.filtered).toLong()
        studiedDays = days
        if (answers >= 50) secondsPerCard = (millis.toDouble() / answers / 1000).coerceIn(2.0, 60.0)
        val m = g.trueRetention.month
        val passed = m.youngPassed + m.maturePassed
        val total = passed + m.youngFailed + m.matureFailed
        retention = if (total >= 20) passed.toDouble() / total else null
        runCatching {
            backend.call(DeckConfigMethods.getDeckConfig, anki.deck_config.DeckConfigId.newBuilder().setDcid(1).build(), anki.deck_config.DeckConfig.parser())
        }.getOrNull()?.config?.desiredRetention?.takeIf { it > 0 }?.let { retentionTarget = it.toDouble() }
    }

    private fun show(root: anki.decks.DeckTreeNode) {
        backend?.let { history(it) }
        run {
            val out = mutableListOf<DeckRow>()
            fun walk(n: anki.decks.DeckTreeNode, depth: Int) {
                // Like Anki, leave out an empty top-level deck (the unused "Default").
                if (depth == 0 && n.totalIncludingChildren == 0) return
                out += DeckRow(n.deckId, n.name, depth, n.newCount, n.learnCount, n.reviewCount)
                n.childrenList.forEach { walk(it, depth + 1) }
            }
            root.childrenList.forEach { walk(it, 0) }
            val top = root.childrenList.filter { it.totalIncludingChildren > 0 }
            rows = out
            topLevelDecks = top.size
            new = top.sumOf { it.newCount }
            learning = top.sumOf { it.learnCount }
            due = top.sumOf { it.reviewCount }
        }
    }
}
