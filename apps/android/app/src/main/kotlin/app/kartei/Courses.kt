// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import android.content.Context
import app.kartei.core.Backend
import app.kartei.core.DecksMethods
import app.kartei.core.ImportExportMethods
import java.io.File

/** A course whose deck ships in the app's assets (content/courses/build_decks.py builds the course-*.apkg files). */
data class Course(
    val id: String,
    val title: String,
    val detail: String,
    /** Asset paths of the packages. */
    val assets: List<String>,
    /** The top-level deck the package creates; the first session searches inside it. */
    val root: String,
    val notes: Int,
    /** Language of the cards as a BCP 47 tag; set for the root deck on import so TalkBack reads them in the right voice. */
    val lang: String = "en",
)

/** Same catalogue as the Apple app (Courses.swift). */
object CourseCatalogue {
    val gdp = Course("gdp", "Grundlagen der Programmierung",
        "Java, auf Deutsch. 11 Vorlesungen, 293 Karten, davon 67 mit getippter Ausgabe.",
        listOf("courses/course-gdp.apkg"), "Grundlagen der Programmierung WS26/27", 293, lang = "de")
    val gdpEnglish = Course("gdp-en", "Programming Fundamentals (GdP), English",
        "The same Java course in English. 11 lectures, 293 cards.",
        listOf("courses/course-gdp-en.apkg"), "Programming Fundamentals (GdP) WS26/27 · English", 293)
    val coopsys = Course("coopsys", "Cooperation Systems",
        "CSCW and groupware, in English. 11 lectures, 330 cards.",
        listOf("courses/course-coopsys.apkg"), "Cooperation Systems WS26/27", 330)
    val all = listOf(gdp, gdpEnglish, coopsys)

    const val FIRST_TAG = "bergmoench::first"
    const val FIRST_SESSION_NAME = "Your first five cards"

    fun firstSearch(course: Course): String = "tag:$FIRST_TAG \"deck:${course.root.replace("\"", "\\\"")}\""

    /** The first chosen course in catalogue order; it supplies the first-session cards. */
    fun firstSessionCourse(chosen: Collection<Course>): Course? = all.firstOrNull { it in chosen }

    /** Import the courses' packages from the assets. Returns the notes added. Call off the main thread. */
    fun importCourses(ctx: Context, backend: Backend, courses: List<Course>, progress: (Int, Int) -> Unit = { _, _ -> }): Int {
        val files = courses.flatMap { it.assets }
        var added = 0
        files.forEachIndexed { i, asset ->
            progress(i + 1, files.size)
            val local = File(ctx.cacheDir, "course-import-${i}.apkg")
            try {
                ctx.assets.open(asset).use { input -> local.outputStream().use { input.copyTo(it) } }
                val result = backend.call(
                    ImportExportMethods.importAnkiPackage,
                    anki.import_export.ImportAnkiPackageRequest.newBuilder().setPackagePath(local.path)
                        .setOptions(anki.import_export.ImportAnkiPackageOptions.newBuilder().setMergeNotetypes(true)).build(),
                    anki.import_export.ImportResponse.parser(),
                )
                added += result.log.newCount
            } finally {
                local.delete()
            }
        }
        return added
    }

    /** A filtered deck with the course's five first cards; grades count, and removing it sends the cards home. */
    fun makeFirstSession(backend: Backend, course: Course): Long? = runCatching {
        val fresh = backend.call(DecksMethods.getOrCreateFilteredDeck, anki.decks.DeckId.newBuilder().setDid(0).build(),
            anki.decks.FilteredDeckForUpdate.parser())
        val term = anki.decks.Deck.Filtered.SearchTerm.newBuilder().setSearch(firstSearch(course)).setLimit(5)
            .setOrder(anki.decks.Deck.Filtered.SearchTerm.Order.ADDED)
        val config = fresh.config.toBuilder().clearSearchTerms().addSearchTerms(term).setReschedule(true)
        val deck = fresh.toBuilder().setName(FIRST_SESSION_NAME).setConfig(config).setAllowEmpty(false).build()
        backend.call(DecksMethods.addOrUpdateFilteredDeck, deck, anki.collection.OpChangesWithId.parser()).id
    }.getOrNull()

    fun removeFirstSession(backend: Backend, id: Long) {
        runCatching {
            backend.call(DecksMethods.removeDecks, anki.decks.DeckIds.newBuilder().addDids(id).build(), anki.collection.OpChangesWithCount.parser())
        }
    }
}
