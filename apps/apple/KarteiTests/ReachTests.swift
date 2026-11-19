// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import XCTest
@testable import Kartei

final class ReachSnapshotTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testRoundTripAndVersionGate() throws {
        let s = ReachSnapshot(written: date(2026, 11, 14), studied: ["2026-11-13", "2026-11-14"],
                              days: [.init(day: "2026-11-14", minutes: 12, cards: 54), .init(day: "2026-11-15", minutes: 3, cards: 14)])
        let data = try s.encoded()
        XCTAssertEqual(ReachSnapshot.decode(data), s)
        // A snapshot from a different format version is ignored rather than misread.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["version"] = 99
        XCTAssertNil(ReachSnapshot.decode(try JSONSerialization.data(withJSONObject: json)))
        XCTAssertNil(ReachSnapshot.decode(Data("not json".utf8)))
    }

    func testBuiltFromStoreAndRollsOverAtMidnight() {
        let now = date(2026, 11, 14, 22)
        let s = ReachCoordinator.snapshot(now: now, studied: [0, -1, -6, -34], forecast: [54, 14, 0], secondsPerCard: 8, calendar: cal)
        XCTAssertEqual(s.studied, ["2026-10-11", "2026-11-08", "2026-11-13", "2026-11-14"])
        XCTAssertEqual(s.days.map(\.day), ["2026-11-14", "2026-11-15", "2026-11-16"])
        XCTAssertEqual(s.days.map(\.minutes), [7, 2, 0])  // 54 × 8 s = 7.2 min; 14 × 8 s ≈ 1.9; nothing due → 0
        XCTAssertEqual(s.day(for: now, calendar: cal)?.cards, 54)
        XCTAssertEqual(s.studiedOffsets(relativeTo: now, calendar: cal), [0, -1, -6, -34])

        // The widget renders the next day from the same snapshot: offsets shift, the oldest day drops out of the 35.
        let tomorrow = date(2026, 11, 15, 0, 1)
        XCTAssertEqual(s.day(for: tomorrow, calendar: cal)?.cards, 14)
        XCTAssertEqual(s.studiedOffsets(relativeTo: tomorrow, calendar: cal), [-1, -2, -7])
        XCTAssertNil(s.day(for: date(2026, 11, 20), calendar: cal))
    }

    func testWritesAndReadsFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("snap.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let s = ReachSnapshot(written: .now, studied: [], days: [.init(day: "2026-11-14", minutes: 1, cards: 3)])
        XCTAssertTrue(ReachShared.write(s, to: url))
        XCTAssertEqual(ReachShared.read(from: url)?.days, s.days)
        XCTAssertNil(ReachShared.read(from: url.deletingLastPathComponent().appendingPathComponent("missing.json")))
    }
}

final class ReminderPlanTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()
    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))! }
    private var on: ReminderSettings { ReminderSettings(enabled: true, hour: 19, minute: 0) }

    func testDefaultIsOff() {
        XCTAssertFalse(ReminderSettings().enabled)
        XCTAssertTrue(ReminderPlan.plan(ReminderSettings(), now: at(14, 10), forecast: [50, 50], secondsPerCard: 8, calendar: cal).isEmpty)
    }

    func testOnlyDaysWithCardsDue() {
        let plan = ReminderPlan.plan(on, now: at(14, 10), forecast: [90, 0, 7], secondsPerCard: 8, calendar: cal)
        XCTAssertEqual(plan.map(\.fire), [at(14, 19), at(16, 19)])
        XCTAssertEqual(plan.first?.title, "12 min of cards today")  // 90 × 8 s = 12 min
        XCTAssertEqual(plan.first?.id, "kartei.reminder.2026-11-14")
        XCTAssertEqual(plan.last?.title, "1 min of cards today")
    }

    func testNothingDueMeansNoReminder() {
        XCTAssertTrue(ReminderPlan.plan(on, now: at(14, 10), forecast: [0, 0, 0], secondsPerCard: 8, calendar: cal).isEmpty)
    }

    func testTimeAlreadyPassedTodayStartsTomorrow() {
        let plan = ReminderPlan.plan(on, now: at(14, 19, 30), forecast: [40, 20], secondsPerCard: 8, calendar: cal)
        XCTAssertEqual(plan.map(\.fire), [at(15, 19)])
    }

    func testHorizonCapsAWeek() {
        let plan = ReminderPlan.plan(on, now: at(14, 8), forecast: Array(repeating: 5, count: 30), secondsPerCard: 8, calendar: cal)
        XCTAssertEqual(plan.count, ReminderPlan.horizon)
    }

    func testWordingIsForgiving() {
        for cards in [1, 2, 140] {
            let text = (ReminderPlan.plan(on, now: at(14, 8), forecast: [cards], secondsPerCard: 8, calendar: cal).first.map { $0.title + " " + $0.body } ?? "").lowercased()
            XCTAssertTrue(text.contains("\(cards) card"), text)
            for banned in ["streak", "don't", "lose", "miss", "behind", "!"] { XCTAssertFalse(text.contains(banned), "\(banned) in \(text)") }
        }
        XCTAssertEqual(ReminderPlan.body(cards: 1), "1 card is ready whenever suits you. A few is fine too.")
    }

    func testSettingsPersistPerScope() {
        let d = UserDefaults(suiteName: "kartei.tests.\(UUID().uuidString)")!
        ReminderSettings(enabled: true, hour: 7, minute: 30).save(d, scope: "/a")
        XCTAssertEqual(ReminderSettings.load(d, scope: "/a"), ReminderSettings(enabled: true, hour: 7, minute: 30))
        XCTAssertEqual(ReminderSettings.load(d, scope: "/b"), ReminderSettings())
    }
}

final class SyncTextTests: XCTestCase {
    func testSyncedAgo() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(SyncText.syncedAgo(nil, now: now), "Not synced yet")
        XCTAssertEqual(SyncText.syncedAgo(now.addingTimeInterval(-20), now: now), "Synced just now")
        XCTAssertEqual(SyncText.syncedAgo(now.addingTimeInterval(-120), now: now), "Synced 2 min ago")
        XCTAssertEqual(SyncText.syncedAgo(now.addingTimeInterval(-59 * 60), now: now), "Synced 59 min ago")
        XCTAssertEqual(SyncText.syncedAgo(now.addingTimeInterval(-3 * 3600 - 100), now: now), "Synced 3 h ago")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let noon = cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!
        XCTAssertEqual(SyncText.syncedAgo(cal.date(byAdding: .hour, value: -20, to: noon), now: noon, calendar: cal), "Synced yesterday")
        XCTAssertEqual(SyncText.syncedAgo(cal.date(byAdding: .day, value: -5, to: noon), now: noon, calendar: cal), "Synced 9 Nov")
        XCTAssertEqual(SyncText.syncedAgo(cal.date(byAdding: .year, value: -1, to: noon), now: noon, calendar: cal), "Synced 14 Nov 2025")
    }

    func testEndpointNormalising() {
        XCTAssertEqual(try? SyncText.endpoint(from: " 192.168.1.20:8080 ").get(), "http://192.168.1.20:8080/")
        XCTAssertEqual(try? SyncText.endpoint(from: "localhost:27701").get(), "http://localhost:27701/")
        XCTAssertEqual(try? SyncText.endpoint(from: "nas.local:8080").get(), "http://nas.local:8080/")
        XCTAssertEqual(try? SyncText.endpoint(from: "sync.example.org").get(), "https://sync.example.org/")
        XCTAssertEqual(try? SyncText.endpoint(from: "https://sync.example.org/anki").get(), "https://sync.example.org/anki/")
        XCTAssertNil(try? SyncText.endpoint(from: "").get())
        XCTAssertNil(try? SyncText.endpoint(from: "ftp://x").get())
    }

    func testAnkiWebIsRefused() {
        for typed in ["https://sync.ankiweb.net/", "ankiweb.net", "sync2.ankiweb.net"] {
            guard case .failure(let p) = SyncText.endpoint(from: typed) else { return XCTFail(typed) }
            XCTAssertTrue(p.text.contains("AnkiWeb"), p.text)
        }
    }

    func testPlainErrors() {
        XCTAssertEqual(SyncText.plain("Email or password was incorrect; please try again."), "The server did not accept that username and password.")
        XCTAssertTrue(SyncText.plain("A network error occurred. error sending request for url (http://127.0.0.1:1/sync/hostKey)").hasPrefix("Could not reach"))
        XCTAssertTrue(SyncText.plain("Connection timed out. Please try again.").hasPrefix("The server took too long"))
        XCTAssertTrue(SyncText.plain("Only one copy of Anki can sync to your account at once.").hasPrefix("Another device"))
        XCTAssertFalse(SyncText.plain("AnkiWeb encountered a problem. Please try again in a few minutes.").contains("AnkiWeb"))
        XCTAssertEqual(SyncText.plain("weird"), "Sync did not finish: weird")
    }
}

final class KeychainTests: XCTestCase {
    func testSetReadReplaceRemove() throws {
        let kc = Keychain(service: "app.kartei.tests.\(UUID().uuidString)")
        let account = "/tmp/collection-\(UUID().uuidString)"
        defer { try? kc.remove(account) }
        XCTAssertNil(try kc.value(SyncAccount.self, for: account))
        let a = SyncAccount(hkey: "abc", endpoint: "http://127.0.0.1:27702/", username: "kai")
        try kc.set(a, for: account)
        XCTAssertEqual(try kc.value(SyncAccount.self, for: account), a)
        var b = a
        b.hkey = "def"
        try kc.set(b, for: account)
        XCTAssertEqual(try kc.value(SyncAccount.self, for: account), b)
        XCTAssertNil(try kc.value(SyncAccount.self, for: account + "-other"))
        try kc.remove(account)
        XCTAssertNil(try kc.value(SyncAccount.self, for: account))
        try kc.remove(account)  // removing twice is fine
    }

    func testAccountNeverHoldsPassword() throws {
        let json = String(decoding: try JSONEncoder().encode(SyncAccount(hkey: "k", endpoint: "http://x/", username: "u")), as: UTF8.self)
        XCTAssertFalse(json.lowercased().contains("password"))
        XCTAssertEqual(SyncAccount(hkey: "k", endpoint: "http://192.168.1.20:8080/", username: "u").host, "192.168.1.20:8080")
    }
}

final class WidgetRenderTests: XCTestCase {
    /// Renders the widget views to PNGs (KARTEI_WIDGET_SHOTS=/folder) so they can be looked at without a widget host.
    @MainActor
    func testRenderSmallAndMedium() throws {
        let now = Date.now
        let studied = Set([0, -1, -2, -4, -5, -7, -8, -9, -11, -14, -15, -16, -18, -21, -25, -28, -29, -32])
        let snap = ReachCoordinator.snapshot(now: now, studied: studied, forecast: [90, 40], secondsPerCard: 8)
        WidgetType.register()
        for (size, w, h, name) in [(ReachWidgetContent.Size.small, 170.0, 170.0, "small"), (.medium, 364.0, 170.0, "medium")] {
            let view = ReachWidgetContent(snapshot: snap, date: now, size: size).padding(16).frame(width: w, height: h).background(WidgetInk(snap.themeFamily, dark: true).bg)
                .environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: view)
            r.scale = 2
            let image = try XCTUnwrap(r.cgImage)
            XCTAssertEqual(image.width, Int(w * 2))
            if let dir = ProcessInfo.processInfo.environment["KARTEI_WIDGET_SHOTS"] {
                let url = URL(fileURLWithPath: dir).appendingPathComponent("widget-\(name).png")
                let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
                CGImageDestinationAddImage(dest, image, nil)
                XCTAssertTrue(CGImageDestinationFinalize(dest))
            }
        }
        // Empty state, before the app has written anything.
        XCTAssertNotNil(ImageRenderer(content: ReachWidgetContent(snapshot: nil, date: now, size: .medium).frame(width: 364, height: 170)).cgImage)
    }
}

final class DebugKeyFileTests: XCTestCase {
    func testScriptedRunsKeepKeyInScratchFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var kc = Keychain(service: "app.kartei.sync")
        kc.debugFolder = dir
        let a = SyncAccount(hkey: "h", endpoint: "http://127.0.0.1:27702/", username: "kai")
        try kc.set(a, for: "/some/collection")
        XCTAssertEqual(try kc.value(SyncAccount.self, for: "/some/collection"), a)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 1)
        try kc.remove("/some/collection")
        XCTAssertNil(try kc.value(SyncAccount.self, for: "/some/collection"))
    }
}
