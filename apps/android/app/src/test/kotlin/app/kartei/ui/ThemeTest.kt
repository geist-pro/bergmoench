// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import app.kartei.KeyValue
import app.kartei.ThemePrefs
import app.kartei.reach.Snapshot
import java.io.File
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.pow

/** Just enough JSON for core/themes.json (objects, arrays, strings, numbers, booleans). */
private class MiniJson(private val s: String) {
    private var i = 0
    fun parse(): Any? { val v = value(); ws(); check(i == s.length) { "trailing data at $i" }; return v }
    private fun ws() { while (i < s.length && s[i].isWhitespace()) i++ }
    private fun value(): Any? {
        ws()
        return when (s[i]) {
            '{' -> { i++; val m = linkedMapOf<String, Any?>(); ws()
                if (s[i] == '}') { i++; return m }
                while (true) { ws(); val k = string(); ws(); check(s[i++] == ':'); m[k] = value(); ws()
                    if (s[i] == ',') i++ else { check(s[i++] == '}'); return m } } }
            '[' -> { i++; val l = mutableListOf<Any?>(); ws()
                if (s[i] == ']') { i++; return l }
                while (true) { l += value(); ws(); if (s[i] == ',') i++ else { check(s[i++] == ']'); return l } } }
            '"' -> string()
            't' -> { i += 4; true }
            'f' -> { i += 5; false }
            'n' -> { i += 4; null }
            else -> { val st = i; while (i < s.length && (s[i].isDigit() || s[i] in "+-.eE")) i++; s.substring(st, i).toDouble() }
        }
    }
    private fun string(): String {
        check(s[i++] == '"'); val b = StringBuilder()
        while (s[i] != '"') { if (s[i] == '\\') { i++; b.append(if (s[i] == 'n') '\n' else s[i]) } else b.append(s[i]); i++ }
        i++; return b.toString()
    }
}

@Suppress("UNCHECKED_CAST")
private object ThemesJson {
    // Unit tests run with the module directory (apps/android/app) as the working directory.
    val root: Map<String, Any?> by lazy {
        val f = listOf("../../../core/themes.json", "../../core/themes.json").map(::File).first { it.exists() }
        MiniJson(f.readText()).parse() as Map<String, Any?>
    }
    fun palette(family: String, mode: String) = ((root["families"] as Map<String, Any?>)[family] as Map<String, Any?>)[mode] as Map<String, String>
    fun fonts(family: String) = ((root["families"] as Map<String, Any?>)[family] as Map<String, Any?>)["fonts"] as Map<String, String>
    fun hex(s: String): Long = 0xFF000000 or s.removePrefix("#").toLong(16)
}

private val all = listOf(
    Triple(Family.Gruvbox, false, "gruvbox light"), Triple(Family.Gruvbox, true, "gruvbox dark"),
    Triple(Family.Geist, false, "geist light"), Triple(Family.Geist, true, "geist dark"),
)

class ThemesJsonTest {
    @Test fun palettesEqualThemesJson() {
        for ((family, dark, _) in all) {
            val json = ThemesJson.palette(family.key, if (dark) "dark" else "light").mapValues { ThemesJson.hex(it.value) }
            val kotlin = Palettes.of(family, dark).roles()
            assertEquals("roles of ${family.key}", json.keys, kotlin.keys)
            for ((role, v) in json) assertEquals("${family.key} ${if (dark) "dark" else "light"} $role", "%08x".format(v), "%08x".format(kotlin[role]))
        }
    }

    @Test fun everyFamilyInJsonExistsInKotlin() {
        @Suppress("UNCHECKED_CAST") val families = (ThemesJson.root["families"] as Map<String, Any?>).keys
        assertEquals(families, Family.entries.map { it.key }.toSet())
    }

    @Test fun flagsEqualThemesJson() {
        @Suppress("UNCHECKED_CAST") val flags = (ThemesJson.root["flags"] as List<String>).map(ThemesJson::hex)
        assertEquals(flags, Palettes.flags)
    }

    @Test fun defaultsEqualThemesJson() {
        @Suppress("UNCHECKED_CAST") val d = ThemesJson.root["defaults"] as Map<String, String>
        assertEquals(d["family"], ThemePrefs.DEFAULT_FAMILY.key)
        assertEquals(d["mode"], ThemePrefs.DEFAULT_MODE.key)
    }

    @Test fun cardPageUsesTheFamilysFonts() {
        for (f in Family.entries) {
            val html = CardPage.html("Q", null, "", Palettes.of(f, true), f, true)
            val fonts = ThemesJson.fonts(f.key)
            assertTrue("${f.key} display", "font-family:\"${fonts["display"]}\"" in html)
            assertTrue("${f.key} body", "font-family:\"${fonts["body"]}\"" in html)
        }
    }
}

/** WCAG 2.x contrast over all four palettes. A failure here means the palette needs a design decision, not a quiet tweak. */
class ContrastTest {
    private fun lum(c: Long): Double {
        fun ch(v: Long): Double { val x = v / 255.0; return if (x <= 0.03928) x / 12.92 else ((x + 0.055) / 1.055).pow(2.4) }
        return 0.2126 * ch((c shr 16) and 0xFF) + 0.7152 * ch((c shr 8) and 0xFF) + 0.0722 * ch(c and 0xFF)
    }
    private fun ratio(a: Long, b: Long): Double { val x = lum(a); val y = lum(b); return (maxOf(x, y) + 0.05) / (minOf(x, y) + 0.05) }

    @Test fun allPairsMeetTheirMinimum() {
        val failures = mutableListOf<String>()
        for ((family, dark, name) in all) {
            val p = Palettes.of(family, dark)
            val pairs = listOf(
                Triple("text/bg", p.text to p.bg, 4.5), Triple("text/surface", p.text to p.surface, 4.5),
                Triple("muted/bg", p.muted to p.bg, 4.5), Triple("muted/surface", p.muted to p.surface, 4.5),
                Triple("new/bg", p.new to p.bg, 4.5), Triple("learning/bg", p.learning to p.bg, 4.5),
                Triple("onAccent/accent", p.onAccent to p.accent, 4.5), Triple("onForgot/forgot", p.onForgot to p.forgot, 4.5),
                Triple("display/bg", p.display to p.bg, 3.0),
                // Lines that are the only sign of a control or a state (WCAG 1.4.11).
                Triple("control/bg", p.control to p.bg, 3.0), Triple("accentRule/bg", p.accentRule to p.bg, 3.0),
            )
            for ((label, c, min) in pairs) {
                val r = ratio(c.first, c.second)
                if (r < min) failures += "$name $label %.2f < $min".format(r)
            }
        }
        assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    @Test fun strongContrastKeepsTextAndRaisesLines() {
        for ((family, dark, name) in all) {
            val p = Palettes.of(family, dark); val s = p.strongContrast()
            assertEquals("$name rule", p.control, s.rule)
            assertEquals("$name control", p.muted, s.control)
            assertTrue("$name muted", ratio(s.muted, p.bg) > ratio(p.muted, p.bg))
            assertTrue("$name divider", ratio(s.rule, p.bg) >= 3.0)
            assertTrue("$name outline", ratio(s.control, p.bg) >= 4.5)
            assertEquals("$name everything else", p, s.copy(muted = p.muted, rule = p.rule, control = p.control))
        }
    }

    @Test fun strongContrastMutedIsHalfwayToText() {
        // GEIST dark: muted #aab7d2, text #f4f7fb.
        assertEquals("ffcfd7e7", "%08x".format(Palettes.geistDark.strongContrast().muted))
    }

    @Test fun ratioMatchesKnownValues() {
        assertEquals(21.0, ratio(0xFF000000, 0xFFFFFFFF), 0.01)
        assertEquals(1.0, ratio(0xFF777777, 0xFF777777), 0.001)
    }
}

class ThemePrefsTest {
    private class MapStore(val map: MutableMap<String, String> = mutableMapOf()) : KeyValue {
        override fun get(key: String) = map[key]
        override fun put(key: String, value: String) { map[key] = value }
    }

    @Test fun firstLaunchIsGeistDark() {
        val p = ThemePrefs(MapStore())
        assertEquals(Family.Geist, p.family)
        assertEquals(Mode.Dark, p.mode)
        assertEquals(Palettes.geistDark, p.palette(systemDark = false))
    }

    @Test fun choicesPersistAcrossInstances() {
        val store = MapStore()
        ThemePrefs(store).apply { updateFamily(Family.Gruvbox); updateMode(Mode.Light) }
        assertEquals(mapOf("family" to "gruvbox", "mode" to "light"), store.map)
        val again = ThemePrefs(store)
        assertEquals(Family.Gruvbox, again.family)
        assertEquals(Mode.Light, again.mode)
        again.updateMode(Mode.System)
        assertEquals(Mode.System, ThemePrefs(store).mode)
    }

    @Test fun unknownStoredValuesFallBackToDefaults() {
        val p = ThemePrefs(MapStore(mutableMapOf("family" to "solarized", "mode" to "sepia")))
        assertEquals(Family.Geist, p.family)
        assertEquals(Mode.Dark, p.mode)
    }

    @Test fun modeResolution() {
        val expected = mapOf(
            (Mode.System to false) to false, (Mode.System to true) to true,
            (Mode.Light to false) to false, (Mode.Light to true) to false,
            (Mode.Dark to false) to true, (Mode.Dark to true) to true,
        )
        for ((k, dark) in expected) {
            val (mode, system) = k
            assertEquals("$mode, system dark $system", dark, mode.isDark(system))
            val p = ThemePrefs(MapStore()).apply { updateFamily(Family.Gruvbox); updateMode(mode) }
            assertEquals("$mode, system dark $system", if (dark) Palettes.gruvboxDark else Palettes.gruvboxLight, p.palette(system))
        }
    }
}

class CardPageThemeTest {
    @Test fun pageCarriesEveryRoleAsACustomProperty() {
        for ((family, dark, name) in all) {
            val p = Palettes.of(family, dark)
            val html = CardPage.html("<b>Q</b>", "A", ".card{color:black}", p, family, dark)
            for ((role, c) in p.roles()) assertTrue("$name --k-${CardPage.cssName(role)}", "--k-${CardPage.cssName(role)}:#%06x".format(c and 0xFFFFFF) in html)
            assertTrue("$name color-scheme", "color-scheme:${if (dark) "dark" else "light"}" in html)
            assertEquals("$name nightMode class", dark, "nightMode" in html)
            assertTrue("$name highlight border", "--highlight-shape-border:3px #%06x".format(p.accent and 0xFFFFFF) in html)
        }
    }

    @Test fun injectedCssUsesTheProperties() {
        val html = CardPage.html("Q", "A", "", Palettes.gruvboxLight, Family.Gruvbox, false)
        assertTrue("body.card{background:transparent!important;color:var(--k-text)!important" in html)
        assertTrue(".k-typed .typeBad{color:var(--k-text);background:var(--k-forgot-soft)}" in html)
        assertTrue("--k-forgot-soft:rgba(157,0,6,0.18)" in html)
        // No Gruvbox-dark literals left in the light page (#ebdbb2 is skipped: it is also light surface2).
        for (lit in listOf("#504945", "#a89984", "#fabd2f", "#fb4934")) assertFalse(lit, lit in html)
    }

    @Test fun pageExposesTheControlColour() {
        val html = CardPage.html("Q", "A", "", Palettes.geistDark, Family.Geist, true)
        assertTrue("--k-control:#5a6ea6" in html)
        assertTrue(".k-play{border-color:var(--k-control)" in html)
        // Stronger contrast reaches the page through the same properties.
        val strong = CardPage.html("Q", "A", "", Palettes.geistDark.strongContrast(), Family.Geist, true)
        assertTrue("--k-rule:#5a6ea6" in strong); assertTrue("--k-control:#aab7d2" in strong); assertTrue("--k-muted:#cfd7e7" in strong)
    }

    @Test fun langGoesOnTheRootElement() {
        val p = Palettes.geistDark
        assertTrue("<html lang=\"de\">" in CardPage.html("Q", null, "", p, Family.Geist, true, lang = "de"))
        assertTrue("<html>" in CardPage.html("Q", null, "", p, Family.Geist, true))
        // Only letters, digits and hyphens get through.
        assertTrue("<html lang=\"en-GB\">" in CardPage.html("Q", null, "", p, Family.Geist, true, lang = "en-GB"))
        assertTrue("<html lang=\"enonloadx\">" in CardPage.html("Q", null, "", p, Family.Geist, true, lang = "en\" onload=\"x"))
        assertTrue("<html>" in CardPage.html("Q", null, "", p, Family.Geist, true, lang = "\""))
    }

    @Test fun questionWeightFollowsTheReadingSetting() {
        val p = Palettes.geistDark
        assertTrue(".k-q{font:200 36px" in CardPage.html("Q", null, "", p, Family.Geist, true))
        assertTrue(".k-q{font:400 36px" in CardPage.html("Q", null, "", p, Family.Geist, true, regularQuestions = true))
    }

    @Test fun cssNames() {
        assertEquals("on-accent", CardPage.cssName("onAccent"))
        assertEquals("accent-rule", CardPage.cssName("accentRule"))
        assertEquals("surface2", CardPage.cssName("surface2"))
    }

    @Test fun differentPalettesGiveDifferentPagesSoTheWebViewReloads() {
        val a = CardPage.html("Q", null, "", Palettes.geistDark, Family.Geist, true)
        val b = CardPage.html("Q", null, "", Palettes.geistLight, Family.Geist, false)
        assertFalse(a == b)
    }
}

class SnapshotFamilyTest {
    private val day = LocalDate.of(2026, 11, 14)

    @Test fun familyRoundTrips() {
        val s = Snapshot(day, 3, 1, 8.0, setOf(day), listOf(2), family = "gruvbox")
        assertEquals("gruvbox", Snapshot.decode(s.encode())?.family)
    }

    @Test fun oldSnapshotWithoutFamilyStillReads() {
        val old = "kartei-snapshot 1\nday=${day.toEpochDay()}\ncards=4\nminutes=1\nspc=8.0\nstudied=\nforecast=1,2\n"
        val s = Snapshot.decode(old)
        assertNotNull(s)
        assertEquals(4, s!!.cards)
        assertNull(s.family)
        assertEquals(Family.Geist, Family.of(s.family) ?: ThemePrefs.DEFAULT_FAMILY)
    }
}
