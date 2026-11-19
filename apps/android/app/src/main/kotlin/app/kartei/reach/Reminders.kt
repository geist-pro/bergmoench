// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.reach

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import app.kartei.MainActivity
import app.kartei.R
import app.kartei.ThemePrefs
import app.kartei.Reach
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZonedDateTime

/**
 * Daily study reminder. Off by default: there is no evidence that one time of day is better for memory, so the person
 * picks the time. Scheduled with an inexact AlarmManager alarm (setAndAllowWhileIdle): no exact-alarm permission,
 * still fires in Doze, and a few minutes' drift doesn't matter for "cards are waiting". WorkManager was the
 * alternative; it defers work to Doze maintenance windows (can be hours) and adds a dependency, while the only
 * thing it would buy here, surviving reboots, is one BOOT_COMPLETED receiver.
 */
object Reminders {
    private const val PREFS = "kartei.reach"
    private const val CHANNEL = "study-reminder"
    private const val EXTRA_AT = "at"
    private const val NOTIFICATION_ID = 1

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isOn(c: Context) = prefs(c).getBoolean("on", false)
    /** Minutes after midnight, or -1 when no time was ever chosen. */
    fun minuteOfDay(c: Context) = prefs(c).getInt("minute", -1)

    fun set(c: Context, on: Boolean, minute: Int = minuteOfDay(c)) {
        prefs(c).edit().putBoolean("on", on && minute >= 0).putInt("minute", minute).apply()
        schedule(c)
    }

    fun canNotify(c: Context): Boolean {
        val nm = c.getSystemService(NotificationManager::class.java)
        if (!nm.areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < 33 || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    private fun pending(c: Context, at: Long, create: Boolean): PendingIntent? {
        val intent = Intent(c, ReminderReceiver::class.java).setAction(ReminderReceiver.FIRE).putExtra(EXTRA_AT, at)
        val flags = PendingIntent.FLAG_IMMUTABLE or if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE
        return PendingIntent.getBroadcast(c, 0, intent, flags)
    }

    /** (Re)arm the alarm for the next chosen time, or cancel it when reminders are off. Idempotent. */
    fun schedule(c: Context) {
        val am = c.getSystemService(AlarmManager::class.java)
        pending(c, 0, create = false)?.let { am.cancel(it); it.cancel() }
        val minute = minuteOfDay(c)
        if (!isOn(c) || minute < 0) return
        val at = nextTrigger(ZonedDateTime.now(), LocalTime.of(minute / 60, minute % 60)).toInstant().toEpochMilli()
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(c, at, create = true)!!)
    }

    internal fun fire(c: Context, scheduledAt: Long) {
        val now = System.currentTimeMillis()
        val text = if (tooLate(scheduledAt, now)) null else reminderFor(Reach.read(c), LocalDate.now())
        if (text != null && canNotify(c)) post(c, text)
        KarteiWidget.updateAll(c)
        schedule(c)
    }

    private fun post(c: Context, text: ReminderText) {
        val nm = c.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Study reminder", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Once a day at the time you chose, only when cards are due."
        })
        val open = PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = android.app.Notification.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_kartei)
            .setContentTitle(text.title)
            .setContentText(text.body)
            .setColor(ThemePrefs.of(c).palette(ThemePrefs.systemDark(c)).accent.toInt())
            .setContentIntent(open)
            .setAutoCancel(true)
            .setCategory(android.app.Notification.CATEGORY_REMINDER)
            .build()
        runCatching { nm.notify(NOTIFICATION_ID, n) }
    }
}

/** Fires the reminder and re-arms it after reboots, app updates and clock or time-zone changes. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            FIRE -> Reminders.fire(context, intent.getLongExtra("at", 0L))
            else -> { Reminders.schedule(context); KarteiWidget.updateAll(context) }
        }
    }

    companion object { const val FIRE = "app.kartei.REMINDER" }
}
