// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Small building blocks shared by the Sync and Reminders sections (prefixed to stay clear of other files' helpers). */
internal fun reachText(size: Int, weight: Int = 400, color: Color = Ink.text) =
    TextStyle(fontFamily = Type.body, fontSize = size.sp, fontWeight = FontWeight(weight), color = color, lineHeight = (size * 1.4).sp)

@Composable
internal fun ReachHeading(title: String) {
    Column(Modifier.padding(top = 24.dp)) {
        BasicText(title, style = TextStyle(fontFamily = Type.display, fontSize = 22.sp, fontWeight = FontWeight(800), color = Ink.text))
        Box(Modifier.padding(top = 8.dp).fillMaxWidth().height(2.dp).background(Ink.accentRule))
    }
}

@Composable
internal fun ReachNote(text: String, color: Color = Ink.muted, modifier: Modifier = Modifier) {
    BasicText(text, style = reachText(13, color = color), modifier = modifier.padding(top = 8.dp))
}

@Composable
internal fun ReachField(label: String, value: String, onChange: (String) -> Unit, placeholder: String = "", secret: Boolean = false,
                        keyboard: KeyboardType = KeyboardType.Text) {
    Column(Modifier.padding(top = 12.dp)) {
        BasicText(label, style = reachText(13, 500, Ink.muted))
        BasicTextField(
            value, onChange, singleLine = true,
            textStyle = reachText(16),
            cursorBrush = SolidColor(Ink.accent),
            visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(keyboardType = keyboard, autoCorrectEnabled = false),
            modifier = Modifier.padding(top = 4.dp).fillMaxWidth().semantics { contentDescription = label },
            decorationBox = { inner ->
                Box(Modifier.fillMaxWidth().heightIn(min = 48.dp).border(1.dp, Ink.control, RoundedCornerShape(4.dp)).padding(horizontal = 12.dp),
                    contentAlignment = Alignment.CenterStart) {
                    if (value.isEmpty() && placeholder.isNotEmpty()) BasicText(placeholder, style = reachText(16, color = Ink.muted))
                    inner()
                }
            },
        )
    }
}

@Composable
internal fun ReachButton(label: String, primary: Boolean = false, enabled: Boolean = true, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(4.dp)
    val base = modifier.heightIn(min = 48.dp).clickable(enabled = enabled, role = Role.Button, onClick = onClick)
    val look = if (primary) base.background(if (enabled) Ink.accent else Ink.rule, shape) else base.border(1.dp, if (enabled) Ink.text else Ink.rule, shape)
    Box(look.padding(horizontal = 18.dp), contentAlignment = Alignment.Center) {
        BasicText(label, style = reachText(15, 700, when { primary -> if (enabled) Ink.onAccent else Ink.muted; enabled -> Ink.text; else -> Ink.muted }))
    }
}

/** A labelled on/off row, with an optional line of explanation; the whole row toggles. */
@Composable
internal fun ReachToggle(label: String, on: Boolean, detail: String? = null, onChange: (Boolean) -> Unit) {
    Row(Modifier.padding(top = 8.dp).fillMaxWidth().heightIn(min = 48.dp)
        .semantics(mergeDescendants = true) { stateDescription = if (on) "On" else "Off" }
        .clickable(role = Role.Switch) { onChange(!on) }, verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(vertical = 4.dp)) {
            BasicText(label, style = reachText(16))
            detail?.let { BasicText(it, style = reachText(13, color = Ink.muted)) }
        }
        KSwitch(on, Modifier.padding(start = 12.dp))
    }
}
