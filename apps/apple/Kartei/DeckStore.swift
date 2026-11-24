// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import Observation

struct DeckRow: Identifiable {
    let id: Int64
    var exam: Date? = nil
    let name: String
    let depth: Int
    let hasChildren: Bool
    let filtered: Bool
    let new: Int
    let learning: Int
    let due: Int
}

extension Array where Element == DeckRow {
    /// The deck "Study now" opens: the first in the list that has something to study today (a parent counts its subdecks).
    var firstToStudy: DeckRow? { first { $0.new + $0.learning + $0.due > 0 } }
}

@Observable
final class DeckStore {
    enum Phase { case loading(String), ready, failed(String) }

    var phase: Phase = .loading("Opening your collection")
    var rows: [DeckRow] = []
    var totals = (new: 0, learning: 0, due: 0)
    var topLevelDecks = 0

    /// Seconds per card for the time estimate: the average answer time of the last 30 days, or 8 s until there are 50 answers.
    var secondsPerCard = 8.0
    /// Days with at least one answer, as offsets from today (0 = today, -1 = yesterday), over the last five weeks.
    var studiedDays: Set<Int> = []
    /// Share of review cards remembered on the first try over the last 30 days; nil until there are 20 such reviews.
    var retention: Double?
    var retentionTarget = 0.9
    var minutesToday: Int { let cards = totals.new + totals.learning + totals.due; return cards == 0 ? 0 : max(1, Int((Double(cards) * secondsPerCard + 30) / 60)) }
    var cardsToday: Int { totals.new + totals.learning + totals.due }

    /// Exam dates per deck, kept in the collection's config under "kartei.examDates" as {"deckId": "yyyy-MM-dd"}.
    var examDates: [Int64: Date] = [:]
    /// Card language per top-level deck (BCP 47, e.g. "de"), kept in the collection's config under "kartei.deckLang"
    /// as {"deckId": "de"}. Subdecks follow their top-level deck. VoiceOver reads the cards in this language.
    var deckLanguages: [Int64: String] = [:]
    /// Courses imported since the last refresh; their decks get their language once the new rows are in.
    @ObservationIgnored private var importedCourses: [Course] = []
    var importMessage: String?

    private(set) var backend: Backend?
    private(set) var mediaFolder: URL?

    func load() {
        Task.detached(priority: .userInitiated) { [self] in
            do {
                let backend = try Backend()
                var dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("Kartei", isDirectory: true)
                #if DEBUG
                // Tests can point each run at its own collection: KARTEI_DATA_DIR=/some/folder
                if let custom = ProcessInfo.processInfo.environment["KARTEI_DATA_DIR"] { dir = URL(fileURLWithPath: custom, isDirectory: true) }
                #endif
                try FileManager.default.createDirectory(at: dir.appendingPathComponent("media"), withIntermediateDirectories: true)
                var open = Anki_Collection_OpenCollectionRequest()
                open.collectionPath = dir.appendingPathComponent("collection.anki2").path
                open.mediaFolderPath = dir.appendingPathComponent("media").path
                open.mediaDbPath = dir.appendingPathComponent("media.db").path
                try backend.run(CollectionMethods.openCollection, open)

                // First run starts empty: onboarding asks which course decks to bring in (Courses.swift).
                let tree = try Self.tree(backend)
                let rows = Self.flatten(tree)
                let top = tree.children.filter { $0.totalIncludingChildren > 0 }
                let history = Self.history(backend)
                let exams = Self.loadExams(backend)
                let languages = Self.loadLanguages(backend)
                let media = dir.appendingPathComponent("media")
                await MainActor.run {
                    self.backend = backend
                    self.mediaFolder = media
                    self.rows = rows
                    self.topLevelDecks = top.count
                    self.totals = (top.reduce(0) { $0 + Int($1.newCount) }, top.reduce(0) { $0 + Int($1.learnCount) }, top.reduce(0) { $0 + Int($1.reviewCount) })
                    self.apply(history)
                    self.examDates = exams
                    self.deckLanguages = languages
                    self.phase = .ready
                    #if DEBUG
                    self.runTestHooks()
                    #endif
                }
            } catch {
                await MainActor.run { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    /// Read the deck tree again, after a study session changed the counts.
    func refresh() {
        guard let backend else { return }
        Task.detached(priority: .userInitiated) { [self] in
            guard let tree = try? Self.tree(backend) else { return }
            let rows = Self.flatten(tree)
            let top = tree.children.filter { $0.totalIncludingChildren > 0 }
            let history = Self.history(backend)
            await MainActor.run {
                self.apply(history)
                self.rows = rows
                if !self.importedCourses.isEmpty {
                    self.adoptCourseLanguages(self.importedCourses)
                    self.importedCourses = []
                }
                self.topLevelDecks = top.count
                self.totals = (top.reduce(0) { $0 + Int($1.newCount) }, top.reduce(0) { $0 + Int($1.learnCount) }, top.reduce(0) { $0 + Int($1.reviewCount) })
            }
        }
    }

    private static let languageKey = "kartei.deckLang"

    private static func loadLanguages(_ backend: Backend) -> [Int64: String] {
        var key = Anki_Generic_String()
        key.val = languageKey
        guard let json: Anki_Generic_Json = try? backend.call(ConfigMethods.getConfigJson, key),
              let map = try? JSONSerialization.jsonObject(with: json.json) as? [String: String] else { return [:] }
        return Dictionary(uniqueKeysWithValues: map.compactMap { id, lang in Int64(id).map { ($0, lang) } })
    }

    /// Set or clear (nil: automatic) the card language of a top-level deck.
    func setLanguage(_ language: String?, for deck: Int64) {
        guard let backend else { return }
        var languages = deckLanguages
        languages[deck] = language
        deckLanguages = languages
        let map = Dictionary(uniqueKeysWithValues: languages.map { (String($0.key), $0.value) })
        Task.detached {
            var req = Anki_Config_SetConfigJsonRequest()
            req.key = Self.languageKey
            req.valueJson = (try? JSONSerialization.data(withJSONObject: map)) ?? Data("{}".utf8)
            req.undoable = false
            let _: Anki_Generic_Empty? = try? backend.call(ConfigMethods.setConfigJsonNoUndo, req)
        }
    }

    /// The top-level deck a row belongs to: rows are in tree order, so it is the nearest depth-0 row at or above it.
    func topLevel(of deck: Int64) -> DeckRow? {
        guard let index = rows.firstIndex(where: { $0.id == deck }) else { return nil }
        return rows[...index].last { $0.depth == 0 }
    }

    /// The language of a deck's cards, from its top-level deck; nil when none is set.
    func language(of deck: Int64) -> String? {
        topLevel(of: deck).flatMap { deckLanguages[$0.id] }
    }

    /// Give freshly imported course decks their language, unless the person already chose one.
    @MainActor func adoptCourseLanguages(_ courses: [Course]) {
        for course in courses {
            guard let language = course.language, let row = rows.first(where: { $0.depth == 0 && $0.name == course.root }),
                  deckLanguages[row.id] == nil else { continue }
            setLanguage(language, for: row.id)
        }
    }

    private static let examKey = "kartei.examDates"
    private static let dayFormat: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()

    private static func loadExams(_ backend: Backend) -> [Int64: Date] {
        var key = Anki_Generic_String()
        key.val = examKey
        guard let json: Anki_Generic_Json = try? backend.call(ConfigMethods.getConfigJson, key),
              let map = try? JSONSerialization.jsonObject(with: json.json) as? [String: String] else { return [:] }
        var out: [Int64: Date] = [:]
        for (id, day) in map { if let id = Int64(id), let date = dayFormat.date(from: day) { out[id] = date } }
        return out
    }

    /// Set or clear (nil) the exam date of a deck.
    func setExam(_ date: Date?, for deck: Int64) {
        guard let backend else { return }
        var dates = examDates
        dates[deck] = date
        examDates = dates
        let map = Dictionary(uniqueKeysWithValues: dates.map { (String($0.key), Self.dayFormat.string(from: $0.value)) })
        Task.detached {
            var req = Anki_Config_SetConfigJsonRequest()
            req.key = Self.examKey
            req.valueJson = (try? JSONSerialization.data(withJSONObject: map)) ?? Data("{}".utf8)
            req.undoable = false
            let _: Anki_Generic_Empty? = try? backend.call(ConfigMethods.setConfigJsonNoUndo, req)
        }
    }

    /// Bring in course decks shipped with the app (onboarding's course picker, or Home's "Add a course deck").
    @MainActor func importCourses(_ courses: [Course], done: @escaping @MainActor (Int) -> Void = { _ in }) {
        guard let backend, !courses.isEmpty else { done(0); return }
        importMessage = "Importing \(courses.count == 1 ? courses[0].title : "\(courses.count) courses")"
        Task.detached(priority: .userInitiated) { [self] in
            do {
                let added = try CourseCatalogue.importCourses(courses, backend: backend) { i, n in
                    if n > 1 { Task { @MainActor in self.importMessage = "Importing deck \(i) of \(n)" } }
                }
                await MainActor.run { self.importMessage = "Added \(added) notes."; self.importedCourses += courses }
                self.refresh()
                await MainActor.run { done(added) }
            } catch {
                await MainActor.run { self.importMessage = "Could not import: \(error.localizedDescription)"; done(0) }
            }
        }
    }

    /// Delete a deck with its subdecks and cards (Anki's RemoveDecks), then say what went.
    func deleteDeck(_ row: DeckRow) {
        guard let backend else { return }
        Task.detached(priority: .userInitiated) { [self] in
            var req = Anki_Decks_DeckIds()
            req.dids = [row.id]
            let message: String
            do {
                let result: Anki_Collection_OpChangesWithCount = try backend.call(DecksMethods.removeDecks, req)
                message = "Deleted \(row.name) and \(result.count) cards."
            } catch {
                message = "Could not delete \(row.name): \(error.localizedDescription)"
            }
            await MainActor.run { self.importMessage = message }
            self.refresh()
        }
    }

    /// Import an .apkg the person picked, then show the new decks.
    func importPackage(_ url: URL) {
        guard let backend else { return }
        importMessage = "Importing \(url.deletingPathExtension().lastPathComponent)"
        Task.detached(priority: .userInitiated) { [self] in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                // Copy first: the picked file may live in a provider the backend cannot read directly.
                let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".apkg")
                try FileManager.default.copyItem(at: url, to: local)
                defer { try? FileManager.default.removeItem(at: local) }
                var req = Anki_ImportExport_ImportAnkiPackageRequest()
                req.packagePath = local.path
                req.options.mergeNotetypes = true
                req.options.withScheduling = true
                let result: Anki_ImportExport_ImportResponse = try backend.call(ImportExportMethods.importAnkiPackage, req)
                let added = result.log.new.count, updated = result.log.updated.count
                await MainActor.run { self.importMessage = "Added \(added) notes" + (updated > 0 ? ", updated \(updated)" : "") + "." }
                self.refresh()
            } catch {
                await MainActor.run { self.importMessage = "Could not import: \(error.localizedDescription)" }
            }
        }
    }

    #if DEBUG
    /// Test hooks, debug builds only: KARTEI_TEST_IMPORT=/path/deck.apkg, KARTEI_TEST_EXAM="Deck name=yyyy-MM-dd".
    private func runTestHooks() {
        let env = ProcessInfo.processInfo.environment
        if let spec = env["KARTEI_TEST_EXAM"], let eq = spec.lastIndex(of: "=") {
            let name = String(spec[..<eq]), day = String(spec[spec.index(after: eq)...])
            if let row = rows.first(where: { $0.name == name }), let date = Self.dayFormat.date(from: day) { setExam(date, for: row.id) }
        }
        if let path = env["KARTEI_TEST_IMPORT"] { importPackage(URL(fileURLWithPath: path)) }
    }
    #endif

    struct History { var days: Set<Int> = []; var secondsPerCard: Double?; var retention: Double?; var target: Double? }

    private func apply(_ h: History) {
        studiedDays = h.days
        if let s = h.secondsPerCard { secondsPerCard = s }
        retention = h.retention
        if let t = h.target { retentionTarget = t }
    }

    /// Review history from Anki's stats service: which days had answers, average answer time, true retention.
    private static func history(_ backend: Backend) -> History {
        var h = History()
        var req = Anki_Stats_GraphsRequest()
        req.search = ""
        req.days = 35
        guard let g: Anki_Stats_GraphsResponse = try? backend.call(StatsMethods.graphs, req) else { return h }
        var answers = 0, millis = 0
        for (day, c) in g.reviews.count {
            let n = Int(c.learn + c.relearn + c.young + c.mature + c.filtered)
            if n > 0 && day > -35 { h.days.insert(Int(day)) }
            if day > -30 { answers += n }
        }
        for (day, t) in g.reviews.time where day > -30 { millis += Int(t.learn + t.relearn + t.young + t.mature + t.filtered) }
        if answers >= 50 { h.secondsPerCard = min(60, max(2, Double(millis) / Double(answers) / 1000)) }
        let m = g.trueRetention.month
        let passed = Int(m.youngPassed + m.maturePassed), total = passed + Int(m.youngFailed + m.matureFailed)
        if total >= 20 { h.retention = Double(passed) / Double(total) }
        var dc = Anki_DeckConfig_DeckConfigId()
        dc.dcid = 1
        if let config: Anki_DeckConfig_DeckConfig = try? backend.call(DeckConfigMethods.getDeckConfig, dc), config.config.desiredRetention > 0 {
            h.target = Double(config.config.desiredRetention)
        }
        return h
    }

    private static func tree(_ backend: Backend) throws -> Anki_Decks_DeckTreeNode {
        var req = Anki_Decks_DeckTreeRequest()
        req.now = Int64(Date().timeIntervalSince1970)
        return try backend.call(DecksMethods.deckTree, req)
    }

    private static func flatten(_ root: Anki_Decks_DeckTreeNode) -> [DeckRow] {
        var out: [DeckRow] = []
        func walk(_ node: Anki_Decks_DeckTreeNode, _ depth: Int) {
            // Like Anki, leave out an empty top-level deck (the unused "Default").
            if depth == 0 && node.totalIncludingChildren == 0 { return }
            out.append(DeckRow(id: node.deckID, name: node.name, depth: depth, hasChildren: !node.children.isEmpty, filtered: node.filtered,
                               new: Int(node.newCount), learning: Int(node.learnCount), due: Int(node.reviewCount)))
            for child in node.children { walk(child, depth + 1) }
        }
        for child in root.children { walk(child, 0) }
        return out
    }
}
