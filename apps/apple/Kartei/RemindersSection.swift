// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import UserNotifications

/// Settings → Reminder. Off until chosen; when on, a notification at the chosen time, only on days with cards due.
struct RemindersSection: View {
    let store: DeckStore
    @State private var settings = ReminderSettings()
    @State private var loaded = false
    @State private var denied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reminder").font(Type.display(22, heavy: true)).foregroundStyle(Ink.text)
            HStack {
                Text("Remind me when cards are due").font(Type.body(15)).foregroundStyle(Ink.text)
                Spacer()
                Toggle("Remind me when cards are due", isOn: Binding(get: { settings.enabled }, set: toggle))
                    .labelsHidden().toggleStyle(.switch).tint(Ink.accent)
            }
            .frame(minHeight: 44)
            if settings.enabled {
                HStack {
                    Text("Time").font(Type.body(15)).foregroundStyle(Ink.text)
                    Spacer()
                    DatePicker("Time", selection: Binding(get: { time }, set: setTime), displayedComponents: .hourAndMinute)
                        .labelsHidden().tint(Ink.accent)
                }
                .frame(minHeight: 44)
                Text(preview).font(Type.body(13)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            }
            if denied {
                Text("Notifications are turned off for Bergmönch in System Settings, so the reminder cannot appear.")
                    .font(Type.body(13)).foregroundStyle(Ink.forgot).fixedSize(horizontal: false, vertical: true)
            }
            Text("Off unless you turn it on. No time of day has been shown to be better for studying; 19:00 is only a starting point. Days with nothing due stay quiet, and the reminder never counts streaks.")
                .font(Type.body(12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.rule).frame(height: 1) }
        .onChange(of: store.reachScope, initial: true) { _, scope in
            guard let scope, !loaded else { return }
            settings = ReminderSettings.load(.standard, scope: scope)
            loaded = true
        }
    }

    private var time: Date {
        Calendar.current.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: .now) ?? .now
    }

    private var preview: String {
        let cards = store.cardsToday
        if cards == 0 { return "Nothing is due today, so there is no reminder today." }
        let minutes = ReminderPlan.estimateMinutes(cards: cards, secondsPerCard: store.secondsPerCard)
        return "On days with cards due, at \(time.formatted(date: .omitted, time: .shortened)): “\(minutes) min of cards today. \(ReminderPlan.body(cards: cards))”"
    }

    private func toggle(_ on: Bool) {
        guard on else { save { $0.enabled = false }; denied = false; return }
        Task {
            let granted = await ReminderScheduler.requestPermission()
            denied = !granted
            save { $0.enabled = granted }
        }
    }

    private func setTime(_ date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        save { $0.hour = c.hour ?? 19; $0.minute = c.minute ?? 0 }
    }

    private func save(_ change: (inout ReminderSettings) -> Void) {
        change(&settings)
        ReachCoordinator.shared.setReminders(settings, store: store)
    }
}
