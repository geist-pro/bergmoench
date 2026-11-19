// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import Observation
import WidgetKit

/// Hooks for sync, widget and reminders; called whenever the deck counts or the study calendar change.
enum Reach {
    static func storeDidUpdate(_ store: DeckStore) {
        MainActor.assumeIsolated { ReachCoordinator.shared.update(store) }
    }
}

extension DeckStore {
    /// The folder holding collection.anki2 and media (KARTEI_DATA_DIR in debug runs).
    var dataFolder: URL? { mediaFolder?.deletingLastPathComponent() }

    /// Separates per-collection state (sync login, last sync, reminder) so test collections never touch the real one.
    var reachScope: String? { dataFolder?.standardizedFileURL.path }
}

/// Keeps the widget snapshot and the reminders in step with the collection, and connects sync once it is open.
@MainActor
final class ReachCoordinator {
    static let shared = ReachCoordinator()

    private var tracking = false
    private var pending: Task<Void, Never>?
    private(set) var reminders = ReminderSettings()
    private var scope: String?

    func update(_ store: DeckStore) {
        guard store.backend != nil, let scope = store.reachScope else { return }
        if self.scope != scope {
            self.scope = scope
            reminders = ReminderSettings.load(.standard, scope: scope)
            var keychain = Keychain(service: "app.kartei.sync")
            #if DEBUG
            if ProcessInfo.processInfo.environment["KARTEI_DATA_DIR"] != nil { keychain.debugFolder = store.dataFolder }
            #endif
            SyncController.shared.attach(store, scope: scope, keychain: keychain)
        }
        track(store)
        // Several changes arrive together (rows, totals, calendar); act once they settle.
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.publish(store)
        }
    }

    func setReminders(_ settings: ReminderSettings, store: DeckStore) {
        reminders = settings
        if let scope = store.reachScope { settings.save(.standard, scope: scope) }
        update(store)
    }

    /// AppShell only reports deck-list and calendar changes; also follow the due counts (after a review session, a sync).
    private func track(_ store: DeckStore) {
        guard !tracking else { return }
        tracking = true
        withObservationTracking {
            _ = store.cardsToday
            _ = store.studiedDays
            _ = store.secondsPerCard
        } onChange: {
            Task { @MainActor in
                ReachCoordinator.shared.tracking = false
                ReachCoordinator.shared.update(store)
            }
        }
    }

    private func publish(_ store: DeckStore) async {
        guard let backend = store.backend else { return }
        let settings = reminders
        let today = store.cardsToday
        let secondsPerCard = store.secondsPerCard
        let studied = store.studiedDays
        let now = Date.now
        let later = await Task.detached { Self.forecast(backend, from: now, days: ReminderPlan.horizon, hour: settings.enabled ? settings.hour : 12, minute: settings.minute) }.value
        let forecast = [today] + later

        let snapshot = Self.snapshot(now: now, studied: studied, forecast: forecast, secondsPerCard: secondsPerCard, family: ThemeStore.shared.family)
        if ReachShared.write(snapshot, to: Self.snapshotURL(store)) {
            WidgetCenter.shared.reloadTimelines(ofKind: ReachShared.widgetKind)
        }
        let plan = ReminderPlan.plan(settings, now: now, forecast: forecast, secondsPerCard: secondsPerCard)
        ReminderScheduler.apply(plan)  // an empty plan clears what was scheduled before
        lastPlan = plan
    }

    /// The most recent reminder plan, for the Settings section and tests.
    private(set) var lastPlan: [PlannedReminder] = []

    /// Debug runs with KARTEI_DATA_DIR keep the snapshot next to their collection, away from the real widget.
    nonisolated static func snapshotURL(_ store: DeckStore) -> URL? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["KARTEI_DATA_DIR"] != nil, let folder = store.dataFolder {
            return folder.appendingPathComponent(ReachShared.fileName)
        }
        #endif
        return ReachShared.snapshotURL()
    }

    nonisolated static func snapshot(now: Date, studied: Set<Int>, forecast: [Int], secondsPerCard: Double, family: ThemeFamily = Palette.defaultFamily, calendar: Calendar = .current) -> ReachSnapshot {
        let start = calendar.startOfDay(for: now)
        let days = studied.compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { ReachSnapshot.dayKey($0, calendar: calendar) }.sorted()
        let entries = forecast.enumerated().compactMap { offset, cards -> ReachSnapshot.Day? in
            guard let d = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return .init(day: ReachSnapshot.dayKey(d, calendar: calendar), minutes: ReminderPlan.estimateMinutes(cards: cards, secondsPerCard: secondsPerCard), cards: cards)
        }
        return ReachSnapshot(written: now, studied: days, days: entries, family: family.rawValue)
    }

    /// Cards due on each of the next `days - 1` days at the given time, if nothing is studied in between
    /// (Anki's deck tree evaluated at a future timestamp, with that day's fresh new-card limits).
    nonisolated static func forecast(_ backend: Backend, from now: Date, days: Int, hour: Int, minute: Int, calendar: Calendar = .current) -> [Int] {
        let start = calendar.startOfDay(for: now)
        return (1..<max(days, 1)).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let at = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return 0 }
            var req = Anki_Decks_DeckTreeRequest()
            req.now = Int64(at.timeIntervalSince1970)
            guard let tree: Anki_Decks_DeckTreeNode = try? backend.call(DecksMethods.deckTree, req) else { return 0 }
            return tree.children.reduce(0) { $0 + Int($1.newCount + $1.learnCount + $1.reviewCount) }
        }
    }
}
