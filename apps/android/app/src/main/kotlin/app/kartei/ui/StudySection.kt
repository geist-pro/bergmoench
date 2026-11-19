// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.kartei.DeckStore
import app.kartei.StudyPrefs

/** How much the review screen shows. Simple is the default for new users (docs/science-defaults.md, Grading). */
@Suppress("UNUSED_PARAMETER")
@Composable
fun StudySection(store: DeckStore, prefs: StudyPrefs) {
    Column {
        KSectionHead("Detail level", "default Simple")
        DetailChoice(prefs)
        KCaption("Two buttons schedule as accurately as four, and Simple leaves out Hard, the button most often misused.",
            Modifier.padding(top = 6.dp, bottom = 8.dp))
    }
}

@Composable
internal fun DetailChoice(prefs: StudyPrefs) {
    KOption("Simple", "Forgot or Got it, and minutes instead of card counts. Good if spaced repetition is new to you.", prefs.detail == StudyPrefs.Detail.Simple) {
        prefs.updateDetail(StudyPrefs.Detail.Simple)
    }
    KOption("Full", "Four buttons, intervals, and new / learning / due counts, like Anki.", prefs.detail == StudyPrefs.Detail.Full) {
        prefs.updateDetail(StudyPrefs.Detail.Full)
    }
}
