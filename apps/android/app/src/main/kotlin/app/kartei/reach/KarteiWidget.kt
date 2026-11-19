// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.reach

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Bundle
import android.widget.RemoteViews
import app.kartei.MainActivity
import app.kartei.R
import app.kartei.Reach
import app.kartei.ThemePrefs
import app.kartei.ui.Family
import app.kartei.ui.Palettes
import java.time.LocalDate

/**
 * Home-screen widget: today's minutes as the big numeral and the five-week study calendar, in the look chosen in Settings
 * (stored in the snapshot). It follows the system's light/dark mode: the RemoteViews carry a light and a dark bitmap, and
 * layout/ vs layout-night/ show one of them, so the launcher switches when the system mode changes without waking the app.
 * RemoteViews with one bitmap drawn on a Canvas, not Glance: Glance can't use the app's variable fonts
 * (Bricolage Grotesque 800/200), and a 35-cell grid of RemoteViews would be close to the launcher's view limits.
 * Reads only the snapshot that Reach writes; never opens the collection. Tapping opens the app.
 */
class KarteiWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = ids.forEach { draw(context, manager, it) }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) = draw(context, manager, id)

    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = runCatching { manager.getAppWidgetIds(ComponentName(context, KarteiWidget::class.java)) }.getOrNull() ?: return
            ids.forEach { draw(context, manager, it) }
        }

        private fun draw(context: Context, manager: AppWidgetManager, id: Int) {
            val o = manager.getAppWidgetOptions(id)
            val portrait = context.resources.configuration.orientation != android.content.res.Configuration.ORIENTATION_LANDSCAPE
            val wDp = (if (portrait) o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) else o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)).takeIf { it > 0 } ?: 250
            val hDp = (if (portrait) o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT) else o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)).takeIf { it > 0 } ?: 110
            val snap = Reach.read(context)
            val today = LocalDate.now()
            val family = Family.of(snap?.family) ?: ThemePrefs.DEFAULT_FAMILY
            val views = RemoteViews(context.packageName, R.layout.widget_kartei)
            val w = wDp.coerceIn(110, 600); val h = hDp.coerceIn(60, 400)
            for ((viewId, dark) in listOf(R.id.widget_light to false, R.id.widget_dark to true)) {
                views.setImageViewBitmap(viewId, WidgetArt(context, family, dark).render(snap, today, w, h))
                views.setContentDescription(viewId, WidgetArt.describe(snap, today))
            }
            val open = PendingIntent.getActivity(context, 1, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            views.setOnClickPendingIntent(R.id.widget_root, open)
            runCatching { manager.updateAppWidget(id, views) }
        }
    }
}

/** Draws the widget. Sizes in dp, scaled by the screen density (at most 3x to keep the bitmap small). */
class WidgetArt(private val context: Context, family: Family, dark: Boolean) {
    private val p = Palettes.of(family, dark)
    private val bg = p.bg.toInt()
    private val rule = p.rule.toInt()
    private val text = p.text.toInt()
    private val display = p.display.toInt()
    private val muted = p.muted.toInt()
    private val todayRing = p.accentRule.toInt()
    private val displayFont = if (family == Family.Geist) R.font.nunito else R.font.bricolage_grotesque
    private val bodyFont = if (family == Family.Geist) R.font.noto_serif else R.font.dm_sans

    private fun paint(font: Int, weight: Int, sizePx: Float, color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = runCatching { context.resources.getFont(font) }.getOrElse { Typeface.DEFAULT }
        fontVariationSettings = "'wght' $weight"
        textSize = sizePx
        this.color = color
    }

    fun render(snap: Snapshot?, today: LocalDate, wDp: Int, hDp: Int): Bitmap {
        // Two bitmaps travel in one RemoteViews, so keep each under about 1.2 million pixels.
        val d = minOf(context.resources.displayMetrics.density, 3f, kotlin.math.sqrt(1_200_000f / (wDp * hDp)))
        val w = (wDp * d).toInt(); val h = (hDp * d).toInt()
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = bg }
        c.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), 20 * d, 20 * d, fill)

        val pad = 16 * d
        val live = snap != null && snap.day == today
        val minutes = if (live) snap!!.minutes.toString() else "–"
        val caption = when {
            snap == null -> "Open Bergmönch to count today"
            !live -> "Open Bergmönch to count today"
            snap.cards == 0 -> "Nothing due today"
            snap.cards == 1 -> "1 card today"
            else -> "${snap.cards} cards today"
        }
        val studied = snap?.studied.orEmpty()
        val showCalendar = wDp >= 220

        // Calendar on the right: five rows (this week at the bottom), Monday first, today outlined in the accent rule colour.
        var calLeft = w - pad
        if (showCalendar) {
            val gap = 3 * d
            val captionH = 16 * d
            val cell = minOf((h - 2 * pad - captionH - 4 * gap) / 5, 14 * d)
            val gridW = 7 * cell + 6 * gap
            calLeft = w - pad - gridW
            val top = pad
            val weekday = today.dayOfWeek.value - 1
            val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
            val solid = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = text }
            val r = 1 * d
            for (week in 0 until 5) for (day in 0 until 7) {
                val offset = (week - 4) * 7 + day - weekday
                val x = calLeft + day * (cell + gap); val y = top + week * (cell + gap)
                val box = RectF(x, y, x + cell, y + cell)
                val inset = RectF(box).apply { inset(d / 2, d / 2) }
                val date = today.plusDays(offset.toLong())
                when {
                    offset > 0 -> { stroke.color = rule; stroke.alpha = 115; stroke.strokeWidth = d; c.drawRoundRect(inset, r, r, stroke) }
                    offset == 0 -> {
                        if (date in studied) c.drawRoundRect(box, r, r, solid)
                        stroke.color = todayRing; stroke.alpha = 255; stroke.strokeWidth = 2 * d
                        c.drawRoundRect(RectF(box).apply { inset(d, d) }, r, r, stroke)
                    }
                    date in studied -> c.drawRoundRect(box, r, r, solid)
                    else -> { stroke.color = rule; stroke.alpha = 255; stroke.strokeWidth = d; c.drawRoundRect(inset, r, r, stroke) }
                }
            }
            val count = studied.count { it <= today && it > today.minusDays(35) }
            val small = paint(bodyFont, 400, 12 * d, muted).apply { textAlign = Paint.Align.RIGHT }
            c.drawText("$count ${if (count == 1) "day" else "days"} in 5 weeks", w - pad, top + 5 * cell + 4 * gap + captionH - 2 * d, small)
        }

        // Numeral and "min", baseline-aligned, sized to the space on the left.
        val leftW = (if (showCalendar) calLeft - 14 * d else w - pad) - pad
        val captionPaint = paint(bodyFont, 500, 13 * d, muted)
        val captionBase = h - pad
        var size = minOf(h - 2 * pad - 22 * d, 84 * d)
        val big = paint(displayFont, 800, size, display).apply { letterSpacing = -0.03f }
        val unit = paint(displayFont, 200, size * 0.5f, display)
        fun width() = big.measureText(minutes) + 6 * d + unit.measureText("min")
        while (width() > leftW && size > 20 * d) { size -= 2 * d; big.textSize = size; unit.textSize = size * 0.5f }
        val baseline = captionBase - 13 * d - 8 * d
        c.drawText(minutes, pad, baseline, big)
        c.drawText("min", pad + big.measureText(minutes) + 6 * d, baseline, unit)
        val cap = if (captionPaint.measureText(caption) > leftW) caption.replace("Open Bergmönch to count today", "Open to count") else caption
        c.drawText(cap, pad, captionBase, captionPaint)
        return bmp
    }

    companion object {
        fun describe(snap: Snapshot?, today: LocalDate): String {
            val days = snap?.studied.orEmpty().count { it <= today && it > today.minusDays(35) }
            val head = if (snap != null && snap.day == today) "${snap.minutes} minutes of cards today, ${snap.cards} cards." else "Open Bergmönch to count today's cards."
            return "$head Studied on $days of the last 35 days. Opens Bergmönch."
        }
    }
}
