// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import XCTest
@testable import Kartei

/// Pure logic behind Browse, Stats, Pace and onboarding.
final class ScreensLogicTests: XCTestCase {

    // MARK: browse search

    func testSearchStringCombinesTypedTextAndFilter() {
        XCTAssertEqual(BrowseSearch.build(text: "", filter: nil), "")
        XCTAssertEqual(BrowseSearch.build(text: "   ", filter: nil), "")
        XCTAssertEqual(BrowseSearch.build(text: " deck:Intro ", filter: nil), "deck:Intro")
        XCTAssertEqual(BrowseSearch.build(text: "", filter: .due), "is:due")
        // The typed part is bracketed so an "or" cannot swallow the filter.
        XCTAssertEqual(BrowseSearch.build(text: "dog or cat", filter: .flagged), "(dog or cat) -flag:0")
    }

    func testQuickFiltersUseAnkiSearchTerms() {
        XCTAssertEqual(BrowseFilter.allCases.map(\.search), ["is:due", "is:new", "-flag:0", "is:suspended", "tag:leech"])
        XCTAssertEqual(BrowseFilter.slipping.title, "Keep slipping")
    }

    // MARK: card status wording

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var nextDay: Int64 { 1_800_000_000 + 6 * 3_600 }

    private func status(ctype: UInt32, queue: Int32, due: Int32, today: Int = 1000) -> CardStatus {
        CardStatus.of(ctype: ctype, queue: queue, due: due, daysElapsed: today, nextDayAt: nextDay, now: now)
    }

    func testCardStatusStates() {
        XCTAssertEqual(status(ctype: 0, queue: 0, due: 5), CardStatus(due: "not seen", state: "new"))
        XCTAssertEqual(status(ctype: 2, queue: -1, due: 1000), CardStatus(due: "paused", state: "suspended", suspended: true))
        XCTAssertEqual(status(ctype: 2, queue: -2, due: 1000).state, "buried")
        XCTAssertEqual(status(ctype: 2, queue: 2, due: 1000), CardStatus(due: "today", state: "review"))
        XCTAssertEqual(status(ctype: 2, queue: 2, due: 1001).due, "tomorrow")
        XCTAssertEqual(status(ctype: 2, queue: 2, due: 1003).due, "in 3 d")
        XCTAssertEqual(status(ctype: 2, queue: 2, due: 997).due, "3 d late")
        XCTAssertEqual(status(ctype: 3, queue: 3, due: 1000).state, "relearning")
    }

    func testIntradayLearningIsDueNowOrToday() {
        XCTAssertEqual(status(ctype: 1, queue: 1, due: Int32(1_800_000_000 - 60)).due, "now")
        XCTAssertEqual(status(ctype: 1, queue: 1, due: Int32(1_800_000_000 + 600)), CardStatus(due: "today", state: "learning"))
        XCTAssertEqual(status(ctype: 1, queue: 1, due: Int32(nextDay + 60)).due, "tomorrow")
    }

    func testFarDaysShowADate() {
        let text = CardStatus.dayText(40, now: now)
        XCTAssertFalse(text.hasPrefix("in "))
        XCTAssertTrue(text.contains(" "), text)
    }

    func testFlagColoursAndNames() {
        XCTAssertNil(Flags.colour(0))
        XCTAssertEqual(Flags.name(1), "Red")
        XCTAssertEqual(Flags.name(7), "Purple")
        XCTAssertNil(Flags.name(8))
    }

    // MARK: true retention

    private func answer(_ ease: Int, type: Int = 1, lastIvl: Int = 5, factor: Int = 2500, at: Int64 = 1_800_000_000) -> StatsMath.Answer {
        .init(id: at * 1000, ease: ease, type: type, lastIvl: lastIvl, factor: factor)
    }

    func testTrueRetentionCountsLikeAnki() {
        XCTAssertEqual(StatsMath.counts(answer(3)), true)
        XCTAssertEqual(StatsMath.counts(answer(2)), true)   // Hard is a pass
        XCTAssertEqual(StatsMath.counts(answer(1)), false)  // only Forgot fails (F3)
        XCTAssertNil(StatsMath.counts(answer(0)))                                 // manual reschedule
        XCTAssertNil(StatsMath.counts(answer(3, type: 3, factor: 0)))             // cramming
        XCTAssertNil(StatsMath.counts(answer(3, type: 0, lastIvl: -600)))         // same-day learning step
        XCTAssertEqual(StatsMath.counts(answer(1, type: 2, lastIvl: 12)), false)  // relearn of a known card counts
        XCTAssertEqual(StatsMath.counts(answer(3, type: 0, lastIvl: -86_400)), true)
    }

    func testDailyBucketsFollowRollover() {
        let nd = nextDay
        let answers = [
            answer(3, at: nd - 100),                // today
            answer(1, at: nd - 200),                // today
            answer(3, at: nd - 86_400 - 1),         // yesterday
            answer(3, at: nd - 40 * 86_400),        // outside the window
            answer(3, at: nd + 10),                 // tomorrow (clock skew): ignored
            answer(0, at: nd - 300),                // not counted
        ]
        let days = StatsMath.daily(answers, nextDayAt: nd, days: 30)
        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(days.last, StatsMath.Day(offset: 0, passed: 1, total: 2))
        XCTAssertEqual(days[28], StatsMath.Day(offset: -1, passed: 1, total: 1))
        XCTAssertEqual(days.first?.offset, -29)
        XCTAssertEqual(days.reduce(0) { $0 + $1.total }, 3)
    }

    func testRetentionNeedsTwentyAnswers() {
        XCTAssertNil(StatsMath.rate(passed: 18, total: 19))
        XCTAssertEqual(StatsMath.rate(passed: 18, total: 20)!, 0.9, accuracy: 1e-9)
        XCTAssertNil(StatsMath.rate(passed: 0, total: 0))
    }

    // MARK: forecast

    func testForecastFoldsOverdueIntoTodayAndUsesSecondsPerCard() {
        let f = StatsMath.forecast([-3: 10, 0: 20, 1: 45, 13: 1, 14: 99], days: 14, secondsPerCard: 8)
        XCTAssertEqual(f.count, 14)
        XCTAssertEqual(f[0].cards, 30)
        XCTAssertEqual(f[0].minutes, 4)    // 30 × 8 s = 4 min
        XCTAssertEqual(f[1].minutes, 6)    // 45 × 8 s = 6 min
        XCTAssertEqual(f[13].minutes, 1)   // anything at all is at least a minute
        XCTAssertEqual(f[5].minutes, 0)
    }

    func testMinutesRounding() {
        XCTAssertEqual(StatsMath.minutes(cards: 0, secondsPerCard: 8), 0)
        XCTAssertEqual(StatsMath.minutes(cards: 1, secondsPerCard: 8), 1)
        XCTAssertEqual(StatsMath.minutes(cards: 100, secondsPerCard: 8), 13)
    }

    func testReviewsThisWeekCountsSevenDays() {
        var r = Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews()
        r.young = 3; r.learn = 2
        let counts: [Int32: Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews] = [0: r, -6: r, -7: r, 1: r]
        XCTAssertEqual(StatsMath.reviewsThisWeek(counts), 10)
    }

    func testSecondsPerCardNeedsFiftyAnswers() {
        var t = Anki_Stats_GraphsResponse.ReviewCountsAndTimes()
        var c = Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews(); c.young = 40
        var ms = Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews(); ms.young = 40 * 12_000
        t.count = [0: c]; t.time = [0: ms]
        XCTAssertEqual(StatsMath.secondsPerCard(t), 8)
        c.young = 50; ms.young = 50 * 12_000
        t.count = [0: c]; t.time = [0: ms]
        XCTAssertEqual(StatsMath.secondsPerCard(t), 12, accuracy: 1e-9)
    }

    func testDeckSearchIsQuoted() {
        XCTAssertEqual(StatsModel.deckSearch(nil), "")
        XCTAssertEqual(StatsModel.deckSearch("Sample deck"), "deck:\"Sample deck\"")
        XCTAssertEqual(StatsModel.deckSearch("a_b*"), "deck:\"a\\_b\\*\"")
    }

    // MARK: workload

    func testIntervalRatioFollowsTheForgettingCurve() {
        XCTAssertEqual(Workload.intervalRatio(0.9), 1, accuracy: 1e-9)
        XCTAssertEqual(Workload.intervalRatio(0.9, decay: 0.5), 1, accuracy: 1e-9)
        // FSRS-4.5/5 (decay 0.5): t ∝ r^-2 − 1, so 97 % gives (1/0.9409 − 1)/(1/0.81 − 1) ≈ 0.268.
        XCTAssertEqual(Workload.intervalRatio(0.97, decay: 0.5), 0.268, accuracy: 0.002)
        // FSRS-6 default decay: 97 % gives intervals about 0.22 of those at 90 %.
        XCTAssertEqual(Workload.intervalRatio(0.97), 0.22, accuracy: 0.01)
        XCTAssertGreaterThan(Workload.intervalRatio(0.7), 3)
        // Strictly shorter intervals as retention rises.
        let rs = stride(from: 0.70, through: 0.97, by: 0.01).map { Workload.intervalRatio($0) }
        XCTAssertEqual(rs, rs.sorted(by: >))
    }

    func testSteadyReviewsIsTenPerNewCardAtNinetyPercent() {
        XCTAssertEqual(Workload.steadyReviews(newPerDay: 10), 100)
        XCTAssertEqual(Workload.steadyReviews(newPerDay: 0), 0)
        XCTAssertEqual(Workload.steadyReviews(newPerDay: 20), 200)
        XCTAssertGreaterThan(Workload.steadyReviews(newPerDay: 10, retention: 0.95), 150)
        XCTAssertLessThan(Workload.steadyReviews(newPerDay: 10, retention: 0.8), 60)
        XCTAssertEqual(Workload.minutes(reviews: 100, secondsPerCard: 8), 13)
    }

    func testDecayFromParameters() {
        XCTAssertEqual(Workload.decay([]), Workload.fsrs6Decay)
        XCTAssertEqual(Workload.decay(Array(repeating: 1, count: 19)), 0.5)
        var p6 = Array(repeating: Float(1), count: 21); p6[20] = 0.3
        XCTAssertEqual(Workload.decay(p6), 0.3, accuracy: 1e-6)
    }

    func testSimulatorCostBecomesMinutesPerDay() {
        let curve = Workload.minutesPerDay(cost: [90: 148_434, 97: 303_759, 70: 93_816], days: 365)
        XCTAssertEqual(curve[90]!, 6.78, accuracy: 0.01)
        XCTAssertEqual(curve[97]!, 13.87, accuracy: 0.01)
        XCTAssertFalse(Workload.usable(curve))   // does not cover 70…97
        var full: [Int: Double] = [:]
        for d in 70...99 { full[d] = Double(d) / 10 }
        XCTAssertTrue(Workload.usable(full))
        XCTAssertFalse(Workload.usable(full.mapValues { _ in 0 }))
        XCTAssertTrue(Workload.minutesPerDay(cost: [90: 1], days: 0).isEmpty)
    }

    func testFallbackEstimateScalesWithRetention() {
        // 50 reviews due a day plus 10 new × 10 = 150 reviews at 8 s = 20 min at 90 %.
        XCTAssertEqual(Workload.estimate(dailyLoad: 50, newPerDay: 10, retention: 0.9, secondsPerCard: 8), 20, accuracy: 1e-9)
        XCTAssertGreaterThan(Workload.estimate(dailyLoad: 50, newPerDay: 10, retention: 0.97, secondsPerCard: 8), 80)
        XCTAssertLessThan(Workload.estimate(dailyLoad: 50, newPerDay: 10, retention: 0.8, secondsPerCard: 8), 10)
    }

    func testDefaultsMatchTheScienceDoc() {
        XCTAssertEqual(PaceDefaults.desiredRetention, 0.90)
        XCTAssertEqual(PaceDefaults.minRetention, 0.70)
        XCTAssertEqual(PaceDefaults.maxRetention, 0.97)
        XCTAssertEqual(PaceDefaults.warnAbove, 0.95)
        XCTAssertEqual(PaceDefaults.newPerDay, 10)
        XCTAssertEqual(PaceDefaults.learnSteps, [1, 10])
        XCTAssertEqual(PaceDefaults.relearnSteps, [10])
        XCTAssertEqual(PaceDefaults.leechThreshold, 8)
        XCTAssertEqual(PaceDefaults.reviewsPerNewCard, 10)
    }

    // MARK: steps, lighter days

    func testStepsTextRoundTrip() {
        XCTAssertEqual(StepsText.format([1, 10]), "1m 10m")
        XCTAssertEqual(StepsText.format([10, 60, 1_440, 0.5]), "10m 1h 1d 30s")
        XCTAssertEqual(StepsText.parse("1m 10m"), [1, 10])
        XCTAssertEqual(StepsText.parse("1, 10"), [1, 10])
        XCTAssertEqual(StepsText.parse("30s 1h 2d"), [0.5, 60, 2_880])
        XCTAssertEqual(StepsText.parse(""), [])
        XCTAssertNil(StepsText.parse("1x"))
        XCTAssertNil(StepsText.parse("-5m"))
        for steps: [Float] in [[1, 10], [10], [5, 30, 1_440]] { XCTAssertEqual(StepsText.parse(StepsText.format(steps)), steps) }
        XCTAssertEqual(StepsText.spoken([1, 10]), "1 min, 10 min")
    }

    func testLighterDayCycles() {
        XCTAssertEqual(LighterDay.of(1).next, .half)
        XCTAssertEqual(LighterDay.of(0.5).next, .least)
        XCTAssertEqual(LighterDay.of(0).next, .normal)
        XCTAssertEqual(LighterDay.of(0.7), .half)
    }

    // MARK: card info

    func testRecallIsNinetyPercentAfterOneStability() {
        for decay in [0.5, 0.1542, 0.3] {
            XCTAssertEqual(CardInfoMath.recall(days: 5, stability: 5, decay: decay), 0.9, accuracy: 1e-9)
            XCTAssertEqual(CardInfoMath.recall(days: 0, stability: 5, decay: decay), 1, accuracy: 1e-9)
            XCTAssertLessThan(CardInfoMath.recall(days: 20, stability: 5, decay: decay), 0.9)
        }
        XCTAssertEqual(CardInfoMath.recall(days: 1, stability: 0, decay: 0.5), 0)
    }

    func testRecallCurveSawtooth() {
        let day: Int64 = 86_400
        let entries: [(time: Int64, button: UInt32, stability: Double?)] = [(0, 3, 2.0), (4 * day, 1, 0.5), (5 * day, 3, 3.0)]
        let pts = CardInfoMath.curve(entries, now: 8 * day, decay: 0.5, samples: 4)
        XCTAssertEqual(pts.count, 15)
        XCTAssertEqual(pts.first, CardInfoMath.CurvePoint(t: 0, r: 1))
        XCTAssertEqual(pts.filter(\.miss).count, 1)
        let miss = pts.first(where: \.miss)!
        XCTAssertEqual(miss.t, 4, accuracy: 1e-9)
        XCTAssertEqual(miss.r, CardInfoMath.recall(days: 4, stability: 2, decay: 0.5), accuracy: 1e-9)
        XCTAssertEqual(pts.last!.t, 8, accuracy: 1e-9)
        XCTAssertTrue(CardInfoMath.curve([], now: 0, decay: 0.5).isEmpty)
    }

    func testRecallCurveStartsAtFirstMemoryState() {
        let day: Int64 = 86_400
        let entries: [(time: Int64, button: UInt32, stability: Double?)] = [(0, 3, nil), (30 * day, 3, 2.0)]
        let pts = CardInfoMath.curve(entries, now: 32 * day, decay: 0.5, samples: 4)
        XCTAssertEqual(pts.first?.t, 0)
        XCTAssertEqual(pts.last!.t, 2, accuracy: 1e-9, "times count from the first review FSRS has a state for")
    }

    func testWorkloadFactorDrivesSteadyReviewsAndIntervalWording() {
        XCTAssertEqual(Workload.steadyReviews(newPerDay: 10, factor: 1.8), 180)
        XCTAssertEqual(Workload.steadyReviews(newPerDay: 10, factor: 1), Workload.steadyReviews(newPerDay: 10))
        XCTAssertEqual(PaceAdvanced.intervalText(36_500), "100 y")
        XCTAssertEqual(PaceAdvanced.intervalText(365), "1 y")
        XCTAssertEqual(PaceAdvanced.intervalText(400), "1.1 y")
        XCTAssertEqual(PaceAdvanced.intervalText(60), "60 d")
    }

    func testAnswerNames() {
        XCTAssertEqual(CardInfoMath.answerName(button: 1, kind: .review), "Forgot")
        XCTAssertEqual(CardInfoMath.answerName(button: 3, kind: .learning), "Good")
        XCTAssertEqual(CardInfoMath.answerName(button: 0, kind: .manual), "Rescheduled")
    }

    func testFormatting() {
        XCTAssertEqual(spanText(seconds: 600), "10 min")
        XCTAssertEqual(spanText(seconds: 4 * 86_400), "4 d")
        XCTAssertEqual(spanText(seconds: 90 * 86_400), "3 mo")
        XCTAssertEqual(grouped(1240), "1\u{202F}240")
        XCTAssertEqual(grouped(12), "12")
    }
}

/// The same logic against a real collection with the bundled sample decks.
final class ScreensCollectionTests: XCTestCase {

    /// Write review-log entries directly (tests only): `passed` Good and `failed` Again answers on review cards today.
    private func addReviews(_ c: TempCollection, passed: Int, failed: Int) throws {
        let ids = try c.cardIDs("deck:*")
        let base = Int64(Date().timeIntervalSince1970 - 60) * 1000
        for i in 0..<(passed + failed) {
            let ease = i < passed ? 3 : 1
            _ = try DB.query(c.backend, "insert into revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type) values (?, ?, 0, ?, 10, 10, 2500, 8000, 1)",
                             [base + Int64(i), ids[i % ids.count], ease])
        }
    }

    func testSearchQuickFiltersAndSortOrder() throws {
        let c = try TempCollection()
        let all = try BrowseModel.searchCards(c.backend, BrowseSearch.build(text: "", filter: nil))
        XCTAssertGreaterThan(all.count, 50)
        XCTAssertEqual(try BrowseModel.searchCards(c.backend, BrowseSearch.build(text: "", filter: .new)).count, all.count)
        XCTAssertEqual(try BrowseModel.searchCards(c.backend, BrowseSearch.build(text: "", filter: .slipping)).count, 0)
        XCTAssertEqual(try BrowseModel.searchCards(c.backend, BrowseSearch.build(text: "", filter: .suspended)).count, 0)
        let typed = try BrowseModel.searchCards(c.backend, BrowseSearch.build(text: "dozen", filter: .new))
        XCTAssertGreaterThan(typed.count, 0)
        XCTAssertLessThan(typed.count, all.count)
        XCTAssertThrowsError(try BrowseModel.searchCards(c.backend, "deck:\"unclosed"))
        // Due order: new cards sort by position.
        var req = Anki_Search_SearchRequest(); req.search = ""
        let unsorted: Anki_Search_SearchResponse = try c.backend.call(SearchMethods.searchCards, req)
        XCTAssertEqual(Set(unsorted.ids), Set(all))
    }

    func testRowsSuspendAndFlag() throws {
        let c = try TempCollection()
        let ids = try BrowseModel.searchCards(c.backend, "")
        try BrowseModel.setColumns(c.backend)
        let timing: Anki_Scheduler_SchedTimingTodayResponse = try c.backend.call(SchedulerMethods.schedTimingToday)
        let row = try BrowseModel.row(c.backend, ids[0], timing)
        XCTAssertFalse(row.question.isEmpty)
        XCTAssertFalse(row.question.contains("<"), "question should be plain text")
        XCTAssertEqual(row.deck, "01 Times tables")
        XCTAssertEqual(row.status, CardStatus(due: "not seen", state: "new"))

        try BrowseModel.setSuspended(c.backend, true, [ids[0], ids[1]])
        XCTAssertEqual(try c.cardIDs("is:suspended").count, 2)
        XCTAssertTrue(try BrowseModel.row(c.backend, ids[0], timing).status.suspended)
        try BrowseModel.setSuspended(c.backend, false, [ids[0]])
        XCTAssertEqual(try c.cardIDs("is:suspended"), [ids[1]])

        var flag = Anki_Cards_SetFlagRequest(); flag.cardIds = [ids[2]]; flag.flag = 4
        let _: Anki_Collection_OpChangesWithCount = try c.backend.call(CardsMethods.setFlag, flag)
        XCTAssertEqual(try c.cardIDs(BrowseFilter.flagged.search), [ids[2]])
        XCTAssertEqual(try BrowseModel.row(c.backend, ids[2], timing).flag, 4)
    }

    func testStudyTheseAsADeck() throws {
        let c = try TempCollection()
        let name = try BrowseModel.makeFilteredDeck(c.backend, search: "dozen", limit: 3)
        XCTAssertFalse(name.isEmpty)
        let inDeck = try c.cardIDs("deck:\"\(name)\"")
        XCTAssertGreaterThan(inDeck.count, 0)
        XCTAssertLessThanOrEqual(inDeck.count, 3)
    }

    func testStatsAgreeWithAnkiTrueRetention() throws {
        let c = try TempCollection()
        try addReviews(c, passed: 25, failed: 5)
        let s = try StatsModel.read(c.backend, deck: nil)
        XCTAssertEqual(s.passed, 25)
        XCTAssertEqual(s.total, 30)
        XCTAssertEqual(s.retention!, 25.0 / 30.0, accuracy: 1e-9)
        // The daily line, read from the review log, agrees with Anki's headline.
        XCTAssertEqual(s.daily.last?.total, 30)
        XCTAssertEqual(s.daily.last?.passed, 25)
        XCTAssertEqual(s.reviewsThisWeek, 30)
        XCTAssertEqual(s.target, 0.9, accuracy: 1e-6)
        XCTAssertEqual(s.newCards + s.learning + s.young + s.mature, try c.cardIDs("deck:* -is:suspended").count)
        XCTAssertEqual(s.forecast.count, 14)
        XCTAssertEqual(s.leeches, 0)
        let deck = try StatsModel.read(c.backend, deck: "Sample::01 Times tables")
        XCTAssertEqual(deck.total, 30)
        let none = try StatsModel.read(c.backend, deck: "No such deck")
        XCTAssertEqual(none.total, 0)
        XCTAssertNil(none.retention)
    }

    func testLeechesCountTaggedCards() throws {
        let c = try TempCollection()
        let ids = try c.cardIDs("")
        var note = Anki_Cards_CardId(); note.cid = ids[0]
        let card: Anki_Cards_Card = try c.backend.call(CardsMethods.getCard, note)
        var tags = Anki_Tags_NoteIdsAndTagsRequest(); tags.noteIds = [card.noteID]; tags.tags = "leech"
        let _: Anki_Collection_OpChangesWithCount = try c.backend.call(TagsMethods.addNoteTags, tags)
        XCTAssertEqual(try StatsModel.read(c.backend, deck: nil).leeches, try c.cardIDs("tag:leech").count)
        XCTAssertGreaterThan(try c.cardIDs(BrowseFilter.slipping.search).count, 0)
    }

    func testPacePresetRoundTrip() throws {
        let c = try TempCollection(decks: ["sample-01", "sample-02"])
        let presets = try PaceStore.presets(c.backend)
        XCTAssertEqual(presets.count, 1)
        let preset = try XCTUnwrap(presets.first)
        XCTAssertEqual(preset.name, "Default")
        XCTAssertGreaterThanOrEqual(preset.decks.count, 3)   // parent + two lecture decks
        let deck = preset.decks[0]
        let before = try PaceStore.forUpdate(c.backend, deck: deck)
        XCTAssertFalse(before.fsrs, "Anki starts with FSRS off; Kartei turns it on at first run")

        var config = try XCTUnwrap(before.allConfig.first { $0.config.id == preset.id }?.config)
        config.config.desiredRetention = 0.85
        config.config.newPerDay = 15
        config.config.learnSteps = [2, 15]
        config.config.relearnSteps = [5]
        config.config.leechThreshold = 6
        config.config.maximumReviewInterval = 365
        config.config.easyDaysPercentages = [1, 1, 1, 1, 1, 0.5, 0]
        try PaceStore.write(c.backend, config: config, fsrs: true, deck: deck, update: before)

        let after = try PaceStore.forUpdate(c.backend, deck: deck)
        let saved = try XCTUnwrap(after.allConfig.first { $0.config.id == preset.id }?.config.config)
        XCTAssertTrue(after.fsrs)
        XCTAssertEqual(saved.desiredRetention, 0.85, accuracy: 1e-6)
        XCTAssertEqual(saved.newPerDay, 15)
        XCTAssertEqual(saved.learnSteps, [2, 15])
        XCTAssertEqual(saved.relearnSteps, [5])
        XCTAssertEqual(saved.leechThreshold, 6)
        XCTAssertEqual(saved.maximumReviewInterval, 365)
        XCTAssertEqual(saved.easyDaysPercentages, [1, 1, 1, 1, 1, 0.5, 0])
        // Collection-wide settings that UpdateDeckConfigs also writes are kept as they were.
        XCTAssertEqual(after.newCardsIgnoreReviewLimit, before.newCardsIgnoreReviewLimit)
        XCTAssertEqual(after.applyAllParentLimits, before.applyAllParentLimits)
        XCTAssertEqual(after.fsrsHealthCheck, before.fsrsHealthCheck)
        XCTAssertEqual(after.cardStateCustomizer, before.cardStateCustomizer)
        XCTAssertEqual(PaceStore.desiredRetention(c.backend, deckName: nil)!, 0.85, accuracy: 1e-6)
        XCTAssertEqual(PaceStore.desiredRetention(c.backend, deckName: "Sample::02 Squares")!, 0.85, accuracy: 1e-6)
    }

    func testFirstRunDefaultsTurnOnFsrsAndTenNewCards() throws {
        let c = try TempCollection()
        try PaceStore.applyStartDefaults(c.backend, newPerDay: PaceDefaults.newPerDay)
        let preset = try XCTUnwrap(PaceStore.presets(c.backend).first)
        let u = try PaceStore.forUpdate(c.backend, deck: preset.decks[0])
        XCTAssertTrue(u.fsrs)
        let config = try XCTUnwrap(u.allConfig.first { $0.config.id == preset.id }?.config.config)
        XCTAssertEqual(config.newPerDay, 10)
        XCTAssertEqual(config.desiredRetention, 0.9, accuracy: 1e-6)
        XCTAssertEqual(config.learnSteps, PaceDefaults.learnSteps)
        XCTAssertEqual(config.relearnSteps, PaceDefaults.relearnSteps)
        XCTAssertEqual(config.leechThreshold, PaceDefaults.leechThreshold)
    }

    func testWorkloadSimulationGivesAUsableCurve() throws {
        let c = try TempCollection(decks: ["sample-01", "sample-02"])
        try PaceStore.applyStartDefaults(c.backend, newPerDay: 10)
        let preset = try XCTUnwrap(PaceStore.presets(c.backend).first)
        let u = try PaceStore.forUpdate(c.backend, deck: preset.decks[0])
        let config = try XCTUnwrap(u.allConfig.first { $0.config.id == preset.id }?.config)
        let started = Date()
        let curve = try PaceStore.simulate(c.backend, PaceStore.simulationRequest(config, search: PaceStore.presetSearch(preset.name)))
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "the slider needs this to be quick")
        XCTAssertTrue(Workload.usable(curve))
        let at90 = try XCTUnwrap(curve[90]), at97 = try XCTUnwrap(curve[97]), at80 = try XCTUnwrap(curve[80])
        XCTAssertGreaterThan(at90, 0.5)
        XCTAssertLessThan(at90, 60)
        XCTAssertGreaterThan(at97, at90 * 1.3, "workload rises steeply above 90 %")
        XCTAssertLessThan(at80, at90)
        // More new cards a day cost more.
        var more = config
        more.config.newPerDay = 30
        let heavier = try PaceStore.simulate(c.backend, PaceStore.simulationRequest(more, search: PaceStore.presetSearch(preset.name)))
        XCTAssertGreaterThan(heavier[90]!, at90)
    }

    func testCardStatsHaveMemoryStateOnceFsrsIsOn() throws {
        let c = try TempCollection()
        try PaceStore.applyStartDefaults(c.backend, newPerDay: 10)
        let ids = try c.cardIDs("")
        try c.grade([ids[0]], .good)
        var id = Anki_Cards_CardId(); id.cid = ids[0]
        let s: Anki_Stats_CardStatsResponse = try c.backend.call(StatsMethods.cardStats, id)
        XCTAssertTrue(s.fsrsEnabled)
        XCTAssertTrue(s.hasMemoryState)
        XCTAssertEqual(s.revlog.count, 1)
        XCTAssertEqual(CardInfoMath.answerName(button: s.revlog[0].buttonChosen, kind: s.revlog[0].reviewKind), "Good")
    }

    func testSampleDecksAreRemovedOnlyWithoutHistory() throws {
        let c = try TempCollection()
        let top = try PaceStore.presets(c.backend).flatMap(\.decks)
        var names = Anki_Decks_GetDeckNamesRequest(); names.skipEmptyDefault = true
        let decks: Anki_Decks_DeckNames = try c.backend.call(DecksMethods.getDeckNames, names)
        let parent = try XCTUnwrap(decks.entries.first { !$0.name.contains("::") }?.id)
        XCTAssertFalse(top.isEmpty)

        let kept = try TempCollection()
        try addReviews(kept, passed: 1, failed: 0)
        let keptDecks: Anki_Decks_DeckNames = try kept.backend.call(DecksMethods.getDeckNames, names)
        try Onboarding.removeSamples(kept.backend, decks: keptDecks.entries.map(\.id))
        XCTAssertFalse(try kept.cardIDs("deck:*").isEmpty, "a collection with reviews is never touched")

        try Onboarding.removeSamples(c.backend, decks: [parent])
        XCTAssertTrue(try c.cardIDs("deck:*").isEmpty)
    }
}
