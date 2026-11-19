// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

/// One-time defaults for collections that never went through onboarding (docs/science-defaults.md).
enum FirstRunDefaults {
    static let fsrsKey = "kartei.fsrsDefaulted"

    /// Turn FSRS on once, through Anki's deck-options save so existing review history gets memory states.
    /// After that the person's own choice stands: switching it off in Pace is never undone.
    static func enableFsrsOnce(_ backend: Backend) {
        guard backend.config(fsrsKey, as: Bool.self) != true else { return }
        defer { backend.setConfig(fsrsKey, true) }
        guard let update = try? PaceStore.forUpdate(backend, deck: 1), !update.fsrs else { return }
        let config = update.allConfig.first { $0.config.id == update.currentDeck.configID }?.config ?? update.defaults
        try? PaceStore.write(backend, config: config, fsrs: true, deck: 1, update: update)
    }
}
