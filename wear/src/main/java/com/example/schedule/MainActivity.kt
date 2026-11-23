@file:OptIn(ExperimentalFoundationApi::class)

package com.example.schedule

import android.graphics.Paint
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageVector
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

private const val RANGE = 30
private val RU: Locale = Locale("ru")

private fun curMin(): Int {
    val t = LocalTime.now()
    return t.hour * 60 + t.minute
}

private fun toMin(s: String): Int {
    val h = s.substringBefore(":").toIntOrNull() ?: 0
    val m = s.substringAfter(":").toIntOrNull() ?: 0
    return h * 60 + m
}

enum class Overlay { NONE, MENU, DATES, FILES, FILE }

// ======================= РЕНДЕР ФОРМУЛ (LaTeX -> читаемый текст) =======================
object MathText {
    private val simple = Regex("^-?[\\p{L}\\p{N}.]+\$")
    private val spaces = Regex("[ \\t]{2,}")

    private val symbols = mapOf(
        "cdot" to " * ", "times" to " × ", "div" to " ÷ ", "pm" to "±", "mp" to "∓",
        "leq" to "≤", "le" to "≤", "geq" to "≥", "ge" to "≥", "neq" to "≠", "ne" to "≠",
        "approx" to "≈", "equiv" to "≡", "infty" to "∞",
        "to" to "→", "rightarrow" to "→", "leftarrow" to "←", "Rightarrow" to "⇒", "Leftrightarrow" to "⇔",
        "ldots" to "...", "dots" to "...", "cdots" to "...",
        "degree" to "°", "circ" to "°", "angle" to "∠",
        "in" to "∈", "cup" to "∪", "cap" to "∩", "subset" to "⊂",
        "sum" to "Σ", "prod" to "Π", "int" to "∫", "partial" to "∂", "nabla" to "∇",
        "alpha" to "α", "beta" to "β", "gamma" to "γ", "delta" to "δ", "epsilon" to "ε",
        "theta" to "θ", "lambda" to "λ", "mu" to "μ", "pi" to "π", "rho" to "ρ",
        "sigma" to "σ", "tau" to "τ", "phi" to "φ", "omega" to "ω",
        "Delta" to "Δ", "Sigma" to "Σ", "Omega" to "Ω", "Pi" to "Π",
        "Phi" to "Φ", "Gamma" to "Γ", "Lambda" to "Λ", "Theta" to "Θ",
        "quad" to " ", "qquad" to " "
    )

    private val drop = setOf(
        "left", "right", "displaystyle", "textstyle", "scriptstyle",
        "mathrm", "mathbf", "mathit", "mathbb", "mathcal", "text", "textbf", "textit",
        "operatorname", "boldsymbol", "big", "Big", "bigg", "Bigg", "limits", "nolimits"
    )

    /** Содержимое {...} с учётом вложенности: (текст внутри, индекс после закрывающей скобки). */
    private fun group(s: String, start: Int): Pair<String, Int>? {
        if (start >= s.length || s[start] != '{') return null
        var depth = 0
        var i = start
        while (i < s.length) {
            if (s[i] == '{') depth++
            else if (s[i] == '}') {
                depth--
                if (depth == 0) return s.substring(start + 1, i) to i + 1
            }
            i++
        }
        return null
    }

    private fun skipSpaces(s: String, from: Int): Int {
        var j = from
        while (j < s.length && s[j] == ' ') j++
        return j
    }

    /** Обработка команды, начинающейся с '\\' в позиции start. Возвращает индекс продолжения. */
    private fun command(s: String, start: Int, sb: StringBuilder): Int {
        var j = start + 1
        while (j < s.length && s[j].isLetter()) j++
        val cmd = s.substring(start + 1, j)

        if (cmd.isEmpty()) {
            if (j >= s.length) return j
            when (s[j]) {
                ',', ';', ':', '!', ' ' -> sb.append(' ')
                '\\' -> sb.append('\n')
                '(', ')', '[', ']' -> {}
                else -> sb.append(s[j])
            }
            return j + 1
        }

        if (cmd == "frac" || cmd == "dfrac" || cmd == "tfrac") {
            val a = group(s, skipSpaces(s, j))
            if (a != null) {
                val b = group(s, skipSpaces(s, a.second))
                if (b != null) {
                    val num = convert(a.first).trim()
                    val den = convert(b.first).trim()
                    if (simple.matches(num) && simple.matches(den)) {
                        sb.append(num).append('/').append(den)
                    } else {
                        sb.append('(').append(num).append(") / (").append(den).append(')')
                    }
                    return b.second
                }
            }
            return j
        }

        if (cmd == "sqrt") {
            var k = j
            var idx = ""
            if (k < s.length && s[k] == '[') {
                val close = s.indexOf(']', k)
                if (close > 0) {
                    idx = s.substring(k + 1, close)
                    k = close + 1
                }
            }
            val g = if (k < s.length && s[k] == '{') group(s, k) else null
            if (g != null) {
                val inner = convert(g.first).trim()
                sb.append(idx).append('√').append(if (simple.matches(inner)) inner else "($inner)")
                return g.second
            }
            sb.append(idx).append('√')
            return k
        }

        val sym = symbols[cmd]
        if (sym != null) {
            sb.append(sym)
        } else if (cmd !in drop) {
            sb.append(cmd)   // sin, cos, log, lim ...
        }
        return j
    }

    private fun convert(s: String): String {
        val sb = StringBuilder()
        var i = 0
        while (i < s.length) {
            val ch = s[i]
            if (ch == '\\') {
                i = command(s, i, sb)
            } else if (ch == '^' || ch == '_') {
                val g = if (i + 1 < s.length && s[i + 1] == '{') group(s, i + 1) else null
                if (g != null) {
                    val inner = convert(g.first).trim()
                    sb.append(ch).append(if (simple.matches(inner)) inner else "($inner)")
                    i = g.second
                } else {
                    sb.append(ch)
                    i++
                }
            } else if (ch == '{' || ch == '}' || ch == '$') {
                i++
            } else {
                sb.append(ch)
                i++
            }
        }
        return sb.toString()
    }

    fun render(src: String): String =
        convert(src.replace("\r", "")).lines().joinToString("\n") { spaces.replace(it, " ").trim() }
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ScheduleRepository.init(this)
        FileStore.init(this)
        setContent { WearApp() }
    }
}

@Composable
fun WearApp() {
    val ctx = LocalContext.current
    val lessons by ScheduleRepository.lessons.collectAsState()
    val files by FileStore.files.collectAsState()
    var detail by remember { mutableStateOf<Lesson?>(null) }
    var overlay by remember { mutableStateOf(Overlay.NONE) }
    var openId by remember { mutableStateOf<String?>(null) }
    var nowMin by remember { mutableStateOf(curMin()) }
    val today = remember { LocalDate.now() }
    val pager = rememberPagerState(initialPage = RANGE) { RANGE * 2 + 1 }   // ±30 дней
    val scope = rememberCoroutineScope()

    // обновление шкалы времени раз в минуту
    LaunchedEffect(Unit) {
        while (true) {
            delay(60_000L)
            nowMin = curMin()
        }
    }

    BackHandler(enabled = detail != null || overlay != Overlay.NONE) {
        when (overlay) {
            Overlay.FILE -> overlay = Overlay.FILES
            Overlay.FILES, Overlay.DATES -> overlay = Overlay.MENU
            Overlay.MENU -> overlay = Overlay.NONE
            Overlay.NONE -> detail = null
        }
    }

    MaterialTheme {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            val d = detail
            if (d == null) {
                HorizontalPager(state = pager) { page ->
                    val date = today.plusDays((page - RANGE).toLong())
                    DayPage(
                        date, lessons, isToday = date == today, nowMin = nowMin,
                        onOpen = { detail = it }, onTitle = { overlay = Overlay.MENU }
                    )
                }
                // левый край: свайп слева направо открывает меню
                if (overlay == Overlay.NONE) {
                    Box(
                        Modifier.align(Alignment.CenterStart).fillMaxHeight().width(24.dp)
                            .pointerInput(Unit) {
                                var total = 0f
                                detectHorizontalDragGestures(
                                    onDragStart = { total = 0f },
                                    onDragEnd = { if (total > 40f) overlay = Overlay.MENU },
                                    onDragCancel = { total = 0f },
                                    onHorizontalDrag = { _, dx -> total += dx }
                                )
                            }
                    )
                }
                when (overlay) {
                    Overlay.MENU -> MenuPanel(
                        filesCount = files.size,
                        onDates = { overlay = Overlay.DATES },
                        onFiles = { overlay = Overlay.FILES }
                    )
                    Overlay.DATES -> DatesDrawer(today, pager.currentPage - RANGE) { i ->
                        overlay = Overlay.NONE
                        scope.launch { pager.animateScrollToPage(RANGE + i) }
                    }
                    Overlay.FILES -> FilesScreen(files) { f ->
                        openId = f.id
                        overlay = Overlay.FILE
                    }
                    Overlay.FILE -> {
                        val f = files.firstOrNull { it.id == openId }
                        if (f != null) {
                            FileViewer(f) {
                                FileStore.delete(ctx, f.id)
                                overlay = Overlay.FILES
                            }
                        } else {
                            FilesScreen(files) { x ->
                                openId = x.id
                                overlay = Overlay.FILE
                            }
                        }
                    }
                    Overlay.NONE -> {}
                }
            } else {
                DetailScreen(d) { detail = null }
            }
        }
    }
}

// ======================= МЕНЮ (2 кнопки) =======================
@Composable
fun MenuButton(icon: ImageVector, label: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(Pal.Card)
            .clickable(onClick = onClick).padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, tint = Pal.Lilac, modifier = Modifier.size(22.dp))
        Text(
            label, color = Pal.Text, fontSize = 16.sp, fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(start = 12.dp)
        )
    }
}

@Composable
fun MenuPanel(filesCount: Int, onDates: () -> Unit, onFiles: () -> Unit) {
    Box(
        Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.96f)).pointerInput(Unit) {},
        contentAlignment = Alignment.Center
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 32.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            MenuButton(Icons.Filled.CalendarMonth, "Даты", onDates)
            MenuButton(Icons.Filled.Description, if (filesCount > 0) "Файлы ($filesCount)" else "Файлы", onFiles)
        }
    }
}

@Composable
fun DatesDrawer(today: LocalDate, current: Int, onPick: (Int) -> Unit) {
    val fmt = remember { DateTimeFormatter.ofPattern("EEE, d MMM", RU) }
    Box(
        Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.96f)).pointerInput(Unit) {}
    ) {
        ScalingLazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = 36.dp, bottom = 36.dp, start = 16.dp, end = 16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            item {
                Text(
                    "Выбор даты", color = Pal.Dim, fontSize = 13.sp,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
                )
            }
            items((0..6).toList()) { i ->
                val d = today.plusDays(i.toLong())
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                        .background(if (i == current) Pal.Purple else Pal.Card)
                        .clickable { onPick(i) }
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        d.format(fmt), color = Pal.Text, fontSize = 15.sp,
                        fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)
                    )
                    if (i == 0) Text("сегодня", color = Pal.Dim, fontSize = 11.sp)
                }
            }
        }
    }
}

// ======================= ФАЙЛЫ =======================
@Composable
fun FilesScreen(files: List<WearFile>, onOpen: (WearFile) -> Unit) {
    val list = remember(files) { files.reversed() }   // новые сверху
    Box(Modifier.fillMaxSize().background(Color.Black).pointerInput(Unit) {}) {
        ScalingLazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = 36.dp, bottom = 36.dp, start = 16.dp, end = 16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            item {
                Text(
                    "Файлы", color = Pal.Dim, fontSize = 13.sp,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
                )
            }
            if (list.isEmpty()) {
                item {
                    Text(
                        "Файлов нет", color = Pal.Text, fontSize = 15.sp,
                        textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
                    )
                }
            }
            items(list) { f ->
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Pal.Card)
                        .clickable { onOpen(f) }
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        f.name, color = Pal.Text, fontSize = 15.sp, fontWeight = FontWeight.Bold,
                        maxLines = 1, modifier = Modifier.weight(1f)
                    )
                    Text(f.time, color = Pal.Dim, fontSize = 12.sp)
                }
            }
        }
    }
}

@Composable
fun FileViewer(f: WearFile, onDelete: () -> Unit) {
    val lines = remember(f.text) { MathText.render(f.text).split("\n") }
    Box(Modifier.fillMaxSize().background(Color.Black).pointerInput(Unit) {}) {
        ScalingLazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = 36.dp, bottom = 44.dp, start = 18.dp, end = 18.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            item {
                Text(
                    "${f.name} · ${f.time}", color = Pal.Dim, fontSize = 12.sp,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
                )
            }
            items(lines) { line ->
                Text(
                    if (line.isEmpty()) " " else line,
                    color = Pal.Text, fontSize = 15.sp, modifier = Modifier.fillMaxWidth()
                )
            }
            item {
                Box(
                    Modifier.padding(top = 8.dp).clip(RoundedCornerShape(20.dp)).background(Pal.Card)
                        .clickable(onClick = onDelete)
                        .padding(horizontal = 24.dp, vertical = 8.dp)
                ) {
                    Text("Удалить", color = Color(0xFFFF6B6B), fontSize = 13.sp)
                }
            }
        }
    }
}

// ======================= ШКАЛА ВРЕМЕНИ =======================
@Composable
fun TimeScale(lessons: List<Lesson>, isToday: Boolean, nowMin: Int, modifier: Modifier) {
    val hourPaint = remember {
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.parseColor("#9B98AD")
            textAlign = Paint.Align.RIGHT
        }
    }
    val timePaint = remember {
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.RED
            textAlign = Paint.Align.RIGHT
            isFakeBoldText = true
        }
    }
    Canvas(modifier) {
        val startMin = 8 * 60
        val endMin = 18 * 60
        val total = (endMin - startMin).toFloat()
        val h = size.height
        fun y(min: Int): Float = (min - startMin) / total * h

        hourPaint.textSize = 9.sp.toPx()
        timePaint.textSize = 9.sp.toPx()
        val axisX = 17.dp.toPx()
        val axisColor = Color(0xFF3A3A44)

        drawLine(axisColor, Offset(axisX, 0f), Offset(axisX, h), strokeWidth = 1.dp.toPx())
        for (hr in 8..18 step 2) {
            val yy = y(hr * 60)
            drawLine(axisColor, Offset(axisX - 3.dp.toPx(), yy), Offset(axisX + 3.dp.toPx(), yy), strokeWidth = 1.dp.toPx())
            drawContext.canvas.nativeCanvas.drawText("%02d".format(hr), axisX - 5.dp.toPx(), yy + 3.dp.toPx(), hourPaint)
        }

        lessons.forEach { l ->
            if (l.isAllDay) return@forEach
            val s = toMin(l.start)
            val e = toMin(l.end)
            val cs = maxOf(s, startMin)
            val ce = minOf(e, endMin)
            if (ce <= cs) return@forEach
            val current = isToday && nowMin >= s && nowMin < e
            val col = if (current) Color(0xFF8A8A8A) else parseColor(l.color)
            val top = y(cs)
            val hh = (y(ce) - top).coerceAtLeast(2.dp.toPx())
            drawRoundRect(
                color = col,
                topLeft = Offset(axisX + 3.dp.toPx(), top),
                size = Size(10.dp.toPx(), hh),
                cornerRadius = CornerRadius(3.dp.toPx())
            )
        }

        if (isToday && nowMin in startMin..endMin) {
            val yy = y(nowMin)
            val tagW = 24.dp.toPx()
            drawRect(Color.Black, Offset(0f, yy - 6.dp.toPx()), Size(tagW, 12.dp.toPx()))
            drawContext.canvas.nativeCanvas.drawText(
                "%02d:%02d".format(nowMin / 60, nowMin % 60),
                tagW, yy + 3.dp.toPx(), timePaint
            )
            drawLine(Color.Red, Offset(tagW, yy), Offset(size.width, yy), strokeWidth = 1.5.dp.toPx())
        }
    }
}

@Composable
fun DayPage(
    date: LocalDate, all: List<Lesson>, isToday: Boolean, nowMin: Int,
    onOpen: (Lesson) -> Unit, onTitle: () -> Unit
) {
    val day = remember(all, date) {
        all.filter { it.occursOn(date) }
            .sortedWith(compareByDescending<Lesson> { it.isAllDay }.thenBy { it.start })
    }
    val title = date.format(DateTimeFormatter.ofPattern("EEE, d MMM", RU))
    Box(Modifier.fillMaxSize()) {
        if (day.isEmpty()) {
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Filled.EventAvailable, null, tint = Pal.Lilac, modifier = Modifier.size(44.dp))
                Spacer(Modifier.height(8.dp))
                Text("Занятий нет", color = Pal.Text, fontSize = 16.sp, textAlign = TextAlign.Center)
            }
        } else {
            ScalingLazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(top = 56.dp, bottom = 36.dp, start = 68.dp, end = 12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) { items(day) { WearCard(it) { onOpen(it) } } }
        }
        TimeScale(
            lessons = day, isToday = isToday, nowMin = nowMin,
            modifier = Modifier.align(Alignment.CenterStart).padding(start = 24.dp)
                .width(40.dp).fillMaxHeight(0.56f)
        )
        Text(
            "‹   $title   ›", color = Pal.Text, fontSize = 14.sp, fontWeight = FontWeight.Medium,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 20.dp).clickable(onClick = onTitle)
        )
    }
}

@Composable
fun WearCard(l: Lesson, onClick: () -> Unit) {
    val col = parseColor(l.color)
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Pal.Card)
            .clickable(onClick = onClick).padding(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(4.dp).height(32.dp).clip(RoundedCornerShape(2.dp)).background(col))
        Column(Modifier.weight(1f).padding(start = 6.dp)) {
            Text(l.timeLabel(), color = Pal.Dim, fontSize = 11.sp, maxLines = 1)
            Text(l.title, color = Pal.Text, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        }
        Box(
            Modifier.size(26.dp).clip(RoundedCornerShape(8.dp)).background(col.copy(alpha = 0.3f)),
            contentAlignment = Alignment.Center
        ) {
            if (l.emoji.isNotBlank()) Text(l.emoji, fontSize = 14.sp)
            else Icon(iconFor(l.icon), null, tint = col, modifier = Modifier.size(16.dp))
        }
    }
}

@Composable
fun DetailScreen(l: Lesson, onBack: () -> Unit) {
    val col = parseColor(l.color)
    Column(
        Modifier.fillMaxSize().padding(horizontal = 26.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(col),
            contentAlignment = Alignment.Center
        ) {
            if (l.emoji.isNotBlank()) Text(l.emoji, fontSize = 24.sp)
            else Icon(iconFor(l.icon), null, tint = Color.White, modifier = Modifier.size(28.dp))
        }
        Spacer(Modifier.height(4.dp))
        Text(
            l.title, color = Pal.Text, fontSize = 20.sp, fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center, maxLines = 2
        )
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Schedule, null, tint = Pal.Dim, modifier = Modifier.size(16.dp))
            Text("  ${l.timeLabel()}", color = Pal.Text, fontSize = 14.sp)
        }
        if (l.room.isNotBlank()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.LocationOn, null, tint = Pal.Dim, modifier = Modifier.size(16.dp))
                Text("  ${l.room}", color = Pal.Text, fontSize = 14.sp, maxLines = 1)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Repeat, null, tint = col, modifier = Modifier.size(16.dp))
            Text("  ${recurrenceStatus(l.recurrence)}", color = col, fontSize = 14.sp)
        }
        Spacer(Modifier.height(8.dp))
        Box(
            Modifier.clip(RoundedCornerShape(20.dp)).background(Pal.Card).clickable(onClick = onBack)
                .padding(horizontal = 28.dp, vertical = 6.dp)
        ) {
            Text("Назад", color = Pal.Text, fontSize = 13.sp)
        }
    }
}
