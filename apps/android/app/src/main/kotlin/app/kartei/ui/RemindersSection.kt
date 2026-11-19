// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import android.Manifest
import android.app.TimePickerDialog
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.text.format.DateFormat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import app.kartei.DeckStore
import app.kartei.reach.KarteiWidget
import app.kartei.reach.Reminders
import java.time.LocalTime
import java.util.Calendar

private fun timeText(context: Context, minute: Int): String {
    val cal = Calendar.getInstance().apply { set(Calendar.HOUR_OF_DAY, minute / 60); set(Calendar.MINUTE, minute % 60) }
    return DateFormat.getTimeFormat(context).format(cal.time)
}

private fun pickTime(context: Context, start: Int, chosen: (Int) -> Unit) {
    TimePickerDialog(context, android.R.style.Theme_DeviceDefault_Dialog, { _, h, m -> chosen(h * 60 + m) },
        start / 60, start % 60, DateFormat.is24HourFormat(context)).apply { setTitle("Remind me at") }.show()
}

/** Settings → Reminder (off until the person turns it on and picks a time) and the home-screen widget. */
@Suppress("UNUSED_PARAMETER")
@Composable
fun RemindersSection(store: DeckStore) {
    val context = LocalContext.current
    var on by remember { mutableStateOf(Reminders.isOn(context)) }
    var minute by remember { mutableIntStateOf(Reminders.minuteOfDay(context)) }
    var blocked by remember { mutableStateOf(false) }

    // Suggest the next quarter hour from now: no time of day is known to be better, so start from the present.
    val suggestion = remember { LocalTime.now().let { t -> ((t.hour * 60 + t.minute) / 15 + 1) * 15 % (24 * 60) } }
    fun turnOn() = pickTime(context, if (minute >= 0) minute else suggestion) { m ->
        minute = m; on = true; blocked = !Reminders.canNotify(context)
        Reminders.set(context, true, m)
    }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) turnOn() else blocked = true
    }

    ReachHeading("Reminder")
    ReachToggle("Daily reminder", on) { want ->
        if (!want) { on = false; Reminders.set(context, false); return@ReachToggle }
        if (Build.VERSION.SDK_INT >= 33 && !Reminders.canNotify(context)) ask.launch(Manifest.permission.POST_NOTIFICATIONS) else turnOn()
    }
    if (on && minute >= 0) {
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(role = Role.Button, onClickLabel = "Change time") {
            pickTime(context, minute) { m -> minute = m; Reminders.set(context, true, m) }
        }, verticalAlignment = Alignment.CenterVertically) {
            BasicText("Time", style = reachText(16), modifier = Modifier.weight(1f))
            BasicText(timeText(context, minute), style = reachText(16, 700).copy(textDecoration = TextDecoration.Underline))
        }
    }
    ReachNote("Sent only on days when cards are due, with how long they'll take, like \"12 min of cards today\". " +
        "There's no good evidence that one time of day is better for remembering, so pick a time that suits your day.")
    if (blocked) {
        ReachNote("Notifications are turned off for Bergmönch, so the reminder can't appear.", color = Ink.learning)
        BasicText("Open notification settings", style = reachText(13, 500).copy(textDecoration = TextDecoration.Underline),
            modifier = Modifier.heightIn(min = 48.dp).clickable(role = Role.Button) {
                context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
            }.padding(top = 14.dp))
    }

    val widgets = context.getSystemService(AppWidgetManager::class.java)
    if (widgets?.isRequestPinAppWidgetSupported == true) {
        ReachHeading("Widget")
        ReachNote("Today's minutes and your five-week calendar on the home screen, as of the last time Bergmönch was open.")
        Row(Modifier.padding(top = 12.dp)) {
            ReachButton("Add to home screen") {
                KarteiWidget.updateAll(context)
                widgets.requestPinAppWidget(ComponentName(context, KarteiWidget::class.java), null, null)
            }
        }
    }
}
