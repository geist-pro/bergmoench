// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import app.kartei.ui.Palettes
import app.kartei.ui.ThemeState
import app.kartei.ui.deckCountParts
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadingPrefsTest {
    private class MapStore(val map: MutableMap<String, String> = mutableMapOf()) : KeyValue {
        override fun get(key: String) = map[key]
        override fun put(key: String, value: String) { map[key] = value }
    }

    // ReadingPrefs sets the app-wide contrast switch; leave it off for the other tests.
    @After fun reset() { ThemeState.strongContrast = false }

    @Test fun defaults() {
        val r = ReadingPrefs(MapStore())
        assertEquals(1, r.cardStep); assertEquals(1.0f, r.cardScale)
        assertFalse(r.regularQuestions); assertFalse(r.strongContrast); assertTrue(r.labelColours)
    }

    @Test fun stepsMapToScales() {
        assertEquals(listOf(0.85f, 1.0f, 1.15f, 1.3f, 1.5f), (0..4).map(ReadingPrefs::scaleFor))
        assertEquals(1.0f, ReadingPrefs.scaleFor(-1)); assertEquals(1.0f, ReadingPrefs.scaleFor(5))
    }

    @Test fun textZoomIsFontScaleTimesCardScale() {
        assertEquals(100, ReadingPrefs.textZoom(1f, 1))
        assertEquals(85, ReadingPrefs.textZoom(1f, 0))
        assertEquals(169, ReadingPrefs.textZoom(1.3f, 3))  // 1.3 × 1.3
        assertEquals(300, ReadingPrefs.textZoom(2f, 4))
    }

    @Test fun choicesPersistUnderTheirKeys() {
        val store = MapStore()
        ReadingPrefs(store).apply { updateCardStep(3); updateRegularQuestions(true); updateStrongContrast(true); updateLabelColours(false) }
        assertEquals(mapOf("kartei.reading.cardScale" to "3", "kartei.reading.regularQuestions" to "true",
            "kartei.reading.strongContrast" to "true", "kartei.reading.labelColours" to "false"), store.map)
        val again = ReadingPrefs(store)
        assertEquals(1.3f, again.cardScale); assertTrue(again.regularQuestions); assertTrue(again.strongContrast); assertFalse(again.labelColours)
    }

    @Test fun badStoredValuesFallBack() {
        val r = ReadingPrefs(MapStore(mutableMapOf("kartei.reading.cardScale" to "9", "kartei.reading.labelColours" to "maybe")))
        assertEquals(1, r.cardStep); assertTrue(r.labelColours)
        r.updateCardStep(7); assertEquals(4, r.cardStep)
    }

    @Test fun strongContrastSwitchesTheActivePalette() {
        val r = ReadingPrefs(MapStore())
        val plain = Palettes.of(ThemeState.family, ThemeState.dark)
        assertEquals(plain, ThemeState.palette)
        r.updateStrongContrast(true)
        assertEquals(plain.strongContrast(), ThemeState.palette)
        r.updateStrongContrast(false)
        assertEquals(plain, ThemeState.palette)
    }
}

class DeckLanguageTest {
    @Test fun coursesKnowTheirLanguage() {
        assertEquals("de", CourseCatalogue.gdp.lang)
        for (c in CourseCatalogue.all - CourseCatalogue.gdp) assertEquals(c.id, "en", c.lang)
    }

    @Test fun topLevelAncestor() {
        val rows = listOf(DeckRow(1, "GdP", 0, 0, 0, 0), DeckRow(2, "VL 01", 1, 0, 0, 0), DeckRow(3, "Teil a", 2, 0, 0, 0),
            DeckRow(4, "CoopSys", 0, 0, 0, 0), DeckRow(5, "VL 01", 1, 0, 0, 0))
        assertEquals(1L, DeckRows.topLevel(rows, 1)); assertEquals(1L, DeckRows.topLevel(rows, 3))
        assertEquals(4L, DeckRows.topLevel(rows, 5))
        assertNull(DeckRows.topLevel(rows, 99))
    }

    @Test fun stackedDeckRowDropsZeroCounts() {
        assertEquals(listOf(10 to "new", 2 to "learn", 31 to "due"), deckCountParts(10, 2, 31))
        assertEquals(listOf(98 to "due"), deckCountParts(0, 0, 98))
        assertTrue(deckCountParts(0, 0, 0).isEmpty())
    }
}
