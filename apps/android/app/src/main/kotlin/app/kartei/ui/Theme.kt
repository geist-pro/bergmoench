// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import app.kartei.R

/** The two looks from core/themes.json; [key] is the name used there and in preferences. */
enum class Family(val key: String, val label: String) {
    Gruvbox("gruvbox", "Gruvbox"), Geist("geist", "GEIST");
    companion object { fun of(key: String?) = entries.firstOrNull { it.key == key } }
}

/** How light or dark is chosen; [key] matches "defaults.mode" in core/themes.json. */
enum class Mode(val key: String, val label: String) {
    System("system", "Match system"), Light("light", "Light"), Dark("dark", "Dark");

    fun isDark(systemDark: Boolean) = when (this) { System -> systemDark; Light -> false; Dark -> true }

    companion object { fun of(key: String?) = entries.firstOrNull { it.key == key } }
}

/** One palette, colours as 0xAARRGGBB. Role names are the keys of core/themes.json. */
data class Palette(
    val bg: Long, val surface: Long, val surface2: Long, val rule: Long, val text: Long, val muted: Long, val display: Long,
    val accent: Long, val onAccent: Long, val accentRule: Long, val forgot: Long, val onForgot: Long, val new: Long, val learning: Long, val control: Long,
) {
    /** Role name to colour, in the order of core/themes.json; used by the card page and the tests. */
    fun roles(): Map<String, Long> = linkedMapOf(
        "bg" to bg, "surface" to surface, "surface2" to surface2, "rule" to rule, "text" to text, "muted" to muted, "display" to display,
        "accent" to accent, "onAccent" to onAccent, "accentRule" to accentRule, "forgot" to forgot, "onForgot" to onForgot,
        "new" to new, "learning" to learning, "control" to control,
    )

    /**
     * The "Stronger contrast" variant (Settings › Reading): muted text moves halfway to the text colour, dividers take the
     * control colour, and control outlines take what muted was. Hue and layout stay the same.
     */
    fun strongContrast(): Palette = copy(muted = mix(muted, text), rule = control, control = muted)

    private companion object {
        /** The colour halfway between [a] and [b], per channel. */
        fun mix(a: Long, b: Long): Long {
            fun ch(shift: Int) = ((((a shr shift) and 0xFF) + ((b shr shift) and 0xFF) + 1) / 2) shl shift
            return 0xFF000000 or ch(16) or ch(8) or ch(0)
        }
    }
}

/** Values copied from core/themes.json (ThemesJsonTest keeps them equal). */
object Palettes {
    val gruvboxDark = Palette(
        bg = 0xFF282828, surface = 0xFF32302F, surface2 = 0xFF3C3836, rule = 0xFF504945, text = 0xFFEBDBB2, muted = 0xFFA89984,
        display = 0xFFEBDBB2, accent = 0xFFFABD2F, onAccent = 0xFF1D2021, accentRule = 0xFFFABD2F, forgot = 0xFFFB6A57,
        onForgot = 0xFF1D2021, new = 0xFF83A598, learning = 0xFFFE8019, control = 0xFF928374,
    )
    val gruvboxLight = Palette(
        bg = 0xFFFBF1C7, surface = 0xFFF2E5BC, surface2 = 0xFFEBDBB2, rule = 0xFFD5C4A1, text = 0xFF282828, muted = 0xFF665C54,
        display = 0xFF282828, accent = 0xFF282828, onAccent = 0xFFFBF1C7, accentRule = 0xFFB57614, forgot = 0xFF9D0006,
        onForgot = 0xFFFBF1C7, new = 0xFF076678, learning = 0xFFAF3A03, control = 0xFF7C6F64,
    )
    val geistDark = Palette(
        bg = 0xFF0B1220, surface = 0xFF121B30, surface2 = 0xFF1A2540, rule = 0xFF26335A, text = 0xFFF4F7FB, muted = 0xFFAAB7D2,
        display = 0xFF8FB3F2, accent = 0xFF29B7EA, onAccent = 0xFF161616, accentRule = 0xFF29B7EA, forgot = 0xFFFF7A6B,
        onForgot = 0xFF161616, new = 0xFF6FCDF2, learning = 0xFFF2A865, control = 0xFF5A6EA6,
    )
    val geistLight = Palette(
        bg = 0xFFFFFFFF, surface = 0xFFF2F6FB, surface2 = 0xFFE4EBF5, rule = 0xFFD6DEEA, text = 0xFF161616, muted = 0xFF3A4A66,
        display = 0xFF193F82, accent = 0xFF193F82, onAccent = 0xFFFFFFFF, accentRule = 0xFF1687B5, forgot = 0xFFB42318,
        onForgot = 0xFFFFFFFF, new = 0xFF0A6E96, learning = 0xFFA14A00, control = 0xFF7F8EA9,
    )

    /** Anki's flag colours, the same in every theme. */
    val flags = listOf(0xFFE5484D, 0xFFF08C2E, 0xFF46A758, 0xFF3E8ED0, 0xFFD6409F, 0xFF12A594, 0xFF8E4EC6)

    fun of(family: Family, dark: Boolean) = when (family) {
        Family.Gruvbox -> if (dark) gruvboxDark else gruvboxLight
        Family.Geist -> if (dark) geistDark else geistLight
    }
}

/**
 * The active look, held in Compose state. MainActivity sets it from the preference and the system's dark mode;
 * every [Ink] and [Type] read goes through here, so changing it recomposes whatever drew with the old colours.
 */
object ThemeState {
    var family by mutableStateOf(Family.Geist); private set
    var dark by mutableStateOf(true); private set
    /** Settings › Reading › Stronger contrast; set by ReadingPrefs. */
    var strongContrast by mutableStateOf(false)
    val palette: Palette get() = Palettes.of(family, dark).let { if (strongContrast) it.strongContrast() else it }

    fun apply(family: Family, dark: Boolean) {
        if (this.family != family) this.family = family
        if (this.dark != dark) this.dark = dark
    }
}

/** Colour roles of the active palette (see core/themes.json). */
object Ink {
    private val p get() = ThemeState.palette
    val bg get() = Color(p.bg)
    val surface get() = Color(p.surface)
    val surface2 get() = Color(p.surface2)
    val rule get() = Color(p.rule)
    val text get() = Color(p.text)
    val muted get() = Color(p.muted)
    /** Big headings and numerals. */
    val display get() = Color(p.display)
    val accent get() = Color(p.accent)
    val onAccent get() = Color(p.onAccent)
    /** The 2 dp accent bars and the "today" outline; brighter than [accent] in the light themes. */
    val accentRule get() = Color(p.accentRule)
    val forgot get() = Color(p.forgot)
    val onForgot get() = Color(p.onForgot)
    val new get() = Color(p.new)
    val learning get() = Color(p.learning)
    /** Outlines and tracks of controls and states, 3:1 or more on bg; [rule] is for plain dividers. */
    val control get() = Color(p.control)
    val flags: List<Color> = Palettes.flags.map { Color(it) }
    /** Dims the screen under a sheet; black in every theme. */
    val scrim = Color(0x8C000000)
}

/**
 * Fonts per family. Gruvbox: Bricolage Grotesque (display 200/800) with DM Sans (body). GEIST: Nunito (display 200/800)
 * with Noto Serif (body) and Courier Prime (data). All but Courier Prime are variable fonts.
 */
@OptIn(ExperimentalTextApi::class)
object Type {
    private fun face(res: Int, weight: Int) =
        Font(res, FontWeight(weight), variationSettings = FontVariation.Settings(FontVariation.weight(weight)))

    private val bricolage = FontFamily(face(R.font.bricolage_grotesque, 200), face(R.font.bricolage_grotesque, 800))
    private val dmSans = FontFamily(face(R.font.dm_sans, 400), face(R.font.dm_sans, 500), face(R.font.dm_sans, 700))
    private val nunito = FontFamily(face(R.font.nunito, 200), face(R.font.nunito, 800))
    private val notoSerif = FontFamily(face(R.font.noto_serif, 400), face(R.font.noto_serif, 500), face(R.font.noto_serif, 700))
    private val courier = FontFamily(Font(R.font.courier_prime, FontWeight.Normal))

    fun display(family: Family) = if (family == Family.Geist) nunito else bricolage
    fun body(family: Family) = if (family == Family.Geist) notoSerif else dmSans

    val display: FontFamily get() = display(ThemeState.family)
    val body: FontFamily get() = body(ThemeState.family)
    /** Search syntax and other typed data: Courier Prime in GEIST. Gruvbox's DM Mono is not shipped, so Gruvbox keeps DM Sans there. */
    val data: FontFamily get() = if (ThemeState.family == Family.Geist) courier else dmSans
}
