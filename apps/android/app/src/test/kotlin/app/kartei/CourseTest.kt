// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import app.kartei.ui.CardPage
import app.kartei.ui.Family
import app.kartei.ui.FirstSessionCoach
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CourseTest {
    @Test fun typedOutputJoinsLinesLikeAnki() {
        assertEquals("0.0 5", TypedText.forComparison("0.0\n5"))
        assertEquals("0.0 5", TypedText.forComparison("0.0  \r\n5\n\n"))
        assertEquals("Hallo", TypedText.forComparison("Hallo"))
    }

    @Test fun catalogueMatchesTheAppleApp() {
        assertEquals(listOf("gdp", "gdp-en", "coopsys"), CourseCatalogue.all.map { it.id })
        assertEquals("tag:bergmoench::first \"deck:Cooperation Systems WS26/27\"", CourseCatalogue.firstSearch(CourseCatalogue.coopsys))
        assertNull(CourseCatalogue.firstSessionCourse(emptyList()))
        assertEquals("gdp", CourseCatalogue.firstSessionCourse(listOf(CourseCatalogue.coopsys, CourseCatalogue.gdp))?.id)
    }

    @Test fun courseAssetsExistInTheSourceTree() {
        for (course in CourseCatalogue.all) for (asset in course.assets) {
            assertTrue(asset, java.io.File("src/main/assets/$asset").exists())
        }
    }

    @Test fun codeFontPerFamily() {
        assertEquals("Courier Prime", CardPage.codeFont(Family.Geist))
        assertEquals("DM Mono", CardPage.codeFont(Family.Gruvbox))
    }

    @Test fun coachHasFiveLines() {
        for (i in 0..4) { assertNotNull(FirstSessionCoach.line(i, false, false)); assertNotNull(FirstSessionCoach.line(i, true, false)) }
        assertNull(FirstSessionCoach.line(5, false, false))
    }
}

class SwipeGradeTest {
    private val w = 1080f; private val h = 1500f; private val min = 240f

    @Test fun rightGoodLeftForgotPastAThird() {
        assertEquals(Rating.Good, SwipeGrade.release(400f, 10f, false, false, false, w, h, min))
        assertEquals(Rating.Forgot, SwipeGrade.release(-400f, 10f, false, false, false, w, h, min))
        assertNull(SwipeGrade.release(250f, 0f, false, false, false, w, h, min))
    }

    @Test fun verticalOnlyInFullWhenOn() {
        assertNull(SwipeGrade.release(5f, -400f, true, false, false, w, h, min))
        assertNull(SwipeGrade.release(5f, -400f, false, true, true, w, h, min))
        assertEquals(Rating.Easy, SwipeGrade.release(5f, -400f, true, true, false, w, h, min))
        assertEquals(Rating.Hard, SwipeGrade.release(5f, 400f, true, false, true, w, h, min))
    }

    @Test fun prefsDefaults() {
        val store = object : KeyValue { val m = mutableMapOf<String, String>(); override fun get(key: String) = m[key]; override fun put(key: String, value: String) { m[key] = value } }
        val t = TouchPrefs(store)
        assertTrue(t.swipeToGrade); assertTrue(!t.swipeEasy && !t.swipeHard); assertTrue(t.showHint)
        repeat(3) { t.hintSeen() }
        assertTrue(!t.showHint)
    }
}
