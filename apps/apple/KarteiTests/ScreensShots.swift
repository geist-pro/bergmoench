// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import AppKit
import SwiftUI
import XCTest
@testable import Kartei

/// Renders the Browse, Stats, Pace and onboarding screens inside the app, on a scratch collection with review history,
/// and writes PNGs. Opt-in: TEST_RUNNER_KARTEI_SHOTS=/out/dir TEST_RUNNER_KARTEI_SHOTS_DATA=/scratch/collection xcodebuild test …
final class ScreensShots: XCTestCase {
    private var out: URL!

    private func wait(_ seconds: Double, until done: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end && !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    private func shot<V: View>(_ name: String, height: CGFloat = 844, settle: Double = 2.5, _ view: V) {
        let host = NSHostingView(rootView: view.frame(width: 390, height: height).background(Ink.bg).preferredColorScheme(.dark))
        host.frame = NSRect(x: 0, y: 0, width: 390, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        window.orderFront(nil)
        wait(settle)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }

    /// A month of plausible history: reviews on most days, about 88 % remembered, then real FSRS grading on some cards.
    static func addHistory(_ backend: Backend) throws {
        try PaceStore.applyStartDefaults(backend, newPerDay: 10)
        var req = Anki_Search_SearchRequest(); req.search = "deck:*"
        let ids: Anki_Search_SearchResponse = try backend.call(SearchMethods.searchCards, req)
        let cards = ids.ids
        var grade = Anki_Scheduler_GradeNowRequest()
        grade.cardIds = Array(cards.prefix(120)); grade.rating = .good
        try backend.run(SchedulerMethods.gradeNow, grade)
        grade.cardIds = Array(cards.dropFirst(120).prefix(12)); grade.rating = .again
        try backend.run(SchedulerMethods.gradeNow, grade)
        var flag = Anki_Cards_SetFlagRequest(); flag.cardIds = [cards[1]]; flag.flag = 2
        let _: Anki_Collection_OpChangesWithCount = try backend.call(CardsMethods.setFlag, flag)
        flag.cardIds = [cards[3]]; flag.flag = 1
        let _: Anki_Collection_OpChangesWithCount = try backend.call(CardsMethods.setFlag, flag)
        try BrowseModel.setSuspended(backend, true, [cards[4]])

        var rng = SystemRandomNumberGenerator()
        let now = Int64(Date().timeIntervalSince1970)
        var id = (now - 30 * 86_400) * 1000
        for day in 0..<30 where day % 7 != 5 {
            let n = Int.random(in: 25...45, using: &rng)
            for k in 0..<n {
                id = (now - Int64(30 - day) * 86_400 + Int64(k * 20)) * 1000
                let ease = Double.random(in: 0...1, using: &rng) < 0.88 ? 3 : 1
                _ = try DB.query(backend, "insert into revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type) values (?, ?, 0, ?, 12, 9, 2500, ?, 1)",
                                 [id, cards[(day * 50 + k) % cards.count], ease, Int.random(in: 5_000...14_000, using: &rng)])
            }
        }
    }

    func testRenderScreens() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["KARTEI_SHOTS"], let data = env["KARTEI_SHOTS_DATA"] else { throw XCTSkip("set KARTEI_SHOTS and KARTEI_SHOTS_DATA") }
        out = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let fresh = !FileManager.default.fileExists(atPath: data + "/collection.anki2")
        setenv("KARTEI_DATA_DIR", data, 1)
        let store = DeckStore()
        store.load()
        wait(60) { if case .ready = store.phase { return true } else { return false } }
        let backend = try XCTUnwrap(store.backend)
        if fresh { try Self.addHistory(backend) }
        store.refresh()
        wait(2)
        let prefs = StudyPrefs()
        prefs.load(backend)

        shot("onboarding-welcome", OnboardingView(store: store, prefs: prefs))
        shot("onboarding-setup", OnboardingView(store: store, prefs: prefs, step: .setup))
        shot("stats", height: 1180, StatsView(store: store))
        shot("browse", BrowseView(store: store))

        let model = BrowseModel()
        model.attach(backend)
        wait(2) { !model.ids.isEmpty }
        let ids = model.ids
        for id in ids.prefix(40) { model.needRow(id) }
        wait(2)
        var graded = Anki_Search_SearchRequest(); graded.search = "-is:new"
        let seen: Anki_Search_SearchResponse = try backend.call(SearchMethods.searchCards, graded)
        let target = seen.ids.first ?? ids[0]
        model.needRow(target)
        wait(1)
        shot("card-info", CardInfoView(backend: backend, cardID: target, model: model) {})

        model.filter = .flagged
        model.run()
        shot("browse-flagged", BrowseView(store: store, model: model))

        let settings = ScrollView { VStack(alignment: .leading, spacing: 0) { StudySection(store: store, prefs: prefs); PaceSection(store: store) }.padding(.horizontal, 20) }
        shot("settings-study-pace", height: 1500, settle: 3.5, settings)

        let pace = PaceStore()
        pace.attach(backend, secondsPerCard: store.secondsPerCard)
        wait(5) { pace.loaded }
        shot("pace-advanced", PaceAdvanced(pace: pace) {})
        pace.config.config.desiredRetention = 0.97
        // The warning state is read by the live section from the collection, so write it there first.
        pace.save(debounce: false)
        wait(1.5)
        shot("pace-97", height: 1300, settle: 3.5, ScrollView { PaceSection(store: store).padding(.horizontal, 20) })
        pace.config.config.desiredRetention = 0.9
        pace.save(debounce: false)
        wait(1.5)
    }
}
