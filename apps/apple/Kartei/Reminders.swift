// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import UserNotifications

/// The person's reminder choice. Off by default: there is no evidence for a best time of day (docs/science-defaults.md).
struct ReminderSettings: Codable, Equatable {
    var enabled = false
    /// 19:00 is only a convenient starting point for the picker, not a recommendation.
    var hour = 19
    var minute = 0

    static func load(_ defaults: UserDefaults, scope: String) -> ReminderSettings {
        guard let data = defaults.data(forKey: key(scope)), let s = try? JSONDecoder().decode(ReminderSettings.self, from: data) else { return ReminderSettings() }
        return s
    }

    func save(_ defaults: UserDefaults, scope: String) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key(scope))
    }

    private static func key(_ scope: String) -> String { "kartei.reminder.\(scope)" }
}

struct PlannedReminder: Equatable {
    let id: String
    let fire: Date
    let title: String
    let body: String
}

enum ReminderPlan {
    /// How many days ahead to schedule. If the app is not opened for a week, reminders stop rather than pile up.
    static let horizon = 7

    /// Decide which notifications to schedule. `forecast[i]` is the number of cards due on day i (0 = today)
    /// if nothing is studied in between. Days with nothing due get no reminder; a time already past today is skipped.
    static func plan(_ settings: ReminderSettings, now: Date, forecast: [Int], secondsPerCard: Double, calendar: Calendar = .current) -> [PlannedReminder] {
        guard settings.enabled else { return [] }
        var out: [PlannedReminder] = []
        let today = calendar.startOfDay(for: now)
        for (offset, cards) in forecast.prefix(horizon).enumerated() where cards > 0 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: day),
                  fire > now else { continue }
            let minutes = estimateMinutes(cards: cards, secondsPerCard: secondsPerCard)
            out.append(PlannedReminder(id: "kartei.reminder.\(ReachSnapshot.dayKey(day, calendar: calendar))", fire: fire,
                                       title: "\(minutes) min of cards today",
                                       body: body(cards: cards)))
        }
        return out
    }

    /// Same estimate as the home screen: cards × seconds per card, rounded to minutes, at least 1.
    static func estimateMinutes(cards: Int, secondsPerCard: Double) -> Int {
        cards == 0 ? 0 : max(1, Int((Double(cards) * secondsPerCard + 30) / 60))
    }

    /// Specific and forgiving: what is waiting, and that any part of it is fine. No streaks, no "don't lose".
    static func body(cards: Int) -> String {
        "\(cards) \(cards == 1 ? "card is" : "cards are") ready whenever suits you. A few is fine too."
    }
}

/// Schedules the planned reminders with the system. Each refresh replaces all of Kartei's pending reminders.
enum ReminderScheduler {
    static let prefix = "kartei.reminder."

    /// Ask once, when the person turns reminders on.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func apply(_ plan: [PlannedReminder]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            for r in plan {
                let content = UNMutableNotificationContent()
                content.title = r.title
                content.body = r.body
                content.sound = nil
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: r.fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger)) { error in
                    #if DEBUG
                    NSLog("Kartei reminder %@ at %@: %@ — %@ %@", r.id, r.fire.description, error?.localizedDescription ?? "scheduled", r.title, r.body)
                    #endif
                }
            }
        }
    }
}
