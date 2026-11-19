// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// What the menu bar and the window share: the screen in front, and requests the menus make of the window.
@Observable
final class Router {
    var tab: Tab = Router.startTab
    /// File > Import Deck… asks the window to show the file picker.
    var importing = false
    /// A review or the first-run screens are in front; the navigation commands wait.
    var busy = false
    /// Packages opened from the Finder before the collection was ready.
    var pendingPackages: [URL] = []

    /// Debug builds can open on a tab for screenshots: KARTEI_TEST_TAB=Settings.
    private static var startTab: Tab {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["KARTEI_TEST_TAB"], let t = Tab(rawValue: name) { return t }
        #endif
        return .decks
    }
}
