package dev.personalapp.personal_mobile_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject

/**
 * The "Sketch" home-screen widget: the newest sketch note, and a button that opens a blank canvas.
 *
 * A home-screen widget cannot follow a finger, so drawing happens in the app: both buttons open the
 * app straight on the sketch editor (MainActivity hands the request to Flutter, see lib/launch.dart),
 * and closing the editor saves the sketch as a note. The widget reads the `notes` table directly and
 * draws the sketch the way `SketchPainter` in lib/sketch.dart does; keep the two alike.
 */
class SketchWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = render(context)

    private class Latest(val id: Long, val title: String, val sketch: String)

    companion object {
        /** Sketches are 3 wide to 4 tall, as in the app. */
        private const val W = 480
        private const val H = 640

        private fun latest(context: Context): Latest? {
            val file = context.getDatabasePath("life.db")
            if (!file.exists()) return null
            val db = SQLiteDatabase.openDatabase(
                file.path, null, SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS,
            )
            return db.use {
                it.rawQuery(
                    "SELECT id, title, sketch FROM notes WHERE sketch IS NOT NULL AND sketch != '' " +
                        "ORDER BY updated_at DESC, id DESC LIMIT 1",
                    null,
                ).use { c -> if (c.moveToFirst()) Latest(c.getLong(0), c.getString(1) ?: "", c.getString(2)) else null }
            }
        }

        /** Draws a sketch's strokes; colour 0 is "ink", the widget's text colour. Null when there is nothing. */
        private fun draw(json: String, ink: Int): Bitmap? {
            val strokes = try {
                JSONObject(json).getJSONArray("strokes")
            } catch (_: Exception) {
                return null
            }
            if (strokes.length() == 0) return null
            val bitmap = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            canvas.clipRect(0, 0, W, H)
            for (i in 0 until strokes.length()) {
                val s = strokes.getJSONObject(i)
                val p = s.getJSONArray("p")
                if (p.length() < 2) continue
                val color = s.getLong("c").toInt()
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    this.color = if (color == 0) ink else color
                    strokeWidth = (s.getDouble("w") * W).toFloat()
                    strokeCap = Paint.Cap.ROUND
                    strokeJoin = Paint.Join.ROUND
                    style = Paint.Style.STROKE
                }
                // Points are fractions of the canvas width, for x and y alike.
                fun at(k: Int) = (p.getDouble(k) * W).toFloat()
                if (p.length() < 4) {
                    canvas.drawPoint(at(0), at(1), paint) // a single tap is a dot
                    continue
                }
                val path = Path().apply { moveTo(at(0), at(1)) }
                var j = 2
                while (j + 1 < p.length()) {
                    path.lineTo(at(j), at(j + 1))
                    j += 2
                }
                canvas.drawPath(path, paint)
            }
            return bitmap
        }

        private fun opener(context: Context, open: String, request: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .putExtra(MainActivity.EXTRA_OPEN, open)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(
                context, request, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /** Redraws every copy of the widget on the home screen. */
        fun render(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, SketchWidget::class.java))
            if (ids.isEmpty()) return

            val latest = try {
                latest(context)
            } catch (_: Exception) {
                null // The app has the file busy; the next redraw will show it.
            }
            val picture = latest?.let { draw(it.sketch, context.getColor(R.color.widget_text)) }

            val views = RemoteViews(context.packageName, R.layout.widget_sketch)
            views.setTextViewText(
                R.id.widget_caption,
                when {
                    picture == null || latest == null -> context.getString(R.string.widget_sketch_empty)
                    latest.title.isNotBlank() -> latest.title
                    else -> context.getString(R.string.widget_sketch_last)
                },
            )
            if (picture != null) {
                views.setImageViewBitmap(R.id.widget_picture, picture)
                views.setViewVisibility(R.id.widget_picture, View.VISIBLE)
                views.setViewVisibility(R.id.widget_hint, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_picture, View.GONE)
                views.setViewVisibility(R.id.widget_hint, View.VISIBLE)
            }

            // The button always starts a blank sketch; the canvas reopens the sketch it shows.
            views.setOnClickPendingIntent(R.id.widget_new, opener(context, "sketch:new", 10))
            views.setOnClickPendingIntent(
                R.id.widget_canvas,
                opener(context, if (picture != null && latest != null) "sketch:${latest.id}" else "sketch:new", 11),
            )
            manager.updateAppWidget(ids, views)
        }
    }
}
