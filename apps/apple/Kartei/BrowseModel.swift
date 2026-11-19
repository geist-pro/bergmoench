// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import Observation
import SwiftUI

/// Quick filters above the browse results. Each is one Anki search term, so the search box keeps working as in Anki.
enum BrowseFilter: String, CaseIterable, Identifiable {
    case due, new, flagged, suspended, slipping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .due: "Due today"
        case .new: "New"
        case .flagged: "Flagged"
        case .suspended: "Suspended"
        case .slipping: "Keep slipping"
        }
    }

    /// Anki search syntax. "Keep slipping" is Anki's leech tag: cards forgotten 8 times (the leech threshold).
    var search: String {
        switch self {
        case .due: "is:due"
        case .new: "is:new"
        case .flagged: "-flag:0"
        case .suspended: "is:suspended"
        case .slipping: "tag:leech"
        }
    }
}

enum BrowseSearch {
    /// Combine what the person typed (any Anki search) with the chosen quick filter. The typed part is wrapped in
    /// parentheses so an "or" in it cannot swallow the filter.
    static func build(text: String, filter: BrowseFilter?) -> String {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !typed.isEmpty { parts.append(filter == nil ? typed : "(\(typed))") }
        if let filter { parts.append(filter.search) }
        return parts.joined(separator: " ")
    }
}

/// When a card is due and what state it is in, worded for the browse list.
struct CardStatus: Equatable {
    var due: String
    var state: String
    var suspended = false

    /// Card fields as Anki stores them: ctype 0 new, 1 learning, 2 review, 3 relearning;
    /// queue -1 suspended, -2/-3 buried, 0 new, 1 learning (due is a timestamp), 2 review and 3 day-learning (due is a day number).
    static func of(ctype: UInt32, queue: Int32, due: Int32, originalDue: Int32 = 0, inFilteredDeck: Bool = false,
                   daysElapsed: Int, nextDayAt: Int64, now: Date = .now, calendar: Calendar = .current) -> CardStatus {
        let state: String
        switch ctype {
        case 0: state = "new"
        case 1: state = "learning"
        case 3: state = "relearning"
        default: state = "review"
        }
        if queue == -1 { return CardStatus(due: "paused", state: "suspended", suspended: true) }
        if queue == -2 || queue == -3 { return CardStatus(due: "tomorrow", state: "buried") }
        if ctype == 0 || queue == 0 { return CardStatus(due: "not seen", state: state) }
        if queue == 1 {
            // Intraday learning: due is a Unix timestamp.
            let date = Date(timeIntervalSince1970: TimeInterval(due))
            if Int64(due) < nextDayAt { return CardStatus(due: date <= now ? "now" : "today", state: state) }
            return CardStatus(due: dayText(Int((Int64(due) - nextDayAt) / 86_400) + 1, now: now, calendar: calendar), state: state)
        }
        let day = inFilteredDeck && originalDue != 0 ? originalDue : due
        return CardStatus(due: dayText(Int(day) - daysElapsed, now: now, calendar: calendar), state: state)
    }

    /// Days from today: 0 today, 1 tomorrow, under a week "in 3 d", later the date; past days are late.
    static func dayText(_ days: Int, now: Date = .now, calendar: Calendar = .current) -> String {
        switch days {
        case ..<0: return "\(-days) d late"
        case 0: return "today"
        case 1: return "tomorrow"
        case 2..<7: return "in \(days) d"
        default:
            let date = calendar.date(byAdding: .day, value: days, to: now) ?? now
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: now, toGranularity: .year) ? "d MMM" : "d MMM yyyy")
            return f.string(from: date)
        }
    }
}

/// One row of the result list, filled lazily as it scrolls into view.
struct BrowseRow: Equatable {
    var question: String
    var deck: String
    var tags: String
    var status: CardStatus
    var flag: Int
}

/// Browse: search cards with Anki's own search, list them by due date, act on them.
@Observable
final class BrowseModel {
    var text = ""
    var filter: BrowseFilter?
    private(set) var ids: [Int64] = []
    private(set) var rows: [Int64: BrowseRow] = [:]
    private(set) var error: String?
    private(set) var searching = false
    var message: String?

    @ObservationIgnored private var backend: Backend?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loading: Set<Int64> = []
    @ObservationIgnored private var columnsSet = false

    var search: String { BrowseSearch.build(text: text, filter: filter) }

    func attach(_ backend: Backend?) {
        guard self.backend !== backend else { return }
        self.backend = backend
        columnsSet = false
        run()
    }

    /// Run the current search. Results come back sorted by due date, like Anki's browser sorted on "Due".
    func run() {
        guard let backend else { return }
        generation += 1
        let gen = generation, query = search
        searching = true
        Task.detached(priority: .userInitiated) { [self] in
            let result: Result<[Int64], Error> = Result { try Self.searchCards(backend, query) }
            await MainActor.run {
                guard gen == self.generation else { return }
                self.searching = false
                switch result {
                case .success(let ids): self.ids = ids; self.error = nil
                case .failure(let e): self.ids = []; self.error = e.localizedDescription
                }
                self.rows = [:]
                self.loading = []
            }
        }
    }

    static func searchCards(_ backend: Backend, _ query: String) throws -> [Int64] {
        var req = Anki_Search_SearchRequest()
        req.search = query
        var order = Anki_Search_SortOrder.Builtin()
        order.column = "cardDue"
        req.order.builtin = order
        let resp: Anki_Search_SearchResponse = try backend.call(SearchMethods.searchCards, req)
        return resp.ids
    }

    /// Load a row when it appears; also loads the next few so scrolling stays smooth.
    func needRow(_ id: Int64) {
        guard let backend, rows[id] == nil, !loading.contains(id) else { return }
        let start = ids.firstIndex(of: id) ?? 0
        let batch = ids[start..<min(ids.count, start + 30)].filter { rows[$0] == nil && !loading.contains($0) }
        loading.formUnion(batch)
        let gen = generation, setColumns = !columnsSet
        columnsSet = true
        Task.detached(priority: .userInitiated) { [self] in
            if setColumns { try? Self.setColumns(backend) }
            let timing: Anki_Scheduler_SchedTimingTodayResponse? = try? backend.call(SchedulerMethods.schedTimingToday)
            var loaded: [Int64: BrowseRow] = [:]
            for cid in batch { if let row = try? Self.row(backend, cid, timing) { loaded[cid] = row } }
            await MainActor.run {
                guard gen == self.generation else { return }
                self.rows.merge(loaded) { $1 }
                self.loading.subtract(batch)
            }
        }
    }

    /// The browser columns live in the backend's memory only (not in the collection), so setting them has no side effects.
    static func setColumns(_ backend: Backend) throws {
        var cols = Anki_Generic_StringList()
        cols.vals = ["question", "deck", "noteTags"]
        try backend.run(SearchMethods.setActiveBrowserColumns, cols)
    }

    static func row(_ backend: Backend, _ cid: Int64, _ timing: Anki_Scheduler_SchedTimingTodayResponse?) throws -> BrowseRow {
        var i = Anki_Generic_Int64()
        i.val = cid
        let r: Anki_Search_BrowserRow = try backend.call(SearchMethods.browserRowForId, i)
        var id = Anki_Cards_CardId()
        id.cid = cid
        let card: Anki_Cards_Card = try backend.call(CardsMethods.getCard, id)
        let cells = r.cells.map(\.text)
        let status = CardStatus.of(ctype: card.ctype, queue: card.queue, due: card.due, originalDue: card.originalDue,
                                   inFilteredDeck: card.originalDeckID != 0, daysElapsed: Int(timing?.daysElapsed ?? 0),
                                   nextDayAt: timing?.nextDayAt ?? Int64(Date().timeIntervalSince1970))
        let deck = cells.count > 1 ? cells[1] : ""
        return BrowseRow(question: cells.first ?? "", deck: deck.components(separatedBy: "::").last ?? deck, tags: cells.count > 2 ? cells[2] : "",
                         status: status, flag: Int(card.flags & 0b111))
    }

    // MARK: actions

    func setFlag(_ flag: Int, on cid: Int64) {
        guard let backend else { return }
        let current = rows[cid]?.flag ?? 0
        let value = current == flag ? 0 : flag
        rows[cid]?.flag = value
        Task.detached {
            var req = Anki_Cards_SetFlagRequest()
            req.cardIds = [cid]
            req.flag = UInt32(value)
            let _: Anki_Collection_OpChangesWithCount? = try? backend.call(CardsMethods.setFlag, req)
        }
    }

    func setSuspended(_ suspend: Bool, _ cids: [Int64]) {
        guard let backend else { return }
        Task.detached { [self] in
            try? Self.setSuspended(backend, suspend, cids)
            let timing: Anki_Scheduler_SchedTimingTodayResponse? = try? backend.call(SchedulerMethods.schedTimingToday)
            var loaded: [Int64: BrowseRow] = [:]
            for cid in cids { if let row = try? Self.row(backend, cid, timing) { loaded[cid] = row } }
            await MainActor.run { self.rows.merge(loaded) { $1 } }
        }
    }

    static func setSuspended(_ backend: Backend, _ suspend: Bool, _ cids: [Int64]) throws {
        if suspend {
            var req = Anki_Scheduler_BuryOrSuspendCardsRequest()
            req.cardIds = cids
            req.mode = .suspend
            let _: Anki_Collection_OpChangesWithCount = try backend.call(SchedulerMethods.buryOrSuspendCards, req)
        } else {
            var req = Anki_Cards_CardIds()
            req.cids = cids
            let _: Anki_Collection_OpChanges = try backend.call(SchedulerMethods.restoreBuriedAndSuspendedCards, req)
        }
    }

    /// Build a filtered deck from the current search (Anki's "Create filtered deck"), keeping the cards' own scheduling.
    func studyAsDeck(completion: @escaping (String?) -> Void) {
        guard let backend else { return }
        let query = search.isEmpty ? "deck:*" : search
        let count = ids.count
        Task.detached { [self] in
            let result = Result { try Self.makeFilteredDeck(backend, search: query, limit: count) }
            await MainActor.run {
                switch result {
                case .success(let name): self.message = "Made the deck “\(name)”. It is on the Decks tab."; completion(name)
                case .failure(let e): self.message = "Could not make a deck: \(e.localizedDescription)"; completion(nil)
                }
            }
        }
    }

    static func makeFilteredDeck(_ backend: Backend, search: String, limit: Int) throws -> String {
        var id = Anki_Decks_DeckId()
        id.did = 0
        var deck: Anki_Decks_FilteredDeckForUpdate = try backend.call(DecksMethods.getOrCreateFilteredDeck, id)
        var term = Anki_Decks_Deck.Filtered.SearchTerm()
        term.search = search
        term.limit = UInt32(max(1, min(limit, 9999)))
        term.order = .due
        deck.config.searchTerms = [term]
        deck.config.reschedule = true
        let _: Anki_Collection_OpChangesWithId = try backend.call(DecksMethods.addOrUpdateFilteredDeck, deck)
        return deck.name
    }
}
