// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import Observation

/// Pure arithmetic behind the Stats screen, kept apart so it can be tested without a collection.
enum StatsMath {
    /// One answer from the review log, as stored by Anki (revlog table).
    struct Answer: Equatable {
        var id: Int64          // milliseconds since 1970: when it was answered
        var ease: Int          // button: 1 Again … 4 Easy, 0 for a manual reschedule
        var type: Int          // 0 learn, 1 review, 2 relearn, 3 filtered, 4 manual, 5 rescheduled
        var lastIvl: Int       // previous interval: days if positive, seconds if negative
        var factor: Int        // 0 in a filtered deck means cramming
    }

    /// Anki's true retention: answers with a rating, not cramming, on cards that had an interval of at least a day.
    /// Returns nil if the answer does not count, true if remembered, false if forgotten (Again).
    /// Mirrors rslib/src/stats/graphs/retention.rs so the daily line agrees with the headline.
    static func counts(_ a: Answer) -> Bool? {
        guard a.ease > 0, !(a.type == 3 && a.factor == 0) else { return nil }
        guard a.type == 1 || a.lastIvl <= -86_400 || a.lastIvl >= 1 else { return nil }
        return a.ease != 1
    }

    struct Day: Equatable {
        var offset: Int        // 0 today, -1 yesterday …
        var passed: Int
        var total: Int
        var rate: Double { total == 0 ? 0 : Double(passed) / Double(total) }
    }

    /// Daily true retention over the last `days` days. Day boundaries follow Anki's rollover (`nextDayAt`).
    static func daily(_ answers: [Answer], nextDayAt: Int64, days: Int = 30) -> [Day] {
        var out = (0..<days).map { Day(offset: $0 - days + 1, passed: 0, total: 0) }
        for a in answers {
            guard let ok = counts(a) else { continue }
            let secs = a.id / 1000
            let offset = Int(floor(Double(secs - nextDayAt) / 86_400)) + 1
            let index = offset + days - 1
            guard index >= 0 && index < days else { continue }
            out[index].total += 1
            if ok { out[index].passed += 1 }
        }
        return out
    }

    /// Share remembered, or nil when there are too few answers to say anything (Kartei shows nothing under 20).
    static func rate(passed: Int, total: Int, minimum: Int = 20) -> Double? {
        total >= minimum && total > 0 ? Double(passed) / Double(total) : nil
    }

    /// Minutes for a number of cards, rounded; at least 1 when there is anything to do.
    static func minutes(cards: Double, secondsPerCard: Double) -> Int {
        cards <= 0 ? 0 : max(1, Int((cards * secondsPerCard / 60).rounded()))
    }

    struct ForecastDay: Equatable {
        var offset: Int
        var cards: Int
        var minutes: Int
    }

    /// Reviews already scheduled for the next `days` days, in minutes. Overdue cards count towards today.
    static func forecast(_ futureDue: [Int32: UInt32], days: Int = 14, secondsPerCard: Double) -> [ForecastDay] {
        var cards = Array(repeating: 0, count: days)
        for (day, n) in futureDue {
            let i = max(0, Int(day))
            if i < days { cards[i] += Int(n) }
        }
        return cards.enumerated().map { ForecastDay(offset: $0.offset, cards: $0.element, minutes: minutes(cards: Double($0.element), secondsPerCard: secondsPerCard)) }
    }

    /// Answers over the last seven days including today, from Graphs' review counts (key 0 = today).
    static func reviewsThisWeek(_ counts: [Int32: Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews]) -> Int {
        counts.filter { $0.key > -7 && $0.key <= 0 }.reduce(0) { $0 + Int($1.value.learn + $1.value.relearn + $1.value.young + $1.value.mature + $1.value.filtered) }
    }

    /// Seconds per answer over the last 30 days; 8 s until there are 50 answers (same rule as the home screen).
    static func secondsPerCard(_ r: Anki_Stats_GraphsResponse.ReviewCountsAndTimes) -> Double {
        var answers = 0, millis = 0
        for (day, c) in r.count where day > -30 { answers += Int(c.learn + c.relearn + c.young + c.mature + c.filtered) }
        for (day, t) in r.time where day > -30 { millis += Int(t.learn + t.relearn + t.young + t.mature + t.filtered) }
        guard answers >= 50 else { return 8 }
        return min(60, max(2, Double(millis) / Double(answers) / 1000))
    }
}

/// Everything the Stats screen shows, read in one go.
struct StatsSnapshot: Equatable {
    var scope: String = "All decks"
    var passed = 0
    var total = 0
    var retention: Double? { StatsMath.rate(passed: passed, total: total) }
    var target = 0.9
    var daily: [StatsMath.Day] = []
    var forecast: [StatsMath.ForecastDay] = []
    var secondsPerCard = 8.0
    var measuredTime = false
    var newCards = 0, learning = 0, young = 0, mature = 0, suspended = 0
    var leeches = 0
    var reviewsThisWeek = 0
    /// FSRS: expected number of cards you would recall right now (sum of retrievability), and how many cards that covers.
    var recallNow: Int?
    var recallOf = 0
}

@Observable
final class StatsModel {
    private(set) var snapshot: StatsSnapshot?
    private(set) var error: String?
    /// Deck to limit the stats to; nil means all decks.
    var deckName: String? { didSet { if oldValue != deckName { load() } } }

    @ObservationIgnored private var backend: Backend?

    func attach(_ backend: Backend?) {
        guard let backend, self.backend !== backend else { return }
        self.backend = backend
        load()
    }

    func load() {
        guard let backend else { return }
        let deck = deckName
        Task.detached(priority: .userInitiated) { [self] in
            let result = Result { try Self.read(backend, deck: deck) }
            await MainActor.run {
                switch result {
                case .success(let s): self.snapshot = s; self.error = nil
                case .failure(let e): self.error = e.localizedDescription
                }
            }
        }
    }

    static func deckSearch(_ name: String?) -> String {
        guard let name else { return "" }
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "*", with: "\\*").replacingOccurrences(of: "_", with: "\\_")
        return "deck:\"\(escaped)\""
    }

    static func read(_ backend: Backend, deck: String?) throws -> StatsSnapshot {
        var s = StatsSnapshot()
        s.scope = deck ?? "All decks"
        let search = deckSearch(deck)
        var req = Anki_Stats_GraphsRequest()
        req.search = search
        req.days = 31
        let g: Anki_Stats_GraphsResponse = try backend.call(StatsMethods.graphs, req)

        let m = g.trueRetention.month
        s.passed = Int(m.youngPassed + m.maturePassed)
        s.total = s.passed + Int(m.youngFailed + m.matureFailed)

        let timing: Anki_Scheduler_SchedTimingTodayResponse = try backend.call(SchedulerMethods.schedTimingToday)
        s.daily = StatsMath.daily(try answers(backend, search: search, since: timing.nextDayAt - 31 * 86_400), nextDayAt: timing.nextDayAt)

        s.secondsPerCard = StatsMath.secondsPerCard(g.reviews)
        s.measuredTime = s.secondsPerCard != 8
        s.forecast = StatsMath.forecast(g.futureDue.futureDue, secondsPerCard: s.secondsPerCard)

        let c = g.cardCounts.includingInactive
        let active = g.cardCounts.excludingInactive
        s.newCards = Int(active.newCards)
        s.learning = Int(active.learn + active.relearn)
        s.young = Int(active.young)
        s.mature = Int(active.mature)
        s.suspended = Int(c.suspended)
        s.reviewsThisWeek = StatsMath.reviewsThisWeek(g.reviews.count)

        var leech = Anki_Search_SearchRequest()
        leech.search = search.isEmpty ? "tag:leech" : "\(search) tag:leech"
        let leeches: Anki_Search_SearchResponse = try backend.call(SearchMethods.searchCards, leech)
        s.leeches = leeches.ids.count

        if g.fsrs {
            let seen = g.retrievability.retrievability.values.reduce(0) { $0 + Int($1) }
            if seen > 0 { s.recallNow = Int(g.retrievability.sumByCard.rounded()); s.recallOf = seen }
        }
        s.target = PaceStore.desiredRetention(backend, deckName: deck) ?? 0.9
        return s
    }

    /// Answers since a moment (seconds), read straight from the review log; limited to the cards of a search if given.
    static func answers(_ backend: Backend, search: String, since: Int64) throws -> [StatsMath.Answer] {
        var sql = "select id, ease, type, lastIvl, factor from revlog where id > ?"
        if !search.isEmpty {
            var req = Anki_Search_SearchRequest()
            req.search = search
            let ids: Anki_Search_SearchResponse = try backend.call(SearchMethods.searchCards, req)
            if ids.ids.isEmpty { return [] }
            sql += " and cid in (\(ids.ids.map(String.init).joined(separator: ",")))"
        }
        let rows = try DB.query(backend, sql, [since * 1000])
        return rows.compactMap { r in
            guard r.count == 5 else { return nil }
            return StatsMath.Answer(id: r[0], ease: Int(r[1]), type: Int(r[2]), lastIvl: Int(r[3]), factor: Int(r[4]))
        }
    }
}

/// Read-only SQL through Anki's database proxy (the same one AnkiDroid uses). Integer columns only.
enum DB {
    static func query(_ backend: Backend, _ sql: String, _ args: [Any]) throws -> [[Int64]] {
        var j = Anki_Generic_Json()
        j.json = try JSONSerialization.data(withJSONObject: ["kind": "query", "sql": sql, "args": args, "first_row_only": false])
        let r: Anki_Generic_Json = try backend.call(AnkidroidMethods.runDbCommand, j)
        guard let rows = try JSONSerialization.jsonObject(with: r.json) as? [[Any]] else { return [] }
        return rows.map { $0.map { ($0 as? NSNumber)?.int64Value ?? 0 } }
    }
}
