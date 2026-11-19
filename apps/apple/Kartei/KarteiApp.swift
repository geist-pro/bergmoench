// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

@main
struct KarteiApp: App {
    @State private var store = DeckStore()

    init() {
        Type.register()
        #if os(macOS)
        // The Dock icon choice lasts only while the app runs, so re-apply it at launch.
        DispatchQueue.main.async { AppIconChoice.saved.apply() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppShell(store: store)
                .themed()
                // Unit tests run inside the app; they open their own temporary collections, never this one.
                .task { if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { store.load() } }
                #if os(macOS)
                .frame(minWidth: 390, idealWidth: 390, maxWidth: 520, minHeight: 700, idealHeight: 844)
                #endif
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        #endif
    }
}
