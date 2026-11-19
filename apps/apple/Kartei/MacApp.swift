// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

#if os(macOS)
import SwiftUI
import AppKit

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    /// The app is its one window; closing it ends the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// The menu bar. Review keys (Space, 1 to 4 and the rest) stay out of the menus on purpose: a menu key without a
/// modifier would swallow what is typed into an answer field. Help > Keyboard Shortcuts lists them instead.
struct MacCommands: Commands {
    let store: DeckStore
    let prefs: StudyPrefs
    @Bindable var router: Router
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    private var waiting: Bool { router.busy || store.backend == nil || !prefs.onboarded }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Import Deck…") { router.tab = .decks; router.importing = true }
                .keyboardShortcut("o")
                .disabled(waiting)
            Menu("Add Course Deck") {
                ForEach(CourseCatalogue.all) { course in
                    Button(course.title) { router.tab = .decks; store.importCourses([course]) }
                }
            }
            .disabled(waiting)
            Divider()
            Button("Sync Now") { SyncController.shared.sync() }
                .keyboardShortcut("r")
                .disabled(waiting || SyncController.shared.account == nil)
        }
        CommandGroup(before: .toolbar) {
            Button("Decks") { router.tab = .decks }.keyboardShortcut("1").disabled(waiting)
            Button("Browse") { router.tab = .browse }.keyboardShortcut("2").disabled(waiting)
            Button("Statistics") { router.tab = .stats }.keyboardShortcut("3").disabled(waiting)
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("Bergmönch Website") { open("https://apps.geist.pro/bergmoench/") }
            Button("Keyboard Shortcuts") { openWindow(id: "shortcuts") }
            Divider()
            Button("Improve a Course Card") { open("https://apps.geist.pro/bergmoench/#decks") }
            Button("Report a Problem") { open("https://github.com/geist-pro/bergmoench/issues") }
        }
    }

    private func open(_ address: String) {
        if let url = URL(string: address) { openURL(url) }
    }
}

/// Settings in their own window (Command-comma), one toolbar tab per topic.
struct MacSettingsView: View {
    let store: DeckStore
    let prefs: StudyPrefs
    @State private var page: SettingsView.Page = MacSettingsView.startPage

    private static var startPage: SettingsView.Page {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["KARTEI_TEST_SETTINGS"], let p = SettingsView.Page(rawValue: name) { return p }
        #endif
        return .appearance
    }

    var body: some View {
        TabView(selection: $page) {
            ForEach(SettingsView.Page.shown) { p in
                ScrollView {
                    SettingsPage(page: p, store: store, prefs: prefs)
                        .padding(.horizontal, 24).padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Ink.bg)
                .tabItem { Label(p.rawValue, systemImage: p.symbol) }
                .tag(p)
            }
        }
        .environment(prefs)
        .frame(width: 600, height: 620)
        .id("\(ThemeStore.shared.family.rawValue)-\(ThemeStore.shared.mode.rawValue)-\(ReadingPrefs.shared.contrast)")
    }
}

/// Help > Keyboard Shortcuts: the review keys, which are Anki's.
struct ShortcutsView: View {
    private static let groups: [(String, [(String, String)])] = [
        ("Review", [
            ("Space", "Show the answer, then Good (Got it)"),
            ("1", "Forgot"),
            ("2", "Hard (with four buttons)"),
            ("3", "Good, or Got it"),
            ("4", "Easy (with four buttons)"),
            ("⌘ Return", "Show the answer while typing one"),
            ("⌘ Z", "Undo the last answer"),
            ("R", "Play the audio again"),
            ("Esc", "Back to the decks"),
        ]),
        ("The card in front", [
            (".", "Card actions"),
            ("⌃ 1 to ⌃ 7", "Set or clear a flag"),
            ("−", "Bury until tomorrow"),
            ("@", "Suspend"),
        ]),
        ("Window", [
            ("⌘ 1, ⌘ 2, ⌘ 3", "Decks, Browse, Statistics"),
            ("⌘ O", "Import a deck"),
            ("⌘ R", "Sync now"),
            ("⌘ ,", "Settings"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Self.groups, id: \.0) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Caption(group.0).padding(.bottom, 4)
                    ForEach(group.1, id: \.0) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(row.0).font(Type.data(13)).foregroundStyle(Ink.text).frame(width: 120, alignment: .leading)
                            Text(row.1).font(Type.body(14)).foregroundStyle(Ink.text)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5)
                        .overlay(alignment: .bottom) { Rule() }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Ink.bg)
    }
}
#endif
