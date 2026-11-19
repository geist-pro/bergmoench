// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.kartei.StudyPrefs
import app.kartei.TouchPrefs

/** Settings → Touch controls (touch.html): swipe to grade and its opt-in directions, tap to reveal, haptics. */
@Composable
fun TouchSection(prefs: StudyPrefs) {
    val touch = TouchPrefs.of(LocalContext.current)
    val full = prefs.detail == StudyPrefs.Detail.Full
    Column {
        KSectionHead("Touch controls")
        BasicText("Swipes grade the card once the answer shows: right is Got it, left is Forgot. The buttons stay.",
            style = kBody(14, color = Ink.muted))
        ReachToggle("Swipe to grade", touch.swipeToGrade, onChange = touch::updateSwipe)
        if (touch.swipeToGrade) {
            ReachToggle("Swipe up for Easy (Full detail)", touch.swipeEasy, onChange = touch::updateEasy)
            ReachToggle("Swipe down for Hard (Full detail)", touch.swipeHard, onChange = touch::updateHard)
            BasicText(if (full) "Hard is off by default: pressed after forgetting, it skews the schedule."
                      else "You are in Simple detail, so up and down do nothing.",
                style = kBody(13, color = Ink.muted), modifier = Modifier.padding(top = 4.dp))
        }
        ReachToggle("Tap the card to show the answer", touch.tapToReveal, onChange = touch::updateTap)
        ReachToggle("Haptic tick at the grading point", touch.haptics, onChange = touch::updateHaptics)
    }
}
