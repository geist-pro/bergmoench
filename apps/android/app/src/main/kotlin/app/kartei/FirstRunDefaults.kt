// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import app.kartei.core.Backend
import app.kartei.core.configJson
import app.kartei.core.setConfigJson

/** One-time defaults for collections that never went through onboarding (docs/science-defaults.md). */
object FirstRunDefaults {
    const val FSRS_KEY = "kartei.fsrsDefaulted"

    /**
     * Turn FSRS on once, through Anki's deck-options save so existing review history gets memory states.
     * After that the person's own choice stands: switching it off in Pace is never undone.
     */
    fun enableFsrsOnce(backend: Backend) {
        if (backend.configJson(FSRS_KEY) == "true") return
        try {
            val update = backend.configsFor(1)
            if (!update.fsrs) {
                val config = update.allConfigList.firstOrNull { it.config.id == update.currentDeck.configId }?.config ?: update.defaults
                backend.savePreset(1, config, fsrs = true)
            }
        } catch (_: Throwable) {
        } finally {
            backend.setConfigJson(FSRS_KEY, "true")
        }
    }
}
