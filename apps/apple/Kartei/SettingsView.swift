// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Settings: one index of rows, each with its current value, opening a page of its own. The pages are the
/// sections (AppearanceSection, StudySection, PaceSection, RemindersSection, SyncSection), so each topic gets
/// the whole screen instead of sharing one long scroll.
struct SettingsView: View {
    let store: DeckStore
    let prefs: StudyPrefs

    enum Page: String, CaseIterable, Identifiable {
        case appearance = "Appearance", reading = "Reading", study = "Study", touch = "Touch controls", pace = "Pace", reminders = "Reminders", sync = "Sync"
        var id: String { rawValue }
        /// Touch controls only where there is a touch screen.
        static var shown: [Page] {
            #if os(iOS)
            allCases
            #else
            allCases.filter { $0 != .touch }
            #endif
        }
        /// The toolbar symbol of the page in the macOS Settings window.
        var symbol: String {
            switch self {
            case .appearance: "paintpalette"
            case .reading: "textformat.size"
            case .study: "rectangle.on.rectangle"
            case .touch: "hand.draw"
            case .pace: "gauge.with.dots.needle.50percent"
            case .reminders: "bell"
            case .sync: "arrow.triangle.2.circlepath"
            }
        }
    }

    @State private var page: Page? = Self.startPage

    /// Debug builds can open a page for screenshots: KARTEI_TEST_SETTINGS=Pace.
    private static var startPage: Page? {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["KARTEI_TEST_SETTINGS"] { return Page(rawValue: name) }
        #endif
        return nil
    }

    var body: some View {
        Group {
            if let page {
                VStack(spacing: 0) {
                    ScreenNav(title: "Settings", back: { self.page = nil })
                    ScrollView {
                        SettingsPage(page: page, store: store, prefs: prefs)
                            .padding(.horizontal, 20).padding(.bottom, 32)
                            .frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
                    }
                }
            } else {
                index
            }
        }
        .background(Ink.bg)
    }

    private var index: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings").font(Type.display(34, heavy: true)).foregroundStyle(Ink.display)
                    .padding(.top, 12).padding(.bottom, 16)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Page.shown) { p in
                    ListLine(title: p.rawValue, detail: detail(p)) { page = p }
                }
                Text("Bergmönch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""), Anki backend \(Backend.ankiVersion). Free software under the GNU AGPL.")
                    .font(Type.body(13)).foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
            .frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    /// The current value of each page, so the index answers "how is it set?" without opening anything.
    private func detail(_ p: Page) -> String {
        switch p {
        case .appearance:
            let theme = ThemeStore.shared
            return "\(theme.family.title), \(theme.mode.title.lowercased())"
        case .reading:
            let r = ReadingPrefs.shared
            let size = "Card text \(Int((ReadingPrefs.cardScales[r.cardStep] * 100).rounded()))%"
            return [size, r.regularQuestions ? "regular questions" : nil, r.strongContrast ? "stronger contrast" : nil].compactMap { $0 }.joined(separator: ", ")
        case .study:
            return prefs.detail == .simple ? "Simple: Forgot and Got it, minutes" : "Full: four buttons, counts and intervals"
        case .touch:
            let t = TouchPrefs.shared
            guard t.swipeToGrade else { return "Swipe to grade off" }
            let extra = [t.swipeEasy ? "up Easy" : nil, t.swipeHard ? "down Hard" : nil].compactMap { $0 }
            return "Swipe right Got it, left Forgot" + (extra.isEmpty ? "" : ", " + extra.joined(separator: ", "))
        case .pace:
            return "How much should stick, new cards a day"
        case .reminders:
            let r = ReachCoordinator.shared.reminders
            return r.enabled ? String(format: "Daily at %02d:%02d, only when cards are due", r.hour, r.minute) : "Off"
        case .sync:
            if let account = SyncController.shared.account { return "\(account.username) at \(account.endpoint)" }
            return "Not set up. Your own Anki sync server only."
        }
    }
}

/// One settings topic, shared by the iOS page and the macOS Settings window.
struct SettingsPage: View {
    let page: SettingsView.Page
    let store: DeckStore
    let prefs: StudyPrefs

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch page {
            case .appearance: AppearanceSection()
            case .reading: ReadingSection(store: store)
            case .study: StudySection(store: store, prefs: prefs)
            case .touch: TouchSection(prefs: prefs)
            case .pace: PaceSection(store: store)
            case .reminders: RemindersSection(store: store)
            case .sync: SyncSection(store: store)
            }
        }
    }
}
