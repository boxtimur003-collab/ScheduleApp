#!/data/data/com.termux/files/usr/bin/bash
set +H
cd "${1:-$HOME/ScheduleApp}" || { echo 'Папка проекта не найдена'; exit 1; }

WF=$(find wear -name ScheduleWatchFaceService.kt -not -path '*/build/*' 2>/dev/null | head -1)
if [ -z "$WF" ]; then
  echo 'ScheduleWatchFaceService.kt не найден. Сначала примени скрипт с циферблатом.'; exit 1
fi
WPKG=$(grep -m1 '^package' "$WF" | tr -d '\r' | sed 's/^package[[:space:]]*//; s/[[:space:]]*$//')
[ -z "$WPKG" ] && WPKG="com.example.schedule"
echo "WEAR: FILE=$WF PKG=$WPKG"

BAK="$HOME/.schedule_bak/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BAK"
cp "$WF" "$BAK/ScheduleWatchFaceService.kt"
echo "Резервная копия: $BAK"

# ======================= ЧАСЫ: ScheduleWatchFaceService.kt =======================
cat << 'KT_EOF' > "$WF"
package PKG__

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.BatteryManager
import android.view.SurfaceHolder
import androidx.wear.watchface.CanvasType
import androidx.wear.watchface.ComplicationSlot
import androidx.wear.watchface.ComplicationSlotsManager
import androidx.wear.watchface.DrawMode
import androidx.wear.watchface.Renderer
import androidx.wear.watchface.TapEvent
import androidx.wear.watchface.TapType
import androidx.wear.watchface.WatchFace
import androidx.wear.watchface.WatchFaceService
import androidx.wear.watchface.WatchFaceType
import androidx.wear.watchface.WatchState
import androidx.wear.watchface.style.CurrentUserStyleRepository
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.sqrt

/** С какого экрана открыть приложение: циферблат передаёт extra "open" = files | dates. */
fun initialOverlay(ctx: Context): Overlay {
    var c: Context? = ctx
    while (c is ContextWrapper) {
        if (c is Activity) {
            return when (c.intent?.getStringExtra("open")) {
                "files" -> Overlay.FILES
                "dates" -> Overlay.DATES
                else -> Overlay.NONE
            }
        }
        c = c.baseContext
    }
    return Overlay.NONE
}

private val WF_PURPLE = 0xFF7C5CFF.toInt()
private val WF_LILAC = 0xFFA78BFA.toInt()
private val WF_GREEN = 0xFF4CC36B.toInt()
private val WF_DIM = 0xFFB8B2D6.toInt()
private val WF_SOFT = 0xFFE6E0FF.toInt()
private val WF_CARD = 0xFF17161F.toInt()
private val WF_PILL = 0xFF14131C.toInt()
private val WF_RING = 0xFF2A2740.toInt()
private val WF_BTN = 0xFF1B1A22.toInt()
private val WF_DOT = 0xFF3A3A44.toInt()
private val WF_COLON = 0xFF8C88A8.toInt()

class ScheduleWatchFaceService : WatchFaceService() {
    override suspend fun createWatchFace(
        surfaceHolder: SurfaceHolder,
        watchState: WatchState,
        complicationSlotsManager: ComplicationSlotsManager,
        currentUserStyleRepository: CurrentUserStyleRepository
    ): WatchFace {
        val renderer = ScheduleRenderer(applicationContext, surfaceHolder, currentUserStyleRepository, watchState)
        val face = WatchFace(WatchFaceType.DIGITAL, renderer)
        face.setTapListener(object : WatchFace.TapListener {
            override fun onTapEvent(tapType: Int, tapEvent: TapEvent, complicationSlot: ComplicationSlot?) {
                if (tapType == TapType.UP) renderer.onTap(tapEvent.xPos.toFloat(), tapEvent.yPos.toFloat())
            }
        })
        return face
    }
}

private class ScheduleRenderer(
    private val ctx: Context,
    surfaceHolder: SurfaceHolder,
    currentUserStyleRepository: CurrentUserStyleRepository,
    watchState: WatchState
) : Renderer.CanvasRenderer2<ScheduleRenderer.Assets>(
    surfaceHolder, currentUserStyleRepository, watchState,
    CanvasType.HARDWARE, 1000L, false
) {
    class Assets : Renderer.SharedAssets {
        override fun onDestroy() {}
    }

    private class Hit(val r: RectF, val target: String)

    /** current - идёт сейчас; next - ближайшее после него; between - перерыв между занятиями. */
    private class Status(val current: Lesson?, val next: Lesson?, val between: Boolean)

    private val prefs: SharedPreferences = ctx.getSharedPreferences("schedule", Context.MODE_PRIVATE)

    @Volatile
    private var lessons: List<Lesson> = loadLessons()

    // слушатель хранится в поле: SharedPreferences держит его только слабой ссылкой
    private val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "json") {
            lessons = loadLessons()
            invalidate()
        }
    }

    private val p = Paint(Paint.ANTI_ALIAS_FLAG)
    private val normalFace: Typeface = Typeface.create("sans-serif", Typeface.NORMAL)
    private val boldFace: Typeface = Typeface.create("sans-serif", Typeface.BOLD)
    private val heavyFace: Typeface = Typeface.create("sans-serif-black", Typeface.NORMAL)
    private val dateFmt = DateTimeFormatter.ofPattern("EEE, d MMM", Locale("ru"))
    private val hits = ArrayList<Hit>()
    private var originX = 0f
    private var originY = 0f

    init {
        prefs.registerOnSharedPreferenceChangeListener(listener)
    }

    private fun loadLessons(): List<Lesson> =
        LessonJson.fromJson(prefs.getString("json", "[]") ?: "[]")

    override suspend fun createSharedAssets(): Assets = Assets()

    override fun render(canvas: Canvas, bounds: Rect, zonedDateTime: ZonedDateTime, sharedAssets: Assets) {
        hits.clear()
        originX = bounds.left.toFloat()
        originY = bounds.top.toFloat()
        val s = bounds.width().toFloat()
        canvas.drawColor(Color.BLACK)
        canvas.save()
        canvas.translate(originX, originY)
        if (renderParameters.drawMode == DrawMode.AMBIENT) drawAmbient(canvas, s, zonedDateTime)
        else drawInteractive(canvas, s, zonedDateTime)
        canvas.restore()
    }

    override fun renderHighlightLayer(canvas: Canvas, bounds: Rect, zonedDateTime: ZonedDateTime, sharedAssets: Assets) {
        canvas.drawColor(Color.TRANSPARENT)
    }

    // ---------------- нажатия ----------------
    fun onTap(x: Float, y: Float) {
        val lx = x - originX
        val ly = y - originY
        val target = hits.firstOrNull { it.r.contains(lx, ly) }?.target ?: "app"
        open(target)
    }

    private fun open(target: String) {
        val i = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            .putExtra("open", target)
        try {
            PendingIntent.getActivity(
                ctx, target.hashCode(), i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            ).send()
        } catch (e: Exception) {
            try {
                ctx.startActivity(i)
            } catch (e2: Exception) {
            }
        }
    }

    // ---------------- помощники рисования ----------------
    private fun fill(color: Int) {
        p.reset(); p.isAntiAlias = true
        p.style = Paint.Style.FILL; p.color = color
    }

    private fun stroke(color: Int, w: Float) {
        p.reset(); p.isAntiAlias = true
        p.style = Paint.Style.STROKE; p.color = color; p.strokeWidth = w
        p.strokeCap = Paint.Cap.ROUND; p.strokeJoin = Paint.Join.ROUND
    }

    private fun measure(str: String, size: Float, face: Typeface): Float {
        p.reset(); p.textSize = size; p.typeface = face
        return p.measureText(str)
    }

    private fun txt(
        c: Canvas, str: String, x: Float, y: Float, size: Float, color: Int, face: Typeface,
        align: Paint.Align = Paint.Align.LEFT, maxW: Float = 0f
    ) {
        p.reset(); p.isAntiAlias = true; p.style = Paint.Style.FILL
        p.color = color; p.textSize = size; p.typeface = face; p.textAlign = align
        var out = str
        if (maxW > 0f && p.measureText(out) > maxW) {
            var n = out.length
            while (n > 1 && p.measureText(out, 0, n) + p.measureText("…") > maxW) n--
            out = out.substring(0, n) + "…"
        }
        c.drawText(out, x, y, p)
    }

    private fun withAlpha(col: Int, a: Int): Int = Color.argb(a, Color.red(col), Color.green(col), Color.blue(col))

    private fun colorInt(hex: String): Int = try {
        Color.parseColor(hex)
    } catch (e: Exception) {
        WF_PURPLE
    }

    private fun hm(s: String): Int =
        (s.substringBefore(":").toIntOrNull() ?: 0) * 60 + (s.substringAfter(":").toIntOrNull() ?: 0)

    private fun battery(): Int = try {
        (ctx.getSystemService(Context.BATTERY_SERVICE) as BatteryManager)
            .getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    } catch (e: Exception) {
        -1
    }

    private fun lw(n: Int): String {
        val a = n % 100
        val b = n % 10
        return if (a in 11..14) "уроков" else when (b) {
            1 -> "урок"
            in 2..4 -> "урока"
            else -> "уроков"
        }
    }

    // ---------------- логика «сейчас / следующее» ----------------
    private fun status(all: List<Lesson>, nowMin: Int): Status {
        val timed = all.filter { !it.isAllDay }.sortedBy { hm(it.start) }
        val cur = timed.firstOrNull { hm(it.start) <= nowMin && nowMin < hm(it.end) }
        val nxt = timed.firstOrNull { it !== cur && hm(it.start) > nowMin }
        val past = timed.any { hm(it.end) <= nowMin }
        return Status(cur, nxt, cur == null && nxt != null && past)
    }

    /** Сколько минут (с округлением вверх) осталось до момента target (в минутах от полуночи). */
    private fun minsUntil(target: Int, nowMin: Int, sec: Int): Int =
        (((target - nowMin) * 60 - sec) + 59) / 60

    private fun dur(m: Int): String {
        val v = if (m < 1) 1 else m
        return if (v < 60) {
            "$v мин"
        } else {
            val h = v / 60
            val r = v % 60
            if (r == 0) "$h ч" else "$h ч $r мин"
        }
    }

    // ---------------- ambient ----------------
    private fun drawAmbient(c: Canvas, s: Float, t: ZonedDateTime) {
        val nowMin = t.hour * 60 + t.minute
        val st = status(lessons.filter { it.occursOn(t.toLocalDate()) }, nowMin)
        txt(c, "%02d:%02d".format(t.hour, t.minute), s / 2f, s * 0.56f, s * 0.26f, 0xFFD0D0D0.toInt(), normalFace, Paint.Align.CENTER)
        txt(
            c, t.format(dateFmt).replaceFirstChar { it.uppercase() },
            s / 2f, s * 0.67f, s * 0.06f, 0xFF808080.toInt(), normalFace, Paint.Align.CENTER
        )
        val cur = st.current
        val nxt = st.next
        val line = when {
            cur != null -> "Сейчас: " + cur.title
            nxt != null -> nxt.title + " через " + dur(minsUntil(hm(nxt.start), nowMin, 0))
            else -> ""
        }
        if (line.isNotEmpty()) {
            txt(c, line, s / 2f, s * 0.76f, s * 0.045f, 0xFF707070.toInt(), normalFace, Paint.Align.CENTER, maxW = s * 0.78f)
        }
    }

    // ---------------- интерактивный режим ----------------
    private fun drawInteractive(c: Canvas, s: Float, t: ZonedDateTime) {
        val nowMin = t.hour * 60 + t.minute
        val today = t.toLocalDate()
        val all = lessons.filter { it.occursOn(today) }
        val st = status(all, nowMin)

        // свечение справа сверху
        p.reset(); p.isAntiAlias = true
        p.shader = RadialGradient(s * 0.78f, s * 0.36f, s * 0.36f, 0x557C5CFF, 0x00000000, Shader.TileMode.CLAMP)
        c.drawCircle(s * 0.78f, s * 0.36f, s * 0.36f, p)

        // дуга прогресса учебного дня (08:00-18:00) по левому краю
        val sw = s * 0.012f
        val inset = sw / 2f + s * 0.008f
        val oval = RectF(inset, inset, s - inset, s - inset)
        stroke(WF_RING, sw)
        c.drawArc(oval, 100f, 170f, false, p)
        val prog = ((nowMin - 480) / 600f).coerceIn(0f, 1f)
        if (prog > 0f) {
            stroke(WF_PURPLE, sw)
            c.drawArc(oval, 270f - 170f * prog, 170f * prog, false, p)
        }

        // иконка календаря и дата
        fill(WF_LILAC)
        c.drawRoundRect(RectF(s * 0.465f, s * 0.055f, s * 0.535f, s * 0.115f), s * 0.014f, s * 0.014f, p)
        fill(WF_PURPLE)
        c.drawRoundRect(RectF(s * 0.465f, s * 0.055f, s * 0.535f, s * 0.075f), s * 0.014f, s * 0.014f, p)
        txt(
            c, t.format(dateFmt).replaceFirstChar { it.uppercase() },
            s / 2f, s * 0.168f, s * 0.062f, WF_SOFT, boldFace, Paint.Align.CENTER
        )

        // время
        var ts = s * 0.20f
        val hs = "%02d".format(t.hour)
        val ms = "%02d".format(t.minute)
        var wh = measure(hs, ts, heavyFace)
        var wc = measure(":", ts, heavyFace)
        var wm = measure(ms, ts, heavyFace)
        val maxTotal = s * 0.50f
        if (wh + wc + wm > maxTotal) {
            val k = maxTotal / (wh + wc + wm)
            ts *= k; wh *= k; wc *= k; wm *= k
        }
        val x0 = s * 0.15f
        val ty = s * 0.335f
        txt(c, hs, x0, ty, ts, Color.WHITE, heavyFace)
        txt(c, ":", x0 + wh, ty, ts, WF_COLON, heavyFace)
        txt(c, ms, x0 + wh + wc, ty, ts, WF_PURPLE, heavyFace)

        drawIllustration(c, s)

        // батарея
        val bat = battery()
        if (bat >= 0) {
            stroke(WF_DIM, s * 0.004f)
            c.drawRoundRect(RectF(s * 0.685f, s * 0.188f, s * 0.725f, s * 0.214f), s * 0.006f, s * 0.006f, p)
            fill(WF_DIM)
            c.drawRect(RectF(s * 0.69f, s * 0.193f, s * 0.69f + s * 0.03f * (bat / 100f), s * 0.209f), p)
            txt(c, "$bat%", s * 0.84f, s * 0.214f, s * 0.04f, WF_DIM, normalFace, Paint.Align.RIGHT)
        }

        // плашка «Сегодня • N уроков»
        val pillTxt = "Сегодня • " + (if (all.isEmpty()) "занятий нет" else "${all.size} ${lw(all.size)}")
        val pw = measure(pillTxt, s * 0.045f, normalFace)
        val pl = s * 0.15f
        val pr = pl + s * 0.055f + pw + s * 0.035f
        val pillRect = RectF(pl, s * 0.36f, pr, s * 0.425f)
        fill(WF_PILL)
        c.drawRoundRect(pillRect, s * 0.0325f, s * 0.0325f, p)
        stroke(WF_RING, s * 0.003f)
        c.drawRoundRect(pillRect, s * 0.0325f, s * 0.0325f, p)
        fill(WF_PURPLE)
        c.drawCircle(pl + s * 0.03f, s * 0.3925f, s * 0.01f, p)
        txt(c, pillTxt, pl + s * 0.055f, s * 0.407f, s * 0.045f, WF_SOFT, normalFace)
        hits.add(Hit(pillRect, "app"))

        // что сейчас и что дальше
        drawStatus(c, s, st, nowMin, t.second, all.isEmpty())

        // стрелки: слева «Файлы», справа «Даты»
        drawArrow(c, s, s * 0.075f, s * 0.52f, -1)
        drawArrow(c, s, s * 0.925f, s * 0.52f, 1)
        hits.add(Hit(RectF(0f, s * 0.40f, s * 0.16f, s * 0.64f), "files"))
        hits.add(Hit(RectF(s * 0.84f, s * 0.40f, s, s * 0.64f), "dates"))

        // точки-индикаторы
        fill(WF_PURPLE)
        c.drawCircle(s * 0.47f, s * 0.955f, s * 0.012f, p)
        fill(WF_DOT)
        c.drawCircle(s * 0.50f, s * 0.955f, s * 0.010f, p)
        c.drawCircle(s * 0.53f, s * 0.955f, s * 0.010f, p)
    }

    private fun drawStatus(c: Canvas, s: Float, st: Status, nowMin: Int, sec: Int, noLessons: Boolean) {
        val cur = st.current
        val nxt = st.next
        val cardH = s * 0.145f
        val top1 = s * 0.478f
        val top2 = s * 0.678f
        when {
            cur != null -> {
                val left = dur(minsUntil(hm(cur.end), nowMin, sec))
                header(c, s, s * 0.468f, "СЕЙЧАС", WF_GREEN, "ещё $left")
                drawCard(c, s, cur, top1, cardH)
                if (nxt != null) {
                    val gap = dur(minsUntil(hm(nxt.start), nowMin, sec))
                    header(c, s, s * 0.668f, "СЛЕДУЮЩИЙ", WF_LILAC, "через $gap")
                    drawCard(c, s, nxt, top2, cardH)
                } else {
                    txt(c, "Дальше занятий нет", s / 2f, s * 0.77f, s * 0.048f, WF_DIM, normalFace, Paint.Align.CENTER, maxW = s * 0.7f)
                }
            }
            nxt != null -> {
                header(c, s, s * 0.468f, "СЛЕДУЮЩЕЕ", WF_LILAC, "")
                drawCard(c, s, nxt, top1, cardH)
                val gap = dur(minsUntil(hm(nxt.start), nowMin, sec))
                txt(c, "через $gap", s / 2f, s * 0.745f, s * 0.085f, Color.WHITE, boldFace, Paint.Align.CENTER, maxW = s * 0.7f)
                txt(
                    c, if (st.between) "идёт перерыв" else "занятия ещё не начались",
                    s / 2f, s * 0.805f, s * 0.04f, WF_DIM, normalFace, Paint.Align.CENTER
                )
            }
            else -> {
                txt(
                    c, if (noLessons) "Сегодня занятий нет" else "Занятия закончились",
                    s / 2f, s * 0.64f, s * 0.058f, Color.WHITE, boldFace, Paint.Align.CENTER, maxW = s * 0.7f
                )
            }
        }
    }

    private fun header(c: Canvas, s: Float, y: Float, label: String, color: Int, right: String) {
        val left = s * 0.16f
        val rightX = s * 0.84f
        val rw = if (right.isNotEmpty()) measure(right, s * 0.04f, boldFace) else 0f
        txt(c, label, left, y, s * 0.034f, color, boldFace, maxW = (rightX - left) - rw - s * 0.02f)
        if (right.isNotEmpty()) {
            txt(c, right, rightX, y, s * 0.04f, Color.WHITE, boldFace, Paint.Align.RIGHT)
        }
    }

    private fun drawCard(c: Canvas, s: Float, l: Lesson, top: Float, h: Float) {
        val cy = top + h / 2f
        val dy = abs(cy - s / 2f)
        val half = sqrt(maxOf(0f, (s / 2f) * (s / 2f) - dy * dy))
        val pad = s * 0.035f
        // карточки не заходят под кнопки-стрелки по бокам
        val left = maxOf(s / 2f - half + pad, s * 0.15f)
        val right = minOf(s / 2f + half - pad, s * 0.85f)
        val rect = RectF(left, top, right, top + h)
        val col = colorInt(l.color)

        fill(WF_CARD)
        c.drawRoundRect(rect, s * 0.05f, s * 0.05f, p)
        fill(col)
        c.drawRoundRect(RectF(left, top, left + s * 0.022f, top + h), s * 0.011f, s * 0.011f, p)

        val tx = left + s * 0.06f
        val iconSz = s * 0.095f
        val iconL = right - s * 0.04f - iconSz
        val maxW = iconL - tx - s * 0.02f
        txt(c, l.timeLabel(), tx, top + h * 0.30f, s * 0.042f, WF_DIM, normalFace, maxW = maxW)
        txt(c, l.title, tx, top + h * 0.62f, s * 0.056f, Color.WHITE, boldFace, maxW = maxW)
        val room = roomLabel(l.room)
        if (room.isNotBlank()) {
            stroke(WF_LILAC, s * 0.006f)
            c.drawCircle(tx + s * 0.012f, top + h * 0.86f - s * 0.012f, s * 0.011f, p)
            txt(c, room, tx + s * 0.035f, top + h * 0.90f, s * 0.038f, WF_DIM, normalFace, maxW = maxW - s * 0.035f)
        }

        val ir = RectF(iconL, cy - iconSz / 2f, iconL + iconSz, cy + iconSz / 2f)
        fill(withAlpha(col, 90))
        c.drawRoundRect(ir, s * 0.025f, s * 0.025f, p)
        val glyph = if (l.emoji.isNotBlank()) l.emoji else l.title.take(1).uppercase()
        txt(c, glyph, ir.centerX(), ir.centerY() + s * 0.02f, s * 0.055f, Color.WHITE, boldFace, Paint.Align.CENTER)

        hits.add(Hit(rect, "app"))
    }

    private fun drawArrow(c: Canvas, s: Float, cx: Float, cy: Float, dir: Int) {
        fill(WF_BTN)
        c.drawCircle(cx, cy, s * 0.043f, p)
        stroke(Color.WHITE, s * 0.009f)
        val path = Path()
        val d = dir.toFloat()
        path.moveTo(cx + d * s * 0.010f, cy - s * 0.020f)
        path.lineTo(cx - d * s * 0.010f, cy)
        path.lineTo(cx + d * s * 0.010f, cy + s * 0.020f)
        c.drawPath(path, p)
    }

    private fun drawIllustration(c: Canvas, s: Float) {
        // календарь
        fill(0xFFD8D0FF.toInt())
        c.drawRoundRect(RectF(s * 0.66f, s * 0.25f, s * 0.87f, s * 0.41f), s * 0.025f, s * 0.025f, p)
        fill(WF_PURPLE)
        c.drawRoundRect(RectF(s * 0.66f, s * 0.25f, s * 0.87f, s * 0.285f), s * 0.025f, s * 0.025f, p)
        fill(0xFFB8B0F0.toInt())
        c.drawRoundRect(RectF(s * 0.70f, s * 0.225f, s * 0.715f, s * 0.265f), s * 0.007f, s * 0.007f, p)
        c.drawRoundRect(RectF(s * 0.815f, s * 0.225f, s * 0.83f, s * 0.265f), s * 0.007f, s * 0.007f, p)
        fill(WF_PURPLE)
        for (row in 0..1) {
            for (col in 0..2) {
                val x = s * (0.685f + col * 0.047f)
                val y = s * (0.30f + row * 0.04f)
                c.drawRoundRect(RectF(x, y, x + s * 0.035f, y + s * 0.03f), s * 0.006f, s * 0.006f, p)
            }
        }
        // часы
        fill(0xFF1E1B33.toInt())
        c.drawCircle(s * 0.85f, s * 0.405f, s * 0.045f, p)
        stroke(Color.WHITE, s * 0.006f)
        c.drawCircle(s * 0.85f, s * 0.405f, s * 0.045f, p)
        val hands = Path()
        hands.moveTo(s * 0.85f, s * 0.38f)
        hands.lineTo(s * 0.85f, s * 0.405f)
        hands.lineTo(s * 0.868f, s * 0.415f)
        c.drawPath(hands, p)
    }
}
KT_EOF

sed -i "s/PKG__/${WPKG}/g" "$WF"

# ---------- проверка ----------
chk() { grep -q "$1" "$2" || echo "!! $3"; }
chk 'private fun drawStatus' "$WF" 'не записан drawStatus'
chk 'fun initialOverlay'     "$WF" 'нет initialOverlay (MainActivity ссылается на неё)'
chk 'fun roomLabel'          "$(dirname "$WF")/Notifier.kt" 'нет roomLabel в Notifier.kt (нужен скрипт с полноэкранными напоминаниями)'

echo
echo 'Готово: циферблат показывает "Сейчас" / "Следующий" / перерыв с обратным отсчётом.'
echo '1) git add wear && git commit -m "Watch face: now/next lesson status" && git push'
echo '2) После сборки поставь wear-release.apk на часы: adb install -r wear-release.apk (ключ тот же, поверх).'
echo '3) Если циферблат уже выбран, он обновится сам; иначе: долгое нажатие на циферблат -> "Расписание".'
echo "Резервная копия старого файла: $BAK"
