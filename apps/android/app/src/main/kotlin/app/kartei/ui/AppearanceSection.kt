// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.graphics.drawable.toBitmap
import app.kartei.AppIcon
import app.kartei.AppIconSwitch
import app.kartei.R
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kartei.DeckStore
import app.kartei.Reach
import app.kartei.ThemePrefs

/**
 * Look (Gruvbox or GEIST) and mode (match system, light, dark), stored on this device only.
 * Each look is previewed as a small card in its own colours and its own display face, in the mode that is active now,
 * so the choice is made by sight rather than by name. Mode cells carry a swatch of that mode's page colour.
 */
@Composable
fun AppearanceSection(store: DeckStore, theme: ThemePrefs) {
    val systemDark = isSystemInDarkTheme()
    val dark = theme.isDark(systemDark)
    KSectionHead("Appearance")
    BasicText("Look", style = kBody(13, 500, Ink.muted), modifier = Modifier.padding(top = 4.dp, bottom = 8.dp))
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        for (f in Family.entries) {
            LookTile(f, Palettes.of(f, dark), on = theme.family == f, modifier = Modifier.weight(1f)) {
                if (theme.family != f) { theme.updateFamily(f); Reach.storeDidUpdate(store) }
            }
        }
    }
    BasicText("Mode", style = kBody(13, 500, Ink.muted), modifier = Modifier.padding(top = 16.dp, bottom = 8.dp))
    Row(Modifier.fillMaxWidth().border(1.dp, Ink.control).height(IntrinsicSize.Min)) {
        Mode.entries.forEachIndexed { i, m ->
            if (i > 0) Box(Modifier.width(1.dp).fillMaxHeight().background(Ink.control))
            ModeCell(m, theme.family, on = theme.mode == m, modifier = Modifier.weight(1f).fillMaxHeight()) { theme.updateMode(m) }
        }
    }
    AppIconRow()
    KCaption(
        if (theme.mode == Mode.System) "Follows the phone, now ${if (systemDark) "dark" else "light"}. Saved on this phone only."
        else "Saved on this phone only.",
        Modifier.padding(top = 8.dp, bottom = 4.dp),
    )
}

/** A thumbnail card drawn in [p]: a heading in the look's display face, a line of body text, the accent and state colours. */
@Composable
private fun LookTile(family: Family, p: Palette, on: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(4.dp)
    Column(
        modifier.semantics { selected = on; contentDescription = "${family.label} look" + if (on) ", chosen" else "" }
            .clickable(role = Role.RadioButton, onClick = onClick)
            .border(if (on) 2.dp else 1.dp, if (on) Ink.text else Ink.control, shape).padding(if (on) 4.dp else 5.dp),
    ) {
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(2.dp)).background(Color(p.bg)).padding(horizontal = 12.dp, vertical = 10.dp)) {
            BasicText("12", style = TextStyle(fontFamily = Type.display(family), fontSize = 34.sp, fontWeight = FontWeight(800), color = Color(p.display), letterSpacing = (-1).sp))
            BasicText("min today", style = TextStyle(fontFamily = Type.body(family), fontSize = 13.sp, color = Color(p.muted)))
            Box(Modifier.padding(top = 8.dp).fillMaxWidth().height(2.dp).background(Color(p.accentRule)))
            Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(28.dp).height(12.dp).background(Color(p.accent), RoundedCornerShape(1.dp)))
                Dot(Color(p.new)); Dot(Color(p.learning)); Dot(Color(p.forgot))
            }
        }
        Row(Modifier.padding(start = 4.dp, top = 8.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
            Radio(on)
            BasicText(family.label, style = kBody(15, if (on) 700 else 500), modifier = Modifier.padding(start = 8.dp))
        }
    }
}

@Composable private fun Dot(c: Color) = Box(Modifier.size(10.dp).background(c, CircleShape))

@Composable
private fun Radio(on: Boolean) {
    Box(Modifier.size(16.dp).border(2.dp, if (on) Ink.text else Ink.muted, CircleShape), contentAlignment = Alignment.Center) {
        if (on) Box(Modifier.size(6.dp).background(Ink.text, CircleShape))
    }
}

/** One segment: a round swatch of the mode's page colour (half light, half dark for "Match system") and the label. */
@Composable
private fun ModeCell(mode: Mode, family: Family, on: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val light = Palettes.of(family, false); val darkP = Palettes.of(family, true)
    Box(
        modifier.heightIn(min = 52.dp).semantics { selected = on }
            .clickable(role = Role.RadioButton, onClick = onClick)
            .then(if (on) Modifier.background(Ink.surface2) else Modifier).padding(horizontal = 4.dp, vertical = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Canvas(Modifier.size(14.dp)) {
                val r = size.minDimension / 2; val c = Offset(size.width / 2, size.height / 2)
                when (mode) {
                    Mode.Light -> drawCircle(Color(light.bg), r, c)
                    Mode.Dark -> drawCircle(Color(darkP.bg), r, c)
                    Mode.System -> {
                        drawCircle(Color(light.bg), r, c)
                        val half = Path().apply { moveTo(size.width, 0f); lineTo(size.width, size.height); lineTo(0f, size.height); close() }
                        clipPath(half) { drawCircle(Color(darkP.bg), r, c) }
                    }
                }
                drawCircle(Ink.muted, r, c, style = androidx.compose.ui.graphics.drawscope.Stroke(1.dp.toPx()))
            }
            Spacer(Modifier.width(8.dp))
            BasicText(mode.label, style = kBody(14, if (on) 700 else 500, if (on) Ink.text else Ink.muted))
        }
    }
}

/** "App icon": GEIST (default) or Gruvbox launcher icon, previewed from the real adaptive icons. */
@Composable
private fun AppIconRow() {
    val context = LocalContext.current
    var current by remember { mutableStateOf(AppIconSwitch.current(context)) }
    BasicText("App icon", style = kBody(13, 500, Ink.muted), modifier = Modifier.padding(top = 16.dp, bottom = 8.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        for (icon in AppIcon.entries) {
            val on = icon == current
            val res = if (icon == AppIcon.Geist) R.mipmap.ic_launcher else R.mipmap.ic_launcher_gruvbox
            val preview = remember(res) { context.getDrawable(res)!!.toBitmap(144, 144).asImageBitmap() }
            Column(
                Modifier.border(2.dp, if (on) Ink.text else Color.Transparent, RoundedCornerShape(18.dp))
                    .clickable(role = Role.Button, onClickLabel = "Use the ${icon.label} app icon") {
                        if (!on) { AppIconSwitch.apply(context, icon); current = icon }
                    }
                    .padding(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Image(preview, contentDescription = "${icon.label} app icon" + if (on) ", selected" else "",
                    modifier = Modifier.size(56.dp).clip(CircleShape))
                BasicText(icon.label, style = kBody(14, if (on) 700 else 500, if (on) Ink.text else Ink.muted), modifier = Modifier.padding(top = 6.dp))
            }
        }
    }
}
