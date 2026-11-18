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
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * The "Savings jar" home-screen widget: a jar of coins filled towards the savings goal, how much is saved,
 * and a button that opens the app on the "Into the jar" sheet (see lib/launch.dart).
 *
 * It reads `settings` (the `goal` and `currency` values) and the `saving` rows of `transactions` from
 * life.db directly, and draws the jar the way `JarPainter` in lib/jar.dart does; keep the two alike.
 */
class JarWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = render(context)

    private class Jar(val saved: Double, val target: Double?, val name: String, val currency: String)

    companion object {
        private const val W = 300
        private const val H = 400
        private val GOLD = 0xFFF2C94C.toInt()
        private val RIM = 0xFFC9A227.toInt()
        private val SHINE = 0xCCFFE69A.toInt()

        private fun read(context: Context): Jar {
            val file = context.getDatabasePath("life.db")
            if (!file.exists()) return Jar(0.0, null, "", "$")
            val db = SQLiteDatabase.openDatabase(
                file.path, null, SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS,
            )
            return db.use {
                fun setting(key: String): String? =
                    it.rawQuery("SELECT value FROM settings WHERE key = ?", arrayOf(key)).use { c ->
                        if (c.moveToFirst()) c.getString(0) else null
                    }
                val saved = it.rawQuery("SELECT SUM(amount) FROM transactions WHERE kind = 'saving'", null)
                    .use { c -> if (c.moveToFirst() && !c.isNull(0)) c.getDouble(0) else 0.0 }
                // Settings are stored as JSON: the goal is an object, the currency a quoted string.
                val goal = try {
                    setting("goal")?.let { g -> if (g == "null") null else JSONObject(g) }
                } catch (_: Exception) {
                    null
                }
                val currency = try {
                    setting("currency")?.let { v -> JSONObject("{\"v\":$v}").getString("v") } ?: "$"
                } catch (_: Exception) {
                    "$"
                }
                Jar(saved, goal?.optDouble("target")?.takeIf { t -> t > 0 }, goal?.optString("name") ?: "", currency)
            }
        }

        /** "1,234.5" with the symbol before or the code after, as `formatMoney` in lib/screens/wallet.dart. */
        private fun money(n: Double, currency: String): String {
            var s = String.format(Locale.US, "%,.2f", n).trimEnd('0').trimEnd('.')
            if (s.isEmpty()) s = "0"
            return if (currency.length <= 1) "$currency$s" else "$s $currency"
        }

        private fun drawJar(fill: Double, glass: Int, lid: Int): Bitmap {
            val bitmap = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val w = W.toFloat()
            val h = H.toFloat()
            val r = w * 0.2f
            val body = RectF(w * 0.06f, h * 0.16f, w * 0.94f, h)
            val inset = w * 0.03f
            val inner = RectF(body.left + inset, body.top + inset, body.right - inset, body.bottom - inset)
            val stroke = max(1.5f, w * 0.025f)
            fun alpha(color: Int, a: Float) = Color.argb((a * 255).roundToInt(), Color.red(color), Color.green(color), Color.blue(color))

            // Coins, inside the glass.
            canvas.save()
            val clip = android.graphics.Path().apply { addRoundRect(inner, r - inset, r - inset, android.graphics.Path.Direction.CW) }
            canvas.clipPath(clip)
            val coinW = w * 0.3f
            val coinH = w * 0.12f
            val level = inner.bottom - inner.height() * fill.toFloat()
            val rise = coinH * 0.62f
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            var row = 0
            while (inner.bottom - row * rise + coinH * 0.5f > level) {
                val baseY = inner.bottom - row * rise - coinH * 0.15f
                var x = inner.left - coinW * 0.5f + if (row % 2 == 1) coinW * 0.5f else 0f
                while (x < inner.right + coinW * 0.5f) {
                    val y = baseY + (sin(row * 12.9898 + x * 0.78) * coinH * 0.18).toFloat()
                    if (y - coinH * 0.5f >= level - coinH * 0.25f) {
                        paint.color = RIM
                        canvas.drawOval(RectF(x - coinW / 2, y - coinH / 2 + coinH * 0.18f, x + coinW / 2, y + coinH / 2 + coinH * 0.18f), paint)
                        paint.color = GOLD
                        canvas.drawOval(RectF(x - coinW / 2, y - coinH / 2, x + coinW / 2, y + coinH / 2), paint)
                        paint.color = SHINE
                        val cx = x - coinW * 0.12f
                        val cy = y - coinH * 0.12f
                        canvas.drawOval(RectF(cx - coinW * 0.175f, cy - coinH * 0.15f, cx + coinW * 0.175f, cy + coinH * 0.15f), paint)
                    }
                    x += coinW * 0.92f
                }
                row++
            }
            canvas.restore()

            // The glass, its shine, and the lid.
            paint.style = Paint.Style.FILL
            paint.color = alpha(glass, 0.08f)
            canvas.drawRoundRect(body, r, r, paint)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = stroke
            paint.color = alpha(glass, 0.55f)
            canvas.drawRoundRect(body, r, r, paint)
            paint.strokeWidth = w * 0.045f
            paint.strokeCap = Paint.Cap.ROUND
            paint.color = alpha(Color.WHITE, 0.18f)
            canvas.drawLine(w * 0.2f, h * 0.3f, w * 0.2f, h * 0.62f, paint)
            val lidRect = RectF(w * 0.2f, 0f, w * 0.8f, h * 0.13f)
            paint.style = Paint.Style.FILL
            paint.color = lid
            canvas.drawRoundRect(lidRect, w * 0.06f, w * 0.06f, paint)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = stroke
            paint.color = alpha(glass, 0.55f)
            canvas.drawRoundRect(lidRect, w * 0.06f, w * 0.06f, paint)
            return bitmap
        }

        /** Redraws every copy of the widget on the home screen. */
        fun render(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, JarWidget::class.java))
            if (ids.isEmpty()) return

            val jar = try {
                read(context)
            } catch (_: Exception) {
                Jar(0.0, null, "", "$") // The app has the file busy; the next redraw will show it.
            }
            val fill = if (jar.target == null) 0.0 else (jar.saved / jar.target).coerceIn(0.0, 1.0)

            val views = RemoteViews(context.packageName, R.layout.widget_jar)
            views.setImageViewBitmap(
                R.id.jar_picture,
                drawJar(fill, context.getColor(R.color.widget_dim), context.getColor(R.color.widget_alt)),
            )
            views.setTextViewText(R.id.jar_name, if (jar.name.isBlank()) context.getString(R.string.widget_jar_name) else jar.name)
            views.setTextViewText(R.id.jar_saved, money(jar.saved, jar.currency))
            views.setTextViewText(
                R.id.jar_detail,
                when {
                    jar.target == null -> context.getString(R.string.widget_jar_no_goal)
                    fill >= 1.0 -> context.getString(R.string.widget_jar_full)
                    else -> "${(fill * 100).roundToInt()}% of ${money(jar.target, jar.currency)}"
                },
            )

            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val drop = Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .putExtra(MainActivity.EXTRA_OPEN, "jar:add")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            views.setOnClickPendingIntent(R.id.jar_add, PendingIntent.getActivity(context, 20, drop, flags))
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                views.setOnClickPendingIntent(R.id.jar_root, PendingIntent.getActivity(context, 21, it, flags))
            }
            manager.updateAppWidget(ids, views)
        }
    }
}
