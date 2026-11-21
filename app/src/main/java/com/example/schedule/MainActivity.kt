@file:OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)

package com.example.schedule

import android.content.res.Configuration
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale

const val MONTH_BASE = 12
const val MONTH_COUNT = 25   // ±12 месяцев

val RU: Locale = Locale("ru")
val DAYS = listOf("Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс")
val EMOJIS = listOf(
    "📚", "🧮", "🔬", "💻", "🎨", "🎵", "⚽", "🌍",
    "📝", "🧪", "🏛️", "🧬", "🗣️", "🎭", "⏰", "⭐"
)

// ======================= ТЕМА =======================
class AppColors(
    val bg: Color, val text: Color, val sub: Color, val accent: Color,
    val card: Color, val sat: Color, val sun: Color, val dark: Boolean
)

val LightColors = AppColors(
    Color(0xFFFFFFFF), Color(0xFF000000), Color(0xFF757575), Color(0xFF1A73E8),
    Color(0xFFF5F5F5), Color(0xFF1A73E8), Color(0xFFE53935), false
)
val DarkColors = AppColors(
    Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFF9E9E9E), Color(0xFF1A73E8),
    Color(0xFF1E1E1E), Color(0xFF5C9DFF), Color(0xFFFF6B6B), true
)
val LocalAppColors = staticCompositionLocalOf { LightColors }
val C: AppColors
    @Composable @ReadOnlyComposable get() = LocalAppColors.current

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Locale.setDefault(RU)
        val repo = ScheduleRepository(this)
        setContent {
            val dark = isSystemInDarkTheme()
            val c = if (dark) DarkColors else LightColors
            val scheme = if (dark) darkColorScheme(
                primary = c.accent, onPrimary = Color.White, background = c.bg,
                onBackground = c.text, surface = c.bg, onSurface = c.text,
                surfaceVariant = c.card, onSurfaceVariant = c.sub
            ) else lightColorScheme(
                primary = c.accent, onPrimary = Color.White, background = c.bg,
                onBackground = c.text, surface = c.bg, onSurface = c.text,
                surfaceVariant = c.card, onSurfaceVariant = c.sub
            )
            SideEffect {
                window.statusBarColor = c.bg.toArgb()
                window.navigationBarColor = c.bg.toArgb()
                val ctl = WindowCompat.getInsetsController(window, window.decorView)
                ctl.isAppearanceLightStatusBars = !dark
                ctl.isAppearanceLightNavigationBars = !dark
            }
            CompositionLocalProvider(LocalAppColors provides c) {
                MaterialTheme(colorScheme = scheme) {
                    Surface(Modifier.fillMaxSize(), color = c.bg, contentColor = c.text) {
                        App(repo)
                    }
                }
            }
        }
    }
}

// ======================= КОРНЕВОЙ ЭКРАН =======================
@Composable
fun App(repo: ScheduleRepository) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val today = remember { LocalDate.now() }
    var lessons by remember { mutableStateOf(repo.load()) }
    var selected by remember { mutableStateOf(today) }
    var editing by remember { mutableStateOf<Lesson?>(null) }
    var editDate by remember { mutableStateOf(today) }
    var pendingSave by remember { mutableStateOf<Lesson?>(null) }
    var pendingDelete by remember { mutableStateOf(false) }

    fun sync(list: List<Lesson>, notify: Boolean) {
        scope.launch {
            val r = DataSyncService.send(ctx, LessonJson.toJson(list))
            if (notify) {
                val msg = when {
                    r > 0 -> "Отправлено на часы"
                    r == -2 -> "Слишком много событий для отправки"
                    else -> "Часы не найдены"
                }
                Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun persist(list: List<Lesson>) {
        lessons = list
        repo.save(list)
        sync(list, true)
    }

    LaunchedEffect(Unit) { sync(lessons, false) }
    BackHandler(enabled = editing != null) { editing = null }

    Box(Modifier.fillMaxSize()) {
        MainScreen(
            lessons = lessons, today = today, selected = selected,
            onSelect = { selected = it },
            onOpen = { l, d -> editDate = d; editing = l },
            onNew = {
                editDate = selected
                editing = Lesson(id = 0L, title = "", date = selected.toString(), color = PALETTE[0])
            },
            onManualSync = { sync(lessons, true) }
        )

        editing?.let { orig ->
            key(orig.id) {
                EditScreen(
                    init = orig, initDate = editDate,
                    onSave = { edited ->
                        when {
                            orig.id == 0L -> {
                                persist(lessons + edited.copy(id = System.currentTimeMillis()))
                                editing = null
                            }
                            orig.recurrence == "NONE" -> {
                                persist(lessons.map { if (it.id == orig.id) edited else it })
                                editing = null
                            }
                            else -> pendingSave = edited
                        }
                    },
                    onDelete = {
                        if (orig.recurrence == "NONE") {
                            persist(lessons.filter { it.id != orig.id })
                            editing = null
                        } else {
                            pendingDelete = true
                        }
                    },
                    onCancel = { editing = null }
                )
            }
        }
    }

    val orig = editing
    val ps = pendingSave
    if (ps != null && orig != null) {
        AlertDialog(
            onDismissRequest = { pendingSave = null },
            title = { Text("Изменить событие") },
            text = { Text("Это повторяющееся событие.") },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    TextButton(onClick = {
                        val one = ps.copy(id = System.currentTimeMillis(), recurrence = "NONE", exceptions = emptyList())
                        persist(
                            lessons.map {
                                if (it.id == orig.id) it.copy(exceptions = it.exceptions + editDate.toString()) else it
                            } + one
                        )
                        pendingSave = null; editing = null
                    }) { Text("Изменить только это") }
                    TextButton(onClick = {
                        val delta = ChronoUnit.DAYS.between(editDate, parseDate(ps.date))
                        val base = parseDate(orig.date).plusDays(delta)
                        persist(
                            lessons.map {
                                if (it.id == orig.id) ps.copy(date = base.toString(), exceptions = orig.exceptions) else it
                            }
                        )
                        pendingSave = null; editing = null
                    }) { Text("Изменить всю серию") }
                    TextButton(onClick = { pendingSave = null }) { Text("Отмена") }
                }
            }
        )
    }
    if (pendingDelete && orig != null) {
        AlertDialog(
            onDismissRequest = { pendingDelete = false },
            title = { Text("Удалить событие") },
            text = { Text("Это повторяющееся событие.") },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    TextButton(onClick = {
                        persist(
                            lessons.map {
                                if (it.id == orig.id) it.copy(exceptions = it.exceptions + editDate.toString()) else it
                            }
                        )
                        pendingDelete = false; editing = null
                    }) { Text("Удалить это событие") }
                    TextButton(onClick = {
                        persist(lessons.filter { it.id != orig.id })
                        pendingDelete = false; editing = null
                    }) { Text("Удалить всю серию") }
                    TextButton(onClick = { pendingDelete = false }) { Text("Отмена") }
                }
            }
        )
    }
}

// ======================= ГЛАВНЫЙ ЭКРАН =======================
@Composable
fun MainScreen(
    lessons: List<Lesson>, today: LocalDate, selected: LocalDate,
    onSelect: (LocalDate) -> Unit, onOpen: (Lesson, LocalDate) -> Unit,
    onNew: () -> Unit, onManualSync: () -> Unit
) {
    val c = C
    val scope = rememberCoroutineScope()
    val anchorMonth = remember { YearMonth.from(today) }
    val pager = rememberPagerState(initialPage = MONTH_BASE) { MONTH_COUNT }
    var frac by remember { mutableFloatStateOf(0f) }          // 0 = свёрнут, 1 = развёрнут
    var searching by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    val selNow by rememberUpdatedState(selected)
    val onSelectNow by rememberUpdatedState(onSelect)
    val jobRef = remember { arrayOfNulls<Job>(1) }

    BackHandler(enabled = searching) { searching = false; query = "" }

    // свайп месяца -> выбранная дата
    LaunchedEffect(pager) {
        snapshotFlow { pager.settledPage }.collect { p ->
            val ym = anchorMonth.plusMonths((p - MONTH_BASE).toLong())
            val s = selNow
            if (YearMonth.from(s) != ym) {
                onSelectNow(ym.atDay(minOf(s.dayOfMonth, ym.lengthOfMonth())))
            }
        }
    }
    // выбранная дата -> страница месяца
    LaunchedEffect(selected) {
        val target = (MONTH_BASE + ChronoUnit.MONTHS.between(anchorMonth, YearMonth.from(selected))).toInt()
        if (target in 0 until MONTH_COUNT && pager.currentPage != target) pager.animateScrollToPage(target)
    }

    fun settle(target: Float) {
        jobRef[0]?.cancel()
        jobRef[0] = scope.launch {
            animate(frac, target, animationSpec = tween(220)) { v, _ -> frac = v }
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(c.bg)) {
        val collapsedCell = 46.dp
        val raw = (maxHeight - 56.dp - 28.dp) / 6
        val expandedCell = if (raw > collapsedCell) raw else collapsedCell
        val cellH = lerp(collapsedCell, expandedCell, frac)
        val rangePx = with(LocalDensity.current) { (expandedCell - collapsedCell).toPx() }.coerceAtLeast(1f)
        val strips by remember { derivedStateOf { frac > 0.5f } }

        val dragState = rememberDraggableState { d ->
            jobRef[0]?.cancel()
            frac = (frac + d / rangePx).coerceIn(0f, 1f)
        }
        val dragMod = Modifier.draggable(
            state = dragState, orientation = Orientation.Vertical,
            onDragStopped = { v ->
                settle(if (v > 600f) 1f else if (v < -600f) 0f else if (frac > 0.5f) 1f else 0f)
            }
        )
        val nested = remember(rangePx) {
            object : NestedScrollConnection {
                private fun shift(dy: Float): Float {
                    val nf = (frac + dy / rangePx).coerceIn(0f, 1f)
                    val used = (nf - frac) * rangePx
                    frac = nf
                    return used
                }
                override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset =
                    if (available.y < 0f && frac > 0f) Offset(0f, shift(available.y)) else Offset.Zero
                override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset =
                    if (available.y > 0f && frac < 1f) Offset(0f, shift(available.y)) else Offset.Zero
                override suspend fun onPreFling(available: Velocity): Velocity {
                    if (frac > 0f && frac < 1f) settle(if (frac > 0.5f) 1f else 0f)
                    return Velocity.Zero
                }
            }
        }

        val dayList = remember(lessons, selected) {
            lessons.filter { it.occursOn(selected) }
                .sortedWith(compareByDescending<Lesson> { it.isAllDay }.thenBy { it.start })
        }
        val results = remember(lessons, query) {
            if (query.isBlank()) emptyList()
            else lessons.filter { it.title.contains(query, true) || it.room.contains(query, true) }
                .sortedBy { it.date }
        }

        Column(Modifier.fillMaxSize()) {
            if (searching) {
                val fr = remember { FocusRequester() }
                LaunchedEffect(Unit) { fr.requestFocus() }
                Row(
                    Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = { searching = false; query = "" }) {
                        Icon(Icons.Filled.ArrowBack, null, tint = c.text)
                    }
                    TextField(
                        value = query, onValueChange = { query = it },
                        placeholder = { Text("Поиск событий") }, singleLine = true,
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = Color.Transparent,
                            unfocusedContainerColor = Color.Transparent,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent
                        ),
                        modifier = Modifier.weight(1f).focusRequester(fr)
                    )
                }
                LazyColumn(
                    Modifier.fillMaxWidth().weight(1f),
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 88.dp)
                ) {
                    if (query.isNotBlank() && results.isEmpty()) {
                        item { Text("Ничего не найдено", color = c.sub, modifier = Modifier.padding(8.dp)) }
                    }
                    items(results, key = { it.id }) { l ->
                        val d = parseDate(l.date)
                        LessonCard(l, d.format(DateTimeFormatter.ofPattern("d MMM yyyy", RU))) {
                            onSelect(d)
                            onOpen(l, d)
                            searching = false; query = ""
                        }
                    }
                }
            } else {
                // ---------- верхняя панель ----------
                val shown = anchorMonth.plusMonths((pager.currentPage - MONTH_BASE).toLong())
                val title = shown.month.getDisplayName(TextStyle.FULL_STANDALONE, RU)
                    .replaceFirstChar { it.uppercase() } + " " + shown.year
                Row(
                    Modifier.fillMaxWidth().height(56.dp).padding(start = 16.dp, end = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        title, fontSize = 22.sp, fontWeight = FontWeight.Bold,
                        color = c.text, modifier = Modifier.weight(1f)
                    )
                    IconButton(onClick = { searching = true }) {
                        Icon(Icons.Filled.Search, null, tint = c.text)
                    }
                    Box(
                        Modifier.padding(start = 4.dp).size(34.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .border(1.5.dp, c.text, RoundedCornerShape(8.dp))
                            .combinedClickable(onClick = { onSelect(today) }, onLongClick = onManualSync),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("${today.dayOfMonth}", color = c.text, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    }
                }
                // ---------- дни недели ----------
                Row(Modifier.fillMaxWidth().height(28.dp), verticalAlignment = Alignment.CenterVertically) {
                    DAYS.forEachIndexed { i, d ->
                        Text(
                            d, Modifier.weight(1f), textAlign = TextAlign.Center, fontSize = 13.sp,
                            color = when (i) { 5 -> c.sat; 6 -> c.sun; else -> c.sub }
                        )
                    }
                }
                // ---------- сетка месяцев ----------
                Box(Modifier.fillMaxWidth().height(cellH * 6).then(dragMod).clipToBounds()) {
                    HorizontalPager(state = pager, modifier = Modifier.fillMaxSize()) { page ->
                        MonthGrid(
                            anchorMonth.plusMonths((page - MONTH_BASE).toLong()),
                            lessons, selected, today, cellH, strips, onSelect
                        )
                    }
                }
                // ---------- список событий ----------
                Column(Modifier.weight(1f).fillMaxWidth().clipToBounds()) {
                    Row(
                        Modifier.fillMaxWidth().height(48.dp).then(dragMod).padding(start = 16.dp, end = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "${selected.dayOfMonth} ${selected.dayOfWeek.getDisplayName(TextStyle.SHORT, RU)}",
                            fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.text,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(onClick = onNew) { Icon(Icons.Filled.Add, null, tint = c.accent) }
                    }
                    LazyColumn(
                        Modifier.fillMaxWidth().weight(1f).nestedScroll(nested),
                        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 88.dp)
                    ) {
                        if (dayList.isEmpty()) {
                            item { Text("Нет событий", color = c.sub, modifier = Modifier.padding(vertical = 8.dp)) }
                        }
                        items(dayList, key = { it.id }) { l -> LessonCard(l, null) { onOpen(l, selected) } }
                    }
                }
            }
        }

        if (!searching) {
            Box(
                Modifier.align(Alignment.BottomEnd).padding(16.dp).size(56.dp)
                    .shadow(6.dp, CircleShape).clip(CircleShape).background(c.accent)
                    .clickable(onClick = onNew),
                contentAlignment = Alignment.Center
            ) { Icon(Icons.Filled.Add, null, tint = Color.White) }
        }
    }
}

@Composable
fun MonthGrid(
    ym: YearMonth, lessons: List<Lesson>, selected: LocalDate, today: LocalDate,
    cellH: Dp, strips: Boolean, onSelect: (LocalDate) -> Unit
) {
    val offset = ym.atDay(1).dayOfWeek.value - 1
    val len = ym.lengthOfMonth()
    val byDay: Map<Int, List<Lesson>> = remember(lessons, ym) {
        val m = HashMap<Int, List<Lesson>>()
        for (n in 1..len) {
            val d = ym.atDay(n)
            val l = lessons.filter { it.occursOn(d) }
            if (l.isNotEmpty()) m[n] = l.sortedBy { it.start }
        }
        m
    }
    val selDay = if (YearMonth.from(selected) == ym) selected.dayOfMonth else -1
    val todayDay = if (YearMonth.from(today) == ym) today.dayOfMonth else -1

    LazyVerticalGrid(
        columns = GridCells.Fixed(7),
        modifier = Modifier.fillMaxSize(),
        userScrollEnabled = false
    ) {
        items(42) { i ->
            val n = i - offset + 1
            if (n in 1..len) {
                DayCell(n, i % 7, byDay[n], n == selDay, n == todayDay, cellH, strips) { onSelect(ym.atDay(n)) }
            } else {
                Spacer(Modifier.height(cellH))
            }
        }
    }
}

@Composable
fun DayCell(
    n: Int, col: Int, list: List<Lesson>?, sel: Boolean, isToday: Boolean,
    cellH: Dp, strips: Boolean, onClick: () -> Unit
) {
    val c = C
    val numColor = when {
        isToday -> Color.White
        col == 5 -> c.sat
        col == 6 -> c.sun
        else -> c.text
    }
    Column(
        Modifier.fillMaxWidth().height(cellH).clickable(onClick = onClick)
            .padding(horizontal = 1.dp, vertical = 3.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            Modifier.size(26.dp).clip(CircleShape).background(
                when {
                    isToday -> c.accent
                    sel -> c.accent.copy(alpha = 0.18f)
                    else -> Color.Transparent
                }
            ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                "$n", fontSize = 14.sp, color = numColor,
                fontWeight = if (isToday || sel) FontWeight.Bold else FontWeight.Normal
            )
        }
        if (list != null) {
            if (strips) {
                val max = ((cellH.value - 36f) / 16f).toInt().coerceIn(0, 4)
                Spacer(Modifier.height(2.dp))
                list.take(max).forEach { l ->
                    Box(
                        Modifier.fillMaxWidth().padding(vertical = 1.dp).height(14.dp)
                            .clip(RoundedCornerShape(3.dp)).background(parseColor(l.color))
                            .padding(horizontal = 3.dp),
                        contentAlignment = Alignment.CenterStart
                    ) {
                        Text(l.title, fontSize = 9.sp, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            } else {
                Spacer(Modifier.height(3.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    list.take(3).forEach { l ->
                        Box(Modifier.size(4.dp).clip(CircleShape).background(parseColor(l.color)))
                    }
                }
            }
        }
    }
}

@Composable
fun LessonCard(l: Lesson, dateLabel: String?, onClick: () -> Unit) {
    val c = C
    val col = parseColor(l.color)
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp).clip(RoundedCornerShape(12.dp))
            .background(c.card).clickable(onClick = onClick).height(IntrinsicSize.Min),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(5.dp).fillMaxHeight().background(col))
        Column(Modifier.weight(1f).padding(12.dp)) {
            Text(
                (if (l.emoji.isNotBlank()) l.emoji + " " else "") + l.title,
                fontSize = 16.sp, fontWeight = FontWeight.Medium, color = c.text
            )
            Text(
                if (dateLabel != null) "$dateLabel · ${l.timeLabel()}" else l.timeLabel(),
                fontSize = 13.sp, color = c.sub
            )
            if (l.room.isNotBlank()) Text(l.room, fontSize = 12.sp, color = c.sub)
        }
        if (l.recurrence != "NONE") {
            Icon(Icons.Filled.Repeat, null, tint = c.sub, modifier = Modifier.padding(end = 12.dp).size(18.dp))
        }
    }
}

// ======================= СОЗДАНИЕ / РЕДАКТИРОВАНИЕ =======================
@Composable
fun EditScreen(
    init: Lesson, initDate: LocalDate,
    onSave: (Lesson) -> Unit, onDelete: () -> Unit, onCancel: () -> Unit
) {
    val c = C
    var title by remember { mutableStateOf(init.title) }
    var emoji by remember { mutableStateOf(init.emoji) }
    var color by remember { mutableStateOf(init.color) }
    var allDay by remember { mutableStateOf(init.isAllDay) }
    var date by remember { mutableStateOf(initDate) }
    var sh by remember { mutableStateOf(init.start.substringBefore(":").toIntOrNull() ?: 8) }
    var sm by remember { mutableStateOf(init.start.substringAfter(":").toIntOrNull() ?: 30) }
    var eh by remember { mutableStateOf(init.end.substringBefore(":").toIntOrNull() ?: 9) }
    var em by remember { mutableStateOf(init.end.substringAfter(":").toIntOrNull() ?: 15) }
    var room by remember { mutableStateOf(init.room) }
    var recurrence by remember { mutableStateOf(init.recurrence) }
    var showEmoji by remember { mutableStateOf(false) }
    var showColors by remember { mutableStateOf(false) }
    var showDate by remember { mutableStateOf(false) }
    var showTime by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }

    val save = {
        val s = "%02d:%02d".format(sh, sm)
        var e = "%02d:%02d".format(eh, em)
        if (e < s) e = s
        onSave(
            init.copy(
                title = title.trim().ifBlank { "Событие" }, emoji = emoji, color = color,
                isAllDay = allDay, date = date.toString(), start = s, end = e,
                room = room.trim(), recurrence = recurrence
            )
        )
    }

    Column(Modifier.fillMaxSize().background(c.bg).pointerInput(Unit) {}) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(
                if (init.id == 0L) "Новое событие" else "Событие",
                fontSize = 22.sp, fontWeight = FontWeight.Bold, color = c.text,
                modifier = Modifier.padding(top = 8.dp)
            )

            // название + эмодзи + цвет
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    title, { title = it }, label = { Text("Название") },
                    singleLine = true, modifier = Modifier.weight(1f)
                )
                Box(
                    Modifier.size(40.dp).clip(CircleShape).background(c.card)
                        .clickable { showEmoji = !showEmoji; showColors = false },
                    contentAlignment = Alignment.Center
                ) {
                    if (emoji.isBlank()) Icon(Icons.Filled.EmojiEmotions, null, tint = c.sub)
                    else Text(emoji, fontSize = 22.sp)
                }
                Box(
                    Modifier.size(32.dp).clip(CircleShape).background(parseColor(color))
                        .clickable { showColors = !showColors; showEmoji = false }
                )
            }
            if (showEmoji) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    EMOJIS.chunked(8).forEach { chunk ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            chunk.forEach { e ->
                                Text(
                                    e, fontSize = 24.sp,
                                    modifier = Modifier.clip(RoundedCornerShape(8.dp))
                                        .clickable { emoji = e; showEmoji = false }.padding(4.dp)
                                )
                            }
                        }
                    }
                    TextButton(onClick = { emoji = ""; showEmoji = false }) { Text("Убрать эмодзи") }
                }
            }
            if (showColors) {
                Row(
                    Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    PALETTE.forEach { hex ->
                        Box(
                            Modifier.size(36.dp).clip(CircleShape).background(parseColor(hex))
                                .clickable { color = hex; showColors = false },
                            contentAlignment = Alignment.Center
                        ) {
                            if (hex == color) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(20.dp))
                        }
                    }
                }
            }

            // весь день
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.AccessTime, null, tint = c.sub)
                Text("Весь день", fontSize = 16.sp, color = c.text, modifier = Modifier.weight(1f).padding(start = 12.dp))
                Switch(checked = allDay, onCheckedChange = { allDay = it })
            }

            // дата
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { showDate = true }.padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Filled.CalendarToday, null, tint = c.sub)
                Text(
                    date.format(DateTimeFormatter.ofPattern("EEEE, d MMMM yyyy", RU)),
                    fontSize = 16.sp, color = c.text, modifier = Modifier.padding(start = 12.dp)
                )
            }

            // время
            if (!allDay) {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { showTime = !showTime }.padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Filled.Schedule, null, tint = c.sub)
                    Text(
                        "%02d:%02d – %02d:%02d".format(sh, sm, eh, em),
                        fontSize = 16.sp, color = c.accent, modifier = Modifier.padding(start = 12.dp)
                    )
                }
                if (showTime) {
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("Начало", color = c.sub, fontSize = 13.sp)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Wheel(24, sh) { sh = it }
                                Text(":", fontSize = 22.sp, color = c.text)
                                Wheel(60, sm) { sm = it }
                            }
                        }
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("Конец", color = c.sub, fontSize = 13.sp)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Wheel(24, eh) { eh = it }
                                Text(":", fontSize = 22.sp, color = c.text)
                                Wheel(60, em) { em = it }
                            }
                        }
                    }
                }
            }

            // место
            OutlinedTextField(
                room, { room = it }, label = { Text("Место") },
                leadingIcon = { Icon(Icons.Filled.LocationOn, null) },
                singleLine = true, modifier = Modifier.fillMaxWidth()
            )

            // повторение
            Box {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.card)
                        .clickable { menu = true }.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Filled.Repeat, null, tint = c.sub)
                    Text("Повторение", fontSize = 16.sp, color = c.text, modifier = Modifier.weight(1f).padding(start = 12.dp))
                    Text(recurrenceLabel(recurrence), color = c.accent, fontSize = 15.sp)
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    RECURRENCES.forEach { (k, v) ->
                        DropdownMenuItem(text = { Text(v) }, onClick = { recurrence = k; menu = false })
                    }
                }
            }

            if (init.id != 0L) {
                TextButton(onClick = onDelete) { Text("Удалить событие", color = Color(0xFFE53935)) }
            }
        }

        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            TextButton(onClick = onCancel) { Text("Отмена", fontSize = 16.sp) }
            TextButton(onClick = { save() }) { Text("Сохранить", fontSize = 16.sp, fontWeight = FontWeight.Bold) }
        }
    }

    if (showDate) {
        val st = rememberDatePickerState(initialSelectedDateMillis = date.toEpochDay() * 86_400_000L)
        val base = LocalContext.current
        val ruCtx = remember(base) {
            base.createConfigurationContext(
                Configuration(base.resources.configuration).apply { setLocale(RU) }
            )
        }
        CompositionLocalProvider(
            LocalContext provides ruCtx,
            LocalConfiguration provides ruCtx.resources.configuration
        ) {
            DatePickerDialog(
                onDismissRequest = { showDate = false },
                confirmButton = {
                    TextButton(onClick = {
                        st.selectedDateMillis?.let { date = LocalDate.ofEpochDay(Math.floorDiv(it, 86_400_000L)) }
                        showDate = false
                    }) { Text("OK") }
                },
                dismissButton = { TextButton(onClick = { showDate = false }) { Text("Отмена") } }
            ) { DatePicker(state = st) }
        }
    }
}

@Composable
fun Wheel(count: Int, value: Int, onChange: (Int) -> Unit) {
    val c = C
    val itemH = 40.dp
    val itemPx = with(LocalDensity.current) { itemH.toPx() }
    val state = rememberLazyListState(initialFirstVisibleItemIndex = value.coerceIn(0, count - 1))
    val fling = rememberSnapFlingBehavior(state)
    val cb by rememberUpdatedState(onChange)
    val sel by remember {
        derivedStateOf {
            (state.firstVisibleItemIndex + if (state.firstVisibleItemScrollOffset > itemPx / 2) 1 else 0)
                .coerceIn(0, count - 1)
        }
    }
    LaunchedEffect(Unit) { snapshotFlow { sel }.collect { cb(it) } }

    Box(Modifier.width(56.dp).height(itemH * 3), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxWidth().height(itemH).clip(RoundedCornerShape(10.dp)).background(c.card))
        LazyColumn(
            state = state,
            flingBehavior = fling,
            contentPadding = PaddingValues(vertical = itemH),
            modifier = Modifier.fillMaxSize()
        ) {
            items(count) { i ->
                Box(Modifier.fillMaxWidth().height(itemH), contentAlignment = Alignment.Center) {
                    Text(
                        "%02d".format(i), fontSize = 22.sp,
                        color = if (i == sel) c.text else c.sub
                    )
                }
            }
        }
    }
}
