package dev.personalapp.personal_mobile_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * The "Up next" home-screen widget: the calendar block happening now or coming next, the day's
 * progress, and a Done button for the current block.
 *
 * It reads the app's own database file directly, so it works while the app is closed. The rules for
 * what counts as "now" and "next" mirror `_DayCard` in lib/screens/calendar.dart; keep the two alike.
 */
class UpNextWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = render(context)

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_DONE -> {
                markDone(context, intent.getLongExtra(EXTRA_ID, -1))
                render(context)
            }
            ACTION_REFRESH, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED -> render(context)
        }
    }

    private class Block(val id: Long, val title: String, val category: String, val start: Int, val end: Int, val done: Boolean)

    private class Shown(
        val tag: String,
        val title: String,
        val detail: String,
        val color: Int,
        val doneId: Long? = null,
        val done: Int = 0,
        val total: Int = 0,
        /** Minutes after midnight when the widget should next redraw itself. */
        val nextChange: Int = 1440,
    )

    companion object {
        private const val ACTION_DONE = "dev.personalapp.personal_mobile_app.WIDGET_DONE"
        private const val ACTION_REFRESH = "dev.personalapp.personal_mobile_app.WIDGET_REFRESH"
        private const val EXTRA_ID = "event_id"

        private const val GREEN = 0xFF3DBE7F.toInt()
        private const val AMBER = 0xFFE6A23C.toInt()
        private const val GREY = 0xFF8C93A0.toInt()

        /** The calendar categories' colours, as in lib/theme.dart. */
        private val colors = mapOf(
            "work" to 0xFF6C8CFF, "study" to 0xFF4FC3F7, "gym" to 0xFFFF7A59, "food" to 0xFF3DBE7F,
            "sleep" to 0xFF7986CB, "game" to 0xFFB57BFF, "watch" to 0xFFFF6FAE, "read" to 0xFFD4A373,
            "social" to 0xFFFFB74D, "family" to 0xFFF48FB1, "chores" to 0xFF4DB6AC, "errand" to 0xFFE6C84F,
            "travel" to 0xFF64B5F6, "health" to 0xFFEF6C6C, "hobby" to 0xFFAED581,
        )

        private fun time(minutes: Int): String {
            val m = ((minutes % 1440) + 1440) % 1440
            return String.format(Locale.US, "%02d:%02d", m / 60, m % 60)
        }

        private fun open(context: Context): SQLiteDatabase? {
            val file = context.getDatabasePath("life.db")
            if (!file.exists()) return null
            return SQLiteDatabase.openDatabase(
                file.path,
                null,
                SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.NO_LOCALIZED_COLLATORS,
            )
        }

        private fun markDone(context: Context, id: Long) {
            if (id < 0) return
            try {
                open(context)?.use { it.execSQL("UPDATE events SET done = 1 WHERE id = ?", arrayOf(id)) }
            } catch (_: Exception) {
                // The app has the file busy; the block stays as it was and can be ticked again.
            }
        }

        private fun read(context: Context): Shown {
            val now = Calendar.getInstance()
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now.time)
            val minute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            // Monday is 0, as in the app.
            val weekday = (now.get(Calendar.DAY_OF_WEEK) + 5) % 7

            val blocks = mutableListOf<Block>()
            val db = open(context)
                ?: return Shown("HYETI", "Open the app to plan your day", "Nothing has been set up yet.", GREY)
            db.use {
                // The app copies routine blocks into a day the first time it is opened; do the same here,
                // so the widget is right on a morning when the app has not been opened yet.
                it.execSQL(
                    "INSERT OR IGNORE INTO events (routine_id, date, title, category, start_min, end_min, flex_min) " +
                        "SELECT id, ?, title, category, start_min, end_min, flex_min FROM routines " +
                        "WHERE created_date <= ? AND instr(days, ?) > 0",
                    arrayOf(today, today, weekday.toString()),
                )
                val dayOff = it.rawQuery("SELECT 1 FROM day_offs WHERE date = ?", arrayOf(today)).use { c -> c.moveToFirst() }
                it.rawQuery(
                    "SELECT id, title, category, start_min + shift_min, end_min + shift_min, done FROM events " +
                        "WHERE date = ? AND hidden = 0 ORDER BY start_min + shift_min, id",
                    arrayOf(today),
                ).use { c ->
                    while (c.moveToNext()) {
                        // On a day off, work blocks are left out.
                        if (dayOff && c.getString(2) == "work") continue
                        blocks += Block(c.getLong(0), c.getString(1), c.getString(2), c.getInt(3), c.getInt(4), c.getInt(5) == 1)
                    }
                }
            }

            val total = blocks.size
            val done = blocks.count { it.done }
            val open = blocks.filter { !it.done }
            val current = open.firstOrNull { it.start <= minute && minute < it.end }
            val next = open.firstOrNull { it.start > minute }
            // Redraw when the next block starts or the current one ends, and at midnight at the latest.
            val nextChange = (open.flatMap { listOf(it.start, it.end) }.filter { it > minute } + 1440).min()
            fun colorOf(b: Block) = (colors[b.category] ?: 0xFF8C93A0).toInt()

            return when {
                total == 0 -> Shown("TODAY", "Nothing planned", "Tap to add something.", GREY)
                current != null -> Shown(
                    "NOW", current.title, "Until ${time(current.end)}", colorOf(current), current.id, done, total, nextChange,
                )
                next != null -> Shown(
                    "UP NEXT", next.title, "${time(next.start)} – ${time(next.end)}", colorOf(next), null, done, total, nextChange,
                )
                open.isEmpty() -> Shown("TODAY", "All done", "Everything is ticked off.", GREEN, null, done, total)
                else -> Shown(
                    "TODAY",
                    "Nothing else scheduled",
                    if (open.size == 1) "1 block is not ticked off." else "${open.size} blocks are not ticked off.",
                    AMBER, null, done, total,
                )
            }
        }

        /** Redraws every copy of the widget on the home screen and books the next redraw. */
        fun render(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, UpNextWidget::class.java))
            if (ids.isEmpty()) return

            val shown = try {
                read(context)
            } catch (_: Exception) {
                Shown("HYETI", "Open the app", "The calendar could not be read just now.", GREY)
            }
            val immutable = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

            val views = RemoteViews(context.packageName, R.layout.widget_up_next)
            views.setTextViewText(R.id.widget_tag, if (shown.total > 0) "${shown.tag} · ${shown.done} of ${shown.total} done" else shown.tag)
            views.setTextViewText(R.id.widget_title, shown.title)
            views.setTextViewText(R.id.widget_detail, shown.detail)
            views.setInt(R.id.widget_bar, "setColorFilter", shown.color)
            views.setViewVisibility(R.id.widget_progress, if (shown.total > 0) View.VISIBLE else View.GONE)
            views.setProgressBar(R.id.widget_progress, maxOf(shown.total, 1), shown.done, false)

            // Tapping the widget opens the app.
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(context, 0, it, immutable))
            }
            if (shown.doneId != null) {
                val tick = Intent(context, UpNextWidget::class.java).setAction(ACTION_DONE).putExtra(EXTRA_ID, shown.doneId)
                views.setOnClickPendingIntent(R.id.widget_done, PendingIntent.getBroadcast(context, 1, tick, immutable))
                views.setViewVisibility(R.id.widget_done, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_done, View.GONE)
            }
            manager.updateAppWidget(ids, views)

            // Wake up again when what is shown goes out of date. The alarm is inexact (it needs no
            // permission), so the change can show up to a few minutes late.
            val at = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 5)
                set(Calendar.MILLISECOND, 0)
                add(Calendar.MINUTE, shown.nextChange)
            }
            val refresh = Intent(context, UpNextWidget::class.java).setAction(ACTION_REFRESH)
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
                .set(AlarmManager.RTC, at.timeInMillis, PendingIntent.getBroadcast(context, 2, refresh, immutable))
        }
    }
}
