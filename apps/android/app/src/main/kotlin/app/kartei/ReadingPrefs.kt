// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.kartei.ui.ThemeState
import kotlin.math.roundToInt

/**
 * Reading settings, per device (as ThemePrefs and TouchPrefs): eyesight and screen differ between a phone and a tablet
 * that sync one collection. Card text size sits on top of the system font scale.
 */
class ReadingPrefs(private val store: KeyValue) {
    private fun flag(key: String, fallback: Boolean) = store.get(key)?.toBooleanStrictOrNull() ?: fallback

    /** Card text size as a step, 0..4 (see [SCALES]); 1 is the size the cards were designed at. */
    var cardStep by mutableStateOf(store.get(CARD_SCALE)?.toIntOrNull()?.takeIf { it in SCALES.indices } ?: DEFAULT_STEP); private set
    /** Questions in weight 400 instead of the thin display weight 200. */
    var regularQuestions by mutableStateOf(flag(REGULAR, false)); private set
    /** Brighter secondary text and visible dividers (Palette.strongContrast). */
    var strongContrast by mutableStateOf(flag(CONTRAST, false)); private set
    /** Names beside flags and queue counts, so colour is not the only cue. */
    var labelColours by mutableStateOf(flag(LABELS, true)); private set

    val cardScale: Float get() = scaleFor(cardStep)

    init { ThemeState.strongContrast = strongContrast }

    fun updateCardStep(step: Int) { cardStep = step.coerceIn(SCALES.indices); store.put(CARD_SCALE, cardStep.toString()) }
    fun updateRegularQuestions(on: Boolean) { regularQuestions = on; store.put(REGULAR, on.toString()) }
    fun updateStrongContrast(on: Boolean) { strongContrast = on; ThemeState.strongContrast = on; store.put(CONTRAST, on.toString()) }
    fun updateLabelColours(on: Boolean) { labelColours = on; store.put(LABELS, on.toString()) }

    companion object {
        val SCALES = listOf(0.85f, 1.0f, 1.15f, 1.3f, 1.5f)
        val STEP_NAMES = listOf("Small", "Default", "Large", "Larger", "Largest")
        const val DEFAULT_STEP = 1
        const val CARD_SCALE = "kartei.reading.cardScale"
        const val REGULAR = "kartei.reading.regularQuestions"
        const val CONTRAST = "kartei.reading.strongContrast"
        const val LABELS = "kartei.reading.labelColours"

        /** The multiplier for a step; anything outside 0..4 counts as the default. */
        fun scaleFor(step: Int): Float = SCALES.getOrElse(step) { SCALES[DEFAULT_STEP] }

        /** WebSettings.textZoom for the card page, in percent: system font scale times the card text step. */
        fun textZoom(fontScale: Float, step: Int): Int = (fontScale * scaleFor(step) * 100).roundToInt()

        @Volatile private var instance: ReadingPrefs? = null
        fun of(context: Context): ReadingPrefs = instance ?: synchronized(this) {
            instance ?: ReadingPrefs(ThemePrefs.sharedPrefs(context.applicationContext)).also { instance = it }
        }
    }
}
