// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import app.kartei.ui.examCountdown
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CountdownTest {
    private fun day(offset: Long) = LocalDate.now().plusDays(offset)

    @Test fun wording() {
        assertNull(examCountdown(null))
        assertNull(examCountdown(day(-1)))
        assertEquals("exam today", examCountdown(day(0)))
        assertEquals("exam tomorrow", examCountdown(day(1)))
        assertEquals("exam in 9 days", examCountdown(day(9)))
        assertEquals("exam in 2 weeks", examCountdown(day(14)))
        assertEquals("exam in 12 weeks", examCountdown(day(90)))
    }
}
