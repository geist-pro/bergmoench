// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

@main
struct KarteiApp: App {
    @State private var store = DeckStore()
    @State private var prefs = StudyPrefs()
    @State private var router = Router()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    init() {
        Type.register()
        #if os(macOS)
        // The Dock icon choice lasts only while the app runs, so re-apply it at launch.
        DispatchQueue.main.async { AppIconChoice.saved.apply() }
        #endif
    }

    private var shell: some View {
        AppShell(store: store, prefs: prefs, router: router)
            .themed()
            // Unit tests run inside the app; they open their own temporary collections, never this one.
            .task { if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { store.load() } }
    }

    var body: some Scene {
        #if os(macOS)
        // One collection, one window: a second window would show the same decks and fight over the review.
        Window("Bergmönch", id: "main") {
            shell.frame(minWidth: 480, minHeight: 560)
        }
        .defaultSize(width: 960, height: 760)
        .windowResizability(.contentMinSize)
        .commands { MacCommands(store: store, prefs: prefs, router: router) }

        Settings {
            MacSettingsView(store: store, prefs: prefs).themed()
        }

        Window("Keyboard Shortcuts", id: "shortcuts") {
            ShortcutsView().themed()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        #else
        WindowGroup { shell }
        #endif
    }
}
