// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Wording for the Simple / Full choice, shared by Settings and the first run.
enum DetailCopy {
    static let simpleTitle = "Simple"
    static let simple = "Two buttons, Forgot and Got it, and minutes instead of counts. Good if spaced repetition is new to you."
    static let fullTitle = "Full"
    static let full = "Four buttons, intervals, and new / learning / due counts. Like Anki."
    /// One line of evidence (docs/science-defaults.md, Grading).
    static let evidence = "FSRS schedules about as well with two buttons as with four, and two buttons avoid pressing Hard for a card you actually forgot."
}

/// Study settings: how much detail the review screen shows.
struct StudySection: View {
    let store: DeckStore
    let prefs: StudyPrefs

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Study")
            Caption("Detail level").padding(.top, 4)
            OptionRow(title: DetailCopy.simpleTitle, detail: DetailCopy.simple, selected: prefs.detail == .simple) { prefs.setDetail(.simple) }
            OptionRow(title: DetailCopy.fullTitle, detail: DetailCopy.full, selected: prefs.detail == .full) { prefs.setDetail(.full) }
            Meta(DetailCopy.evidence).padding(.top, 8)
        }
    }
}
