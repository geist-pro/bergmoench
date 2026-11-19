// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Touch controls, per device (as the Apple app's TouchPrefs): swipe to grade once the answer shows, right Got it (Good),
 * left Forgot (Again). Easy (up) and Hard (down) are opt-in and only in Full detail: Hard pressed after a lapse bends
 * the schedule (F3). Swipes before the answer do nothing, so recall comes first (F1).
 */
class TouchPrefs(private val store: KeyValue) {
    private fun flag(key: String, fallback: Boolean) = store.get(key)?.toBooleanStrictOrNull() ?: fallback

    var swipeToGrade by mutableStateOf(flag(SWIPE, true)); private set
    var swipeEasy by mutableStateOf(flag(EASY, false)); private set
    var swipeHard by mutableStateOf(flag(HARD, false)); private set
    var tapToReveal by mutableStateOf(flag(TAP, true)); private set
    var haptics by mutableStateOf(flag(HAPTICS, true)); private set
    var hintsShown by mutableStateOf(store.get(HINTS)?.toIntOrNull() ?: 0); private set

    fun updateSwipe(on: Boolean) { swipeToGrade = on; store.put(SWIPE, on.toString()) }
    fun updateEasy(on: Boolean) { swipeEasy = on; store.put(EASY, on.toString()) }
    fun updateHard(on: Boolean) { swipeHard = on; store.put(HARD, on.toString()) }
    fun updateTap(on: Boolean) { tapToReveal = on; store.put(TAP, on.toString()) }
    fun updateHaptics(on: Boolean) { haptics = on; store.put(HAPTICS, on.toString()) }
    fun hintSeen() { hintsShown += 1; store.put(HINTS, hintsShown.toString()) }

    val showHint get() = swipeToGrade && hintsShown < HINT_ANSWERS
    fun vertical(full: Boolean) = full && (swipeEasy || swipeHard)

    companion object {
        const val HINT_ANSWERS = 3
        private const val SWIPE = "touch.swipe"
        private const val EASY = "touch.easy"
        private const val HARD = "touch.hard"
        private const val TAP = "touch.tap"
        private const val HAPTICS = "touch.haptics"
        private const val HINTS = "touch.hints"

        @Volatile private var instance: TouchPrefs? = null
        fun of(context: Context): TouchPrefs = instance ?: synchronized(this) {
            instance ?: TouchPrefs(ThemePrefs.sharedPrefs(context.applicationContext)).also { instance = it }
        }
    }
}

/** Which grade a drag on the answer side points at, and whether it went far enough (same rules as the Apple app). */
object SwipeGrade {
    /** Horizontal swipes grade past a third of the card's width, vertical ones past a fifth of its height; at least [minPx]. */
    fun threshold(width: Float, height: Float, vertical: Boolean, minPx: Float): Float =
        if (vertical) max(minPx, height / 5) else max(minPx, width / 3)

    fun candidate(dx: Float, dy: Float, full: Boolean, easy: Boolean, hard: Boolean): Rating? {
        if (dx == 0f && dy == 0f) return null
        if (abs(dx) >= abs(dy)) return if (dx > 0) Rating.Good else Rating.Forgot
        if (!full) return null
        return if (dy < 0) (if (easy) Rating.Easy else null) else (if (hard) Rating.Hard else null)
    }

    fun progress(dx: Float, dy: Float, rating: Rating, width: Float, height: Float, minPx: Float): Float {
        val vertical = rating == Rating.Easy || rating == Rating.Hard
        return min(1f, abs(if (vertical) dy else dx) / threshold(width, height, vertical, minPx))
    }

    fun release(dx: Float, dy: Float, full: Boolean, easy: Boolean, hard: Boolean, width: Float, height: Float, minPx: Float): Rating? {
        val r = candidate(dx, dy, full, easy, hard) ?: return null
        return if (progress(dx, dy, r, width, height, minPx) >= 1f) r else null
    }

    fun label(r: Rating, simple: Boolean) = when (r) {
        Rating.Forgot -> "Forgot"
        Rating.Hard -> "Hard"
        Rating.Good -> if (simple) "Got it" else "Good"
        Rating.Easy -> "Easy"
    }
}
