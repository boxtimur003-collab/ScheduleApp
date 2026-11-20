@file:OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)

package com.example.schedule

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.abs

const val MONTH_BASE = 1200
const val MONTH_COUNT = 2400
const val DAY_BASE = 36500
const val DAY_COUNT = 73001

val DAYS = listOf("Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс")
val EMOJIS = listOf(
    "📚", "🧮", "🔬", "💻", "🎨", "🎵", "⚽", "🌍",
    "📝", "🧪", "🏛️", "🧬", "🗣️", "🎭", "⏰", "⭐"
)

fun dateOfPage(anchor: LocalDate, p: Int): LocalDate = anchor.plusDays((p - DAY_BASE).toLong())
fun pageOfDate(anchor: LocalDate, d: LocalDate): Int =
    (DAY_BASE + ChronoUnit.DAYS.between(anchor, d)).toInt().coerceIn(0, DAY_COUNT - 1)

fun monthOfPage(anchor: YearMonth, p: Int): YearMonth = anchor.plusMonths((p - MONTH_BASE).toLong())
fun pageOfMonth(anchor: YearMonth, m: YearMonth): Int =
    (MONTH_BASE + ChronoUnit.MONTHS.between(anchor, m)).toInt().coerceIn(0, MONTH_COUNT - 1)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val repo = ScheduleRepository(this)
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = Pal.Purple, background = Pal.Bg, surface = Pal.Card,
                    onBackground = Pal.Text, onSurface = Pal.Text
                )
            ) {
                App(repo)
            }
        }
    }
}

@Composable
fun App(repo: ScheduleRepository) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val anchor = remember { LocalDate.now() }
    val anchorMonth = remember { YearMonth.from(anchor) }

    var lessons by remember { mutableStateOf(repo.load()) }
    var tab by remember { mutableStateOf(0) }
    var status by remember { mutableStateOf("") }
    var selected by remember { mutableStateOf(anchor) }
    var editing by remember { mutableStateOf<Lesson?>(null) }

    val dayPager = rememberPagerState(initialPage = DAY_BASE) { DAY_COUNT }
    val monthPager = rememberPagerState(initialPage = MONTH_BASE) { MONTH_COUNT }

    LaunchedEffect(dayPager) {
        snapshotFlow { dayPager.settledPage }.collect { selected = dateOfPage(anchor, it) }
    }
    LaunchedEffect(monthPager) {
        snapshotFlow { monthPager.settledPage }.collect { p ->
            val ym = monthOfPage(anchorMonth, p)
            if (YearMonth.from(selected) != ym) {
                selected = ym.atDay(minOf(selected.dayOfMonth, ym.lengthOfMonth()))
            }
        }
    }
    LaunchedEffect(selected) {
        val dp = pageOfDate(anchor, selected)
        if (dayPager.currentPage != dp) {
            if (abs(dayPager.currentPage - dp) > 3) dayPager.scrollToPage(dp)
            else dayPager.animateScrollToPage(dp)
        }
        val mp = pageOfMonth(anchorMonth, YearMonth.from(selected))
        if (monthPager.currentPage != mp) monthPager.animateScrollToPage(mp)
    }

    fun sync(list: List<Lesson>) {
        scope.launch {
            val c = DataSyncService.send(ctx, LessonJson.toJson(list))
            status = when {
                c > 0 -> "Отправлено на часы"
                c == -2 -> "Слишком много событий для отправки"
                else -> "Часы не найдены"
            }
        }
    }

    fun persist(list: List<Lesson>) {
        lessons = list
        repo.save(list)
        sync(list)
    }

    BackHandler(enabled = editing != null) { editing = null }

    Box(Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = Pal.Bg,
            bottomBar = {
                NavigationBar(containerColor = Pal.Card) {
                    NavigationBarItem(
                        selected = tab == 0, onClick = { tab = 0 },
                        icon = { Icon(Icons.Filled.CalendarMonth, null) },
                        label = { Text("Расписание") }
                    )
                    NavigationBarItem(
                        selected = tab == 1, onClick = { tab = 1 },
                        icon = { Icon(Icons.Filled.Settings, null) },
                        label = { Text("Настройки") }
                    )
                }
            },
            floatingActionButton = {
                if (tab == 0) FloatingActionButton(
                    onClick = {
                        editing = Lesson(
                            id = 0L, title = "", date = selected.toString(),
                            recurrence = "NONE", isAllDay = false, color = PALETTE[0],
                            start = "08:30", end = "09:15", room = "", icon = "other", emoji = ""
                        )
                    },
                    containerColor = Pal.Purple
                ) { Icon(Icons.Filled.Add, null) }
            }
        ) { pad ->
            if (tab == 0) {
                CalendarScreen(
                    pad = pad, lessons = lessons, selected = selected,
                    anchor = anchor, anchorMonth = anchorMonth,
                    monthPager = monthPager, dayPager = dayPager,
                    onSelect = { selected = it }, onEdit = { editing = it }
                )
            } else {
                Column(
                    Modifier.padding(pad).padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text("Настройки", fontSize = 28.sp, fontWeight = FontWeight.Bold)
                    Button(onClick = { sync(lessons) }) {
                        Icon(Icons.Filled.Sync, null)
                        Spacer(Modifier.width(8.dp))
                        Text("Отправить на часы")
                    }
                    Text(status, color = Pal.Dim)
                }
            }
        }

        editing?.let { e ->
            EditScreen(
                init = e,
                onSave = { l ->
                    val fixed = l.copy(id = if (l.id == 0L) System.currentTimeMillis() else l.id)
                    persist(lessons.filter { it.id != fixed.id } + fixed)
                    editing = null
                },
                onDelete = {
                    persist(lessons.filter { it.id != e.id })
                    editing = null
                },
                onClose = { editing = null }
            )
        }
    }
}

@Composable
fun CalendarScreen(
    pad: PaddingValues,
    lessons: List<Lesson>,
    selected: LocalDate,
    anchor: LocalDate,
    anchorMonth: YearMonth,
    monthPager: PagerState,
    dayPager: PagerState,
    onSelect: (LocalDate) -> Unit,
    onEdit: (Lesson) -> Unit
) {
    val scope = rememberCoroutineScope()
    val today = remember { LocalDate.now() }
    val shown = monthOfPage(anchorMonth, monthPager.currentPage)
    val monthName = shown.month.getDisplayName(TextStyle.FULL_STANDALONE, Locale("ru"))
    val dayMonth = selected.month.getDisplayName(TextStyle.FULL, Locale("ru"))

    Column(Modifier.padding(pad).padding(horizontal = 16.dp)) {
        Text(
            "Расписание", fontSize = 28.sp, fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(vertical = 12.dp)
        )
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            IconButton(onClick = {
                scope.launch { monthPager.animateScrollToPage(monthPager.currentPage - 1) }
            }) { Icon(Icons.Filled.ChevronLeft, null) }
            Text(
                "${monthName.replaceFirstChar { it.uppercase() }} ${shown.year}",
                fontSize = 18.sp, fontWeight = FontWeight.SemiBold
            )
            IconButton(onClick = {
                scope.launch { monthPager.animateScrollToPage(monthPager.currentPage + 1) }
            }) { Icon(Icons.Filled.ChevronRight, null) }
        }
        Row(Modifier.fillMaxWidth()) {
            DAYS.forEach {
                Text(it, Modifier.weight(1f), textAlign = TextAlign.Center, color = Pal.Dim)
            }
        }
        HorizontalPager(
            state = monthPager,
            modifier = Modifier.fillMaxWidth().height(276.dp)
        ) { page ->
            MonthPage(monthOfPage(anchorMonth, page), lessons, selected, today, onSelect)
        }
        Text(
            if (selected == today) "Сегодня, ${selected.dayOfMonth} $dayMonth"
            else "${selected.dayOfMonth} $dayMonth",
            fontSize = 22.sp, fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(top = 16.dp, bottom = 8.dp)
        )
        HorizontalPager(
            state = dayPager,
            modifier = Modifier.weight(1f).fillMaxWidth()
        ) { page ->
            DayList(dateOfPage(anchor, page), lessons, onEdit)
        }
    }
}

@Composable
fun MonthPage(
    ym: YearMonth, lessons: List<Lesson>, selected: LocalDate,
    today: LocalDate, onSelect: (LocalDate) -> Unit
) {
    val offset = ym.atDay(1).dayOfWeek.value - 1
    val len = ym.lengthOfMonth()
    val busy = remember(lessons, ym) {
        (1..len).filter { n ->
            val d = ym.atDay(n)
            lessons.any { it.occursOn(d) }
        }.toSet()
    }
    Column(Modifier.fillMaxWidth()) {
        for (r in 0 until 6) {
            Row(Modifier.fillMaxWidth()) {
                for (c in 0..6) {
                    val n = r * 7 + c - offset + 1
                    if (n in 1..len) {
                        val d = ym.atDay(n)
                        DayCell(n, d == selected, d == today, n in busy) { onSelect(d) }
                    } else {
                        Spacer(Modifier.weight(1f).height(46.dp))
                    }
                }
            }
        }
    }
}

@Composable
fun RowScope.DayCell(n: Int, sel: Boolean, today: Boolean, has: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.weight(1f).height(46.dp).padding(2.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(if (sel) Pal.Purple else Color.Transparent)
            .let { if (today && !sel) it.border(1.dp, Pal.Lilac, RoundedCornerShape(12.dp)) else it }
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("$n", fontSize = 15.sp)
            if (has) Box(Modifier.size(4.dp).clip(CircleShape).background(Pal.Lilac))
        }
    }
}

@Composable
fun DayList(date: LocalDate, lessons: List<Lesson>, onEdit: (Lesson) -> Unit) {
    val list = remember(lessons, date) {
        lessons.filter { it.occursOn(date) }
            .sortedWith(compareByDescending<Lesson> { it.isAllDay }.thenBy { it.start })
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 88.dp)) {
        if (list.isEmpty()) {
            item { Text("Занятий нет", color = Pal.Dim, modifier = Modifier.padding(top = 8.dp)) }
        }
        items(list, key = { it.id }) { LessonCard(it) { onEdit(it) } }
    }
}

@Composable
fun LessonCard(l: Lesson, onClick: () -> Unit) {
    val col = parseColor(l.color)
    Row(
        Modifier.fillMaxWidth().padding(vertical = 5.dp).clip(RoundedCornerShape(16.dp))
            .background(Pal.Card).clickable(onClick = onClick).height(IntrinsicSize.Min),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(4.dp).fillMaxHeight().background(col))
        Column(Modifier.weight(1f).padding(14.dp)) {
            Text(l.timeLabel(), color = Pal.Dim, fontSize = 14.sp)
            Text(l.title, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            if (l.room.isNotBlank()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.LocationOn, null, tint = Pal.Dim, modifier = Modifier.size(14.dp))
                    Text(" ${l.room}", color = Pal.Dim, fontSize = 14.sp)
                }
            }
            if (l.recurrence != "NONE") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Repeat, null, tint = Pal.Dim, modifier = Modifier.size(14.dp))
                    Text(" ${recurrenceStatus(l.recurrence)}", color = Pal.Dim, fontSize = 13.sp)
                }
            }
        }
        Box(
            Modifier.padding(end = 14.dp).size(52.dp).clip(RoundedCornerShape(14.dp))
                .background(col.copy(alpha = 0.25f)),
            contentAlignment = Alignment.Center
        ) {
            if (l.emoji.isNotBlank()) Text(l.emoji, fontSize = 26.sp)
            else Icon(iconFor(l.icon), null, tint = col, modifier = Modifier.size(30.dp))
        }
    }
}

@Composable
fun EditScreen(init: Lesson, onSave: (Lesson) -> Unit, onDelete: () -> Unit, onClose: () -> Unit) {
    var title by remember { mutableStateOf(init.title) }
    var emoji by remember { mutableStateOf(init.emoji) }
    var showEmoji by remember { mutableStateOf(false) }
    var color by remember { mutableStateOf(init.color) }
    var allDay by remember { mutableStateOf(init.isAllDay) }
    var date by remember {
        mutableStateOf(try { LocalDate.parse(init.date) } catch (e: Exception) { LocalDate.now() })
    }
    var sh by remember { mutableStateOf(init.start.substringBefore(":").toIntOrNull() ?: 8) }
    var sm by remember { mutableStateOf(init.start.substringAfter(":").toIntOrNull() ?: 30) }
    var eh by remember { mutableStateOf(init.end.substringBefore(":").toIntOrNull() ?: 9) }
    var em by remember { mutableStateOf(init.end.substringAfter(":").toIntOrNull() ?: 15) }
    var room by remember { mutableStateOf(init.room) }
    var icon by remember { mutableStateOf(init.icon) }
    var recurrence by remember { mutableStateOf(init.recurrence) }
    var menu by remember { mutableStateOf(false) }

    val doSave = {
        val s = "%02d:%02d".format(sh, sm)
        var e = "%02d:%02d".format(eh, em)
        if (e < s) e = s
        onSave(
            init.copy(
                title = title.ifBlank { "Событие" }, emoji = emoji, color = color,
                isAllDay = allDay, date = date.toString(), start = s, end = e,
                room = room, icon = icon, recurrence = recurrence
            )
        )
    }

    Column(
        Modifier.fillMaxSize().background(Pal.Bg)
            .pointerInput(Unit) {}
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose) { Icon(Icons.Filled.Close, null) }
            Text(
                if (init.id == 0L) "Новое событие" else "Редактирование",
                fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)
            )
            TextButton(onClick = { doSave() }) { Text("Готово") }
        }

        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                title, { title = it }, label = { Text("Название") },
                singleLine = true, modifier = Modifier.weight(1f)
            )
            Box(
                Modifier.size(56.dp).clip(RoundedCornerShape(14.dp)).background(Pal.Card)
                    .clickable { showEmoji = !showEmoji },
                contentAlignment = Alignment.Center
            ) {
                if (emoji.isBlank()) Icon(Icons.Filled.EmojiEmotions, null, tint = Pal.Lilac)
                else Text(emoji, fontSize = 26.sp)
            }
        }
        if (showEmoji) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                EMOJIS.chunked(8).forEach { chunk ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        chunk.forEach { e ->
                            Text(
                                e, fontSize = 26.sp,
                                modifier = Modifier.clip(RoundedCornerShape(8.dp))
                                    .clickable { emoji = e; showEmoji = false }
                                    .padding(4.dp)
                            )
                        }
                    }
                }
                TextButton(onClick = { emoji = ""; showEmoji = false }) { Text("Убрать эмодзи") }
            }
        }

        Text("Цвет", color = Pal.Dim)
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            PALETTE.forEach { hex ->
                Box(
                    Modifier.size(36.dp).clip(CircleShape).background(parseColor(hex))
                        .clickable { color = hex },
                    contentAlignment = Alignment.Center
                ) {
                    if (hex == color) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(20.dp))
                }
            }
        }

        Text("Иконка", color = Pal.Dim)
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ICON_KEYS.forEach { k ->
                Box(
                    Modifier.size(44.dp).clip(RoundedCornerShape(12.dp))
                        .background(parseColor(color).copy(alpha = if (k == icon) 0.7f else 0.2f))
                        .clickable { icon = k },
                    contentAlignment = Alignment.Center
                ) { Icon(iconFor(k), null, tint = Pal.Text) }
            }
        }

        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Pal.Card).padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            IconButton(onClick = { date = date.minusDays(1) }) { Icon(Icons.Filled.ChevronLeft, null) }
            Text(
                "${date.dayOfMonth} ${date.month.getDisplayName(TextStyle.FULL, Locale("ru"))} ${date.year}",
                fontSize = 16.sp
            )
            IconButton(onClick = { date = date.plusDays(1) }) { Icon(Icons.Filled.ChevronRight, null) }
        }

        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Весь день", fontSize = 16.sp)
            Switch(checked = allDay, onCheckedChange = { allDay = it })
        }

        if (!allDay) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Начало", color = Pal.Dim)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Wheel(24, sh) { sh = it }
                        Text(":", fontSize = 22.sp)
                        Wheel(60, sm) { sm = it }
                    }
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Конец", color = Pal.Dim)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Wheel(24, eh) { eh = it }
                        Text(":", fontSize = 22.sp)
                        Wheel(60, em) { em = it }
                    }
                }
            }
        }

        OutlinedTextField(
            room, { room = it }, label = { Text("Место") },
            leadingIcon = { Icon(Icons.Filled.LocationOn, null) },
            singleLine = true, modifier = Modifier.fillMaxWidth()
        )

        Box {
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Pal.Card)
                    .clickable { menu = true }.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("Повторение", fontSize = 16.sp)
                Text(recurrenceLabel(recurrence), color = Pal.Lilac, fontSize = 16.sp)
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                RECURRENCES.forEach { (k, v) ->
                    DropdownMenuItem(text = { Text(v) }, onClick = { recurrence = k; menu = false })
                }
            }
        }

        if (init.id != 0L) {
            TextButton(onClick = onDelete) { Text("Удалить событие", color = Color(0xFFFF6B6B)) }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
fun Wheel(count: Int, value: Int, onChange: (Int) -> Unit) {
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
        Box(Modifier.fillMaxWidth().height(itemH).clip(RoundedCornerShape(10.dp)).background(Pal.Card))
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
                        color = if (i == sel) Pal.Text else Pal.Dim
                    )
                }
            }
        }
    }
}
