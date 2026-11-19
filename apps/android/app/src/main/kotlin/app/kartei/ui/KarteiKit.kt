// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
// Small building blocks shared by Browse, Stats, Pace, Study and onboarding, in the house style (BasicText, no Material).
package app.kartei.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

/** Anki's seven flags in order; "Teal" is Anki's turquoise, shortened so the name fits its cell. */
internal val KFlagNames = listOf("Red", "Orange", "Green", "Blue", "Pink", "Teal", "Purple")

/** From this system font scale on, tight rows reflow: the rating bar becomes a grid, deck counts become a line. */
internal const val K_LARGE_TEXT = 1.3f

@Composable internal fun kLargeText(): Boolean = LocalDensity.current.fontScale >= K_LARGE_TEXT

internal fun kBody(size: Int, weight: Int = 400, color: Color = Ink.text) =
    TextStyle(fontFamily = Type.body, fontSize = size.sp, fontWeight = FontWeight(weight), color = color, fontFeatureSettings = "tnum")

internal fun kDisplay(size: Int, heavy: Boolean, color: Color = Ink.text) =
    TextStyle(fontFamily = Type.display, fontSize = size.sp, fontWeight = FontWeight(if (heavy) 800 else 200), color = color, letterSpacing = (-0.02 * size).sp)

@Composable internal fun KRule(modifier: Modifier = Modifier) = Box(modifier.fillMaxWidth().height(1.dp).background(Ink.rule))

@Composable internal fun KTitle(text: String) =
    BasicText(text, style = kDisplay(34, true, Ink.display), modifier = Modifier.padding(top = 12.dp, bottom = 12.dp))

@Composable internal fun KCaption(text: String, modifier: Modifier = Modifier) = BasicText(text, style = kBody(13, color = Ink.muted), modifier = modifier)

/** Label on the left, value on the right, a hairline below: the "facts" list from the mockups. */
@Composable
internal fun KFact(label: String, value: String, modifier: Modifier = Modifier, sub: String? = null, onClick: (() -> Unit)? = null) {
    val click = if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier
    Column(modifier.then(click).semantics(mergeDescendants = true) {}) {
        Row(Modifier.heightIn(min = 48.dp).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                BasicText(label, style = kBody(16))
                sub?.let { BasicText(it, style = kBody(13, color = Ink.muted)) }
            }
            BasicText(value, style = kBody(16, if (onClick != null) 400 else 700, if (onClick != null) Ink.muted else Ink.text).copy(textAlign = TextAlign.End),
                modifier = Modifier.padding(start = 12.dp))
            if (onClick != null) KChevron(Modifier.padding(start = 8.dp))
        }
        KRule()
    }
}

@Composable
internal fun KChevron(modifier: Modifier = Modifier, back: Boolean = false, color: Color = Ink.muted) {
    Canvas(modifier.size(12.dp)) {
        val a = if (back) size.width * 0.75f else size.width * 0.25f
        val b = if (back) size.width * 0.25f else size.width * 0.75f
        drawLine(color, Offset(a, 0f), Offset(b, size.height / 2), 1.5.dp.toPx(), StrokeCap.Round)
        drawLine(color, Offset(b, size.height / 2), Offset(a, size.height), 1.5.dp.toPx(), StrokeCap.Round)
    }
}

/** Back arrow, title, optional trailing action: the nav row from pace.html and info.html. */
@Composable
internal fun KNavBar(title: String, back: () -> Unit, trailing: String? = null, onTrailing: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(48.dp).clickable(role = Role.Button, onClick = back).semantics { contentDescription = "Back" }, contentAlignment = Alignment.Center) {
            KChevron(Modifier.size(16.dp), back = true, color = Ink.text)
        }
        BasicText(title, style = kBody(17, 500), modifier = Modifier.weight(1f).padding(start = 4.dp, top = 6.dp, bottom = 6.dp))
        if (trailing != null && onTrailing != null) {
            Box(Modifier.heightIn(min = 48.dp).clickable(role = Role.Button, onClick = onTrailing).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                BasicText(trailing, style = kBody(16, 700))
            }
        }
    }
}

/** − value + with 48 dp targets. */
@Composable
internal fun KStepper(value: Int, range: IntRange, step: Int = 1, label: String, onChange: (Int) -> Unit) {
    // Cells have minimum sizes only, so the stepper grows with the font scale; the outline is the control colour.
    Row(Modifier.border(1.dp, Ink.control).height(IntrinsicSize.Min).semantics(mergeDescendants = false) {}, verticalAlignment = Alignment.CenterVertically) {
        val minus = value - step >= range.first; val plus = value + step <= range.last
        val cell = Modifier.widthIn(min = 48.dp).heightIn(min = 48.dp).fillMaxHeight()
        Box(cell.clickable(enabled = minus, role = Role.Button) { onChange(value - step) }.semantics { contentDescription = "Fewer $label" }, contentAlignment = Alignment.Center) {
            BasicText("−", style = kBody(20, 500, if (minus) Ink.text else Ink.rule))
        }
        Box(Modifier.width(1.dp).fillMaxHeight().background(Ink.control))
        Box(Modifier.widthIn(min = 56.dp).heightIn(min = 48.dp).padding(horizontal = 4.dp).semantics { contentDescription = "$value $label" }, contentAlignment = Alignment.Center) {
            BasicText("$value", style = kBody(20, 700))
        }
        Box(Modifier.width(1.dp).fillMaxHeight().background(Ink.control))
        Box(cell.clickable(enabled = plus, role = Role.Button) { onChange(value + step) }.semantics { contentDescription = "More $label" }, contentAlignment = Alignment.Center) {
            BasicText("+", style = kBody(20, 500, if (plus) Ink.text else Ink.rule))
        }
    }
}

/**
 * Whole-number slider drawn like pace.html: a hairline track, a filled part, a ring knob. Drag or tap; TalkBack can set it
 * through setProgress and reads [describe]. [onDone] fires when a drag or tap ends, for saving.
 */
@Composable
internal fun KSlider(value: Int, range: IntRange, label: String, describe: (Int) -> String, onChange: (Int) -> Unit, onDone: (Int) -> Unit) {
    var width by remember { mutableIntStateOf(1) }
    val current by rememberUpdatedState(value)
    val change by rememberUpdatedState(onChange)
    val done by rememberUpdatedState(onDone)
    fun at(x: Float) = (range.first + (x / width).coerceIn(0f, 1f) * (range.last - range.first)).roundToInt()
    Box(
        Modifier.fillMaxWidth().height(48.dp).onSizeChanged { width = maxOf(1, it.width) }
            .semantics {
                contentDescription = label
                stateDescription = describe(value)
                progressBarRangeInfo = ProgressBarRangeInfo(value.toFloat(), range.first.toFloat()..range.last.toFloat(), range.last - range.first - 1)
                setProgress { v -> val n = v.roundToInt().coerceIn(range); change(n); done(n); true }
            }
            .pointerInput(range) { detectTapGestures { change(at(it.x)); done(at(it.x)) } }
            .pointerInput(range) { detectHorizontalDragGestures(onDragEnd = { done(current) }) { c, _ -> change(at(c.position.x)) } },
        contentAlignment = Alignment.CenterStart,
    ) {
        Canvas(Modifier.fillMaxWidth().height(48.dp)) {
            val f = (value - range.first).toFloat() / (range.last - range.first)
            val y = size.height / 2; val x = f * size.width; val r = 11.dp.toPx()
            drawLine(Ink.control, Offset(0f, y), Offset(size.width, y), 2.dp.toPx())
            drawLine(Ink.text, Offset(0f, y), Offset(x, y), 2.dp.toPx())
            drawCircle(Ink.bg, r, Offset(x.coerceIn(r, size.width - r), y))
            drawCircle(Ink.text, r, Offset(x.coerceIn(r, size.width - r), y), style = androidx.compose.ui.graphics.drawscope.Stroke(2.dp.toPx()))
        }
    }
}

/** Full-width button: filled accent for the main action, outlined otherwise. */
@Composable
internal fun KButton(text: String, modifier: Modifier = Modifier, trailing: String? = null, primary: Boolean = true, enabled: Boolean = true, onClick: () -> Unit) {
    val base = modifier.fillMaxWidth().heightIn(min = 56.dp)
    val look = if (primary) base.background(if (enabled) Ink.accent else Ink.surface2) else base.border(1.dp, Ink.control)
    val ink = if (primary && enabled) Ink.onAccent else if (enabled) Ink.text else Ink.muted
    Row(look.clickable(enabled = enabled, role = Role.Button, onClick = onClick).padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        BasicText(text, style = kDisplay(19, true, ink).copy(letterSpacing = 0.sp), modifier = Modifier.weight(1f))
        trailing?.let { BasicText(it, style = kBody(15, 500, ink)) }
    }
}

/** Underlined text action with a 48 dp target. */
@Composable
internal fun KLink(text: String, modifier: Modifier = Modifier, color: Color = Ink.text, onClick: () -> Unit) {
    Box(modifier.heightIn(min = 48.dp).widthIn(min = 48.dp).clickable(role = Role.Button, onClick = onClick), contentAlignment = Alignment.CenterStart) {
        BasicText(text, style = kBody(14, 500, color).copy(textDecoration = TextDecoration.Underline))
    }
}

/** A radio option with a title and one line of explanation (import.html). */
@Composable
internal fun KOption(title: String, detail: String, on: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp).border(1.dp, if (on) Ink.text else Ink.control)
            .semantics { selected = on }.clickable(role = Role.RadioButton, onClick = onClick).padding(16.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(Modifier.padding(top = 2.dp).size(18.dp).border(2.dp, if (on) Ink.text else Ink.muted, CircleShape), contentAlignment = Alignment.Center) {
            if (on) Box(Modifier.size(8.dp).background(Ink.text, CircleShape))
        }
        Column(Modifier.padding(start = 12.dp)) {
            BasicText(title, style = kBody(16, 700))
            BasicText(detail, style = kBody(14, color = Ink.muted))
        }
    }
}

/** A tick box with a title and one line of explanation, for choosing several things (the course picker). */
@Composable
internal fun KCheck(title: String, detail: String, on: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp).border(1.dp, if (on) Ink.accent else Ink.control)
            .semantics { selected = on }.clickable(role = Role.Checkbox, onClick = onClick).padding(16.dp),
        verticalAlignment = Alignment.Top,
    ) {
        // The tick is drawn, not set as text: a glyph would have to be under 13 sp to fit the box.
        val tick = Ink.onAccent
        Canvas(Modifier.padding(top = 2.dp).size(18.dp).background(if (on) Ink.accent else Ink.bg).border(2.dp, if (on) Ink.accent else Ink.muted)) {
            if (on) {
                val w = 2.dp.toPx()
                drawLine(tick, Offset(size.width * 0.26f, size.height * 0.52f), Offset(size.width * 0.43f, size.height * 0.7f), w, StrokeCap.Round)
                drawLine(tick, Offset(size.width * 0.43f, size.height * 0.7f), Offset(size.width * 0.75f, size.height * 0.3f), w, StrokeCap.Round)
            }
        }
        Column(Modifier.padding(start = 12.dp)) {
            BasicText(title, style = kBody(16, 700))
            BasicText(detail, style = kBody(14, color = Ink.muted))
        }
    }
}

/** Section heading inside Settings. */
@Composable
internal fun KSectionHead(title: String, trailing: String? = null) {
    Row(Modifier.fillMaxWidth().padding(top = 20.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        BasicText(title, style = kBody(17, 700), modifier = Modifier.weight(1f).semantics { heading() })
        trailing?.let { BasicText(it, style = kBody(13, color = Ink.muted)) }
    }
}

/**
 * The switch drawn beside a toggle row. Off is an outlined track with the knob on the left, on is a filled track with the
 * knob on the right, so the state shows by position and outline and not by colour alone. The row carries the semantics.
 */
@Composable
internal fun KSwitch(on: Boolean, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(13.dp)
    val track = if (on) Modifier.background(Ink.accent, shape) else Modifier.border(2.dp, Ink.control, shape)
    Box(modifier.width(44.dp).height(26.dp).then(track).padding(if (on) 3.dp else 5.dp), contentAlignment = if (on) Alignment.CenterEnd else Alignment.CenterStart) {
        Box(Modifier.size(if (on) 20.dp else 16.dp).background(if (on) Ink.onAccent else Ink.control, CircleShape))
    }
}

/**
 * A small flag (a pennant with a notch) in the colour of Anki flag [flag], 1..7. With 0 it is an outline in the control
 * colour, standing for "no flag". The shape says "flag" where the colour alone would not.
 */
@Composable
internal fun KFlagMark(flag: Int, modifier: Modifier = Modifier, width: Int = 12, height: Int = 14) {
    val colour = Ink.flags.getOrNull(flag - 1)
    val outline = Ink.control
    Canvas(modifier.size(width.dp, height.dp)) {
        val inset = if (colour == null) 0.5.dp.toPx() else 0f
        val path = Path().apply {
            moveTo(inset, inset); lineTo(size.width - inset, inset); lineTo(size.width * 0.7f, size.height / 2)
            lineTo(size.width - inset, size.height - inset); lineTo(inset, size.height - inset); close()
        }
        if (colour != null) drawPath(path, colour) else drawPath(path, outline, style = Stroke(1.dp.toPx()))
    }
}

/**
 * The flag chooser: the seven flags and "None" as labelled cells, each a flag mark in its colour with the flag's name,
 * 48 dp high at least. The chosen cell has a heavier outline and a bold name. [onFlag] gets 1..7, or 0 for None.
 * [columns] defaults to four, two at large font scales.
 */
@Composable
internal fun KFlagGrid(current: Int, modifier: Modifier = Modifier, columns: Int = if (kLargeText()) 2 else 4, onFlag: (Int) -> Unit) {
    val cells = (1..7).toList() + 0
    Column(modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for (line in cells.chunked(columns)) {
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (f in line) {
                    val on = current == f
                    val name = if (f == 0) "None" else KFlagNames[f - 1]
                    val shape = RoundedCornerShape(2.dp)
                    Row(
                        Modifier.weight(1f).fillMaxHeight().heightIn(min = 48.dp)
                            .border(if (on) 2.dp else 1.dp, if (on) Ink.text else Ink.control, shape)
                            .selectable(selected = on, role = Role.RadioButton) { onFlag(f) }
                            .semantics(mergeDescendants = true) { contentDescription = if (f == 0) "No flag" else "$name flag" }
                            .padding(horizontal = 6.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        if (f != 0) KFlagMark(f)
                        BasicText(name, style = kBody(13, if (on) 700 else 400, if (f == 0 && !on) Ink.muted else Ink.text), maxLines = 2)
                    }
                }
            }
        }
    }
}
