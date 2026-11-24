// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

/// A course whose deck ships inside the app (content/courses/build_decks.py builds the course-*.apkg files).
struct Course: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    /// Package names in the app bundle, without .apkg.
    let files: [String]
    /// The top-level deck the package creates; the first session searches inside it.
    let root: String
    /// Notes in the package, so the picker can say how many cards come in before importing.
    let notes: Int
    /// BCP 47 language of the cards, set on the deck after import so VoiceOver reads them in the right voice.
    var language: String? = nil
}

enum CourseCatalogue {
    static let gdp = Course(id: "gdp", title: "Grundlagen der Programmierung",
                            detail: "Java, auf Deutsch. 11 Vorlesungen, 293 Karten, davon 67 mit getippter Ausgabe.",
                            files: ["course-gdp"], root: "Grundlagen der Programmierung WS26/27", notes: 293, language: "de")
    static let gdpEnglish = Course(id: "gdp-en", title: "Programming Fundamentals (GdP), English",
                                   detail: "The same Java course in English. 11 lectures, 293 cards.",
                                   files: ["course-gdp-en"], root: "Programming Fundamentals (GdP) WS26/27 · English", notes: 293, language: "en")
    static let coopsys = Course(id: "coopsys", title: "Cooperation Systems",
                                detail: "CSCW and groupware, in English. 11 lectures, 330 cards.",
                                files: ["course-coopsys"], root: "Cooperation Systems WS26/27", notes: 330, language: "en")
    /// What the picker offers, in this order.
    static let all: [Course] = [gdp, gdpEnglish, coopsys]

    static let firstTag = "bergmoench::first"
    static let firstSessionName = "Your first five cards"

    static func package(_ name: String, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: name, withExtension: "apkg")
    }

    /// Import the chosen courses' packages from the app bundle. Returns the number of notes added.
    @discardableResult
    static func importCourses(_ courses: [Course], backend: Backend, bundle: Bundle = .main,
                              progress: (Int, Int) -> Void = { _, _ in }) throws -> Int {
        let files = courses.flatMap(\.files)
        var added = 0
        for (i, name) in files.enumerated() {
            progress(i + 1, files.count)
            guard let url = package(name, in: bundle) else { throw BackendFailure(message: "The app is missing \(name).apkg") }
            var req = Anki_ImportExport_ImportAnkiPackageRequest()
            req.packagePath = url.path
            req.options.mergeNotetypes = true
            let result: Anki_ImportExport_ImportResponse = try backend.call(ImportExportMethods.importAnkiPackage, req)
            added += result.log.new.count
        }
        return added
    }

    /// The search for a course's hand-picked first cards.
    static func firstSearch(_ course: Course) -> String {
        "tag:\(firstTag) \"deck:\(course.root.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    /// The first course of the selection that has first-session cards.
    static func firstSessionCourse(_ chosen: [Course]) -> Course? {
        all.filter { c in chosen.contains(c) }.first { !$0.files.isEmpty }
    }

    /// A filtered deck with the course's five first cards, studied like any other deck. Grades count and the
    /// cards go home when the deck is removed (removeFirstSession). Nil when the course has no such cards.
    static func makeFirstSession(_ course: Course, backend: Backend) throws -> Int64? {
        var ids = Anki_Decks_DeckId()
        ids.did = 0
        var deck: Anki_Decks_FilteredDeckForUpdate = try backend.call(DecksMethods.getOrCreateFilteredDeck, ids)
        deck.name = firstSessionName
        var term = Anki_Decks_Deck.Filtered.SearchTerm()
        term.search = firstSearch(course)
        term.limit = 5
        term.order = .added
        deck.config.searchTerms = [term]
        deck.config.reschedule = true
        deck.allowEmpty = false
        guard let result: Anki_Collection_OpChangesWithId = try? backend.call(DecksMethods.addOrUpdateFilteredDeck, deck) else { return nil }
        return result.id
    }

    /// First-session decks nobody is studying any more: the app was closed in the middle of the guided session,
    /// so the deck was never removed and its five cards never went home.
    static func leftoverFirstSessions(_ rows: [DeckRow]) -> [Int64] {
        rows.filter { $0.filtered && $0.depth == 0 && $0.name == firstSessionName }.map(\.id)
    }

    /// Remove the first-session deck; its cards return to their course decks with their progress.
    static func removeFirstSession(_ id: Int64, backend: Backend) {
        var req = Anki_Decks_DeckIds()
        req.dids = [id]
        let _: Anki_Collection_OpChangesWithCount? = try? backend.call(DecksMethods.removeDecks, req)
    }
}
