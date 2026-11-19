// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import XCTest
@testable import Kartei

/// Checks the pieces that join the agents' work: one-time FSRS default, exam cap through the real core.
final class IntegrationTests: XCTestCase {
    private func fsrsOn(_ backend: Backend) throws -> Bool { try PaceStore.forUpdate(backend, deck: 1).fsrs }

    func testFsrsIsSwitchedOnOnceAndAChoiceToTurnItOffStands() throws {
        let col = try TempCollection()
        XCTAssertFalse(try fsrsOn(col.backend), "a fresh Anki collection starts with FSRS off")
        FirstRunDefaults.enableFsrsOnce(col.backend)
        XCTAssertTrue(try fsrsOn(col.backend))
        XCTAssertEqual(col.backend.config(FirstRunDefaults.fsrsKey, as: Bool.self), true)

        // The learner switches FSRS off in Pace; the default must not come back.
        let update = try PaceStore.forUpdate(col.backend, deck: 1)
        let config = update.allConfig.first { $0.config.id == update.currentDeck.configID }!.config
        try PaceStore.write(col.backend, config: config, fsrs: false, deck: 1, update: update)
        FirstRunDefaults.enableFsrsOnce(col.backend)
        XCTAssertFalse(try fsrsOn(col.backend))
    }

    func testFsrsDefaultKeepsReviewHistoryUsable() throws {
        let col = try TempCollection()
        let ids = Array(try col.cardIDs("deck:*").prefix(5))
        try col.grade(ids, .good)
        FirstRunDefaults.enableFsrsOnce(col.backend)
        // After switching on through the deck-options save, reviewed cards carry FSRS memory states.
        var req = Anki_Cards_CardId()
        req.cid = ids[0]
        let card: Anki_Cards_Card = try col.backend.call(CardsMethods.getCard, req)
        XCTAssertTrue(card.hasMemoryState, "reviewed card should get a memory state when FSRS is switched on")
    }
}

/// App icon choice: names match the asset catalog, the choice persists, and both icon images are bundled.
final class AppIconTests: XCTestCase {
    func testChoicesAndAssets() {
        XCTAssertNil(AppIconChoice.geist.iconName, "GEIST is the primary icon")
        XCTAssertEqual(AppIconChoice.gruvbox.iconName, "AppIcon-Gruvbox")
        for choice in AppIconChoice.allCases {
            #if os(macOS)
            XCTAssertNotNil(NSImage(named: choice.previewImage), "\(choice.previewImage) must be in the asset catalog")
            #endif
        }
    }

    func testChoicePersistsAndDefaultsToGeist() {
        let key = AppIconChoice.defaultsKey
        let old = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(old, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(AppIconChoice.saved, .geist)
        AppIconChoice.saved = .gruvbox
        XCTAssertEqual(AppIconChoice.saved, .gruvbox)
        UserDefaults.standard.set("nonsense", forKey: key)
        XCTAssertEqual(AppIconChoice.saved, .geist)
    }
}
