// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.kartei.core.Backend
import app.kartei.core.configJson
import app.kartei.core.setConfigJson

/**
 * Kartei's own study settings, stored in the collection config. Defaults follow docs/science-defaults.md:
 * Simple (Forgot / Got it) for new users, since two and four buttons are equally accurate for FSRS.
 */
class StudyPrefs {
    enum class Detail { Simple, Full }

    var detail by mutableStateOf(Detail.Simple); private set
    var onboarded by mutableStateOf(true); private set
    var loaded by mutableStateOf(false); private set
    private var backend: Backend? = null

    fun load(backend: Backend) {
        this.backend = backend
        detail = if (backend.configJson(DETAIL_KEY)?.trim('"') == "full") Detail.Full else Detail.Simple
        onboarded = backend.configJson(ONBOARDED_KEY) == "true"
        loaded = true
    }

    fun updateDetail(d: Detail) { detail = d; backend?.setConfigJson(DETAIL_KEY, if (d == Detail.Full) "\"full\"" else "\"simple\"") }
    fun finishOnboarding() { onboarded = true; backend?.setConfigJson(ONBOARDED_KEY, "true") }

    companion object {
        const val DETAIL_KEY = "kartei.detail"
        const val ONBOARDED_KEY = "kartei.onboarded"
    }
}
