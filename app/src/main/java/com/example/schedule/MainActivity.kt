package com.example.schedule

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val repo = ScheduleRepository(this)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(
                primary = Pal.Purple, background = Pal.Bg, surface = Pal.Card,
                onBackground = Pal.Text, onSurface = Pal.Text)) {
                App(repo)
            }
        }
    }
}

val DAYS = listOf("Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс")

@Composable
fun App(repo: ScheduleRepository) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var lessons by remember { mutableStateOf(repo.load()) }
    var tab by remember { mutableStateOf(0) }
    var status by remember { mutableStateOf("") }
    var selected by remember { mutableStateOf(LocalDate.now()) }
    var month by remember { mutableStateOf(YearMonth.now()) }
    var editing by remember { mutableStateOf<Lesson?>(null) }

    fun sync(list: List<Lesson>) {
        scope.launch {
            val c = DataSyncService.send(ctx, LessonJson.toJson(list))
            status = if (c > 0) "Отправлено на часы" else "Часы не найдены"
        }
    }
    fun persist(list: List<Lesson>) { lessons = list; repo.save(list); sync(list) }

    Scaffold(
        containerColor = Pal.Bg,
        bottomBar = {
            NavigationBar(containerColor = Pal.Card) {
                NavigationBarItem(selected = tab == 0, onClick = { tab = 0 },
                    icon = { Icon(Icons.Filled.CalendarMonth, null) }, label = { Text("Расписание") })
                NavigationBarItem(selected = tab == 1, onClick = { tab = 1 },
                    icon = { Icon(Icons.Filled.Settings, null) }, label = { Text("Настройки") })
            }
        },
        floatingActionButton = {
            if (tab == 0) FloatingActionButton(
                onClick = { editing = Lesson(0, selected.dayOfWeek.value, "08:30", "09:15", "", "", "other") },
                containerColor = Pal.Purple) { Icon(Icons.Filled.Add, null) }
        }
    ) { pad ->
        if (tab == 0) {
            ScheduleTab(pad, lessons, month, selected,
                onMonth = { month = it }, onSelect = { selected = it }, onEdit = { editing = it })
        } else {
            Column(Modifier.padding(pad).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Настройки", fontSize = 28.sp, fontWeight = FontWeight.Bold)
                Button(onClick = { sync(lessons) }) {
                    Icon(Icons.Filled.Sync, null); Spacer(Modifier.width(8.dp)); Text("Отправить на часы")
                }
                Text(status, color = Pal.Dim)
            }
        }
    }

    editing?.let { e ->
        EditDialog(e,
            onSave = { l ->
                val fixed = l.copy(id = if (l.id == 0L) System.currentTimeMillis() else l.id)
                persist(lessons.filter { it.id != fixed.id } + fixed); editing = null
            },
            onDelete = { persist(lessons.filter { it.id != e.id }); editing = null },
            onDismiss = { editing = null })
    }
}

@Composable
fun ScheduleTab(
    pad: PaddingValues, lessons: List<Lesson>, month: YearMonth, selected: LocalDate,
    onMonth: (YearMonth) -> Unit, onSelect: (LocalDate) -> Unit, onEdit: (Lesson) -> Unit
) {
    val today = LocalDate.now()
    val monthName = month.month.getDisplayName(java.time.format.TextStyle.FULL_STANDALONE, Locale("ru"))
    val offset = month.atDay(1).dayOfWeek.value - 1
    val len = month.lengthOfMonth()
    val rows = (offset + len + 6) / 7
    val dayLessons = lessons.filter { it.day == selected.dayOfWeek.value }.sortedBy { it.start }

    Column(Modifier.padding(pad).padding(horizontal = 16.dp).verticalScroll(rememberScrollState())) {
        Text("Расписание", fontSize = 28.sp, fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(vertical = 12.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween) {
            IconButton(onClick = { onMonth(month.minusMonths(1)) }) { Icon(Icons.Filled.ChevronLeft, null) }
            Text("$monthName ${month.year}", fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
            IconButton(onClick = { onMonth(month.plusMonths(1)) }) { Icon(Icons.Filled.ChevronRight, null) }
        }
        Row { DAYS.forEach { Text(it, Modifier.weight(1f), textAlign = TextAlign.Center, color = Pal.Dim) } }
        for (r in 0 until rows) {
            Row {
                for (c in 0..6) {
                    val n = r * 7 + c - offset + 1
                    if (n in 1..len) {
                        val d = month.atDay(n)
                        DayCell(n, d == selected, d == today, lessons.any { it.day == d.dayOfWeek.value }) { onSelect(d) }
                    } else Spacer(Modifier.weight(1f).height(46.dp))
                }
            }
        }
        Text(if (selected == today) "Сегодня, ${selected.dayOfMonth} ${monthName}" else "${selected.dayOfMonth} $monthName",
            fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 20.dp, bottom = 8.dp))
        if (dayLessons.isEmpty()) Text("Занятий нет", color = Pal.Dim)
        dayLessons.forEach { LessonCard(it) { onEdit(it) } }
        Spacer(Modifier.height(88.dp))
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
fun LessonCard(l: Lesson, onClick: () -> Unit) {
    val col = colorFor(l.icon)
    Row(
        Modifier.fillMaxWidth().padding(vertical = 5.dp).clip(RoundedCornerShape(16.dp))
            .background(Pal.Card).clickable(onClick = onClick).height(IntrinsicSize.Min),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(4.dp).fillMaxHeight().background(col))
        Column(Modifier.weight(1f).padding(14.dp)) {
            Text("${l.start} – ${l.end}", color = Pal.Dim, fontSize = 14.sp)
            Text(l.subject, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.LocationOn, null, tint = Pal.Dim, modifier = Modifier.size(14.dp))
                Text(" Каб. ${l.room}", color = Pal.Dim, fontSize = 14.sp)
            }
        }
        Box(Modifier.padding(end = 14.dp).size(52.dp).clip(RoundedCornerShape(14.dp))
            .background(col.copy(alpha = 0.25f)), contentAlignment = Alignment.Center) {
            Icon(iconFor(l.icon), null, tint = col, modifier = Modifier.size(30.dp))
        }
    }
}

@Composable
fun EditDialog(init: Lesson, onSave: (Lesson) -> Unit, onDelete: () -> Unit, onDismiss: () -> Unit) {
    var start by remember { mutableStateOf(init.start) }
    var end by remember { mutableStateOf(init.end) }
    var subject by remember { mutableStateOf(init.subject) }
    var room by remember { mutableStateOf(init.room) }
    var icon by remember { mutableStateOf(init.icon) }
    AlertDialog(
        onDismissRequest = onDismiss, containerColor = Pal.Card,
        title = { Text(if (init.id == 0L) "Новый урок" else "Редактирование") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(start, { start = it }, label = { Text("Начало") },
                        singleLine = true, modifier = Modifier.weight(1f))
                    OutlinedTextField(end, { end = it }, label = { Text("Конец") },
                        singleLine = true, modifier = Modifier.weight(1f))
                }
                OutlinedTextField(subject, { subject = it }, label = { Text("Предмет") }, singleLine = true)
                OutlinedTextField(room, { room = it }, label = { Text("Кабинет") }, singleLine = true)
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ICON_KEYS.forEach { k ->
                        Box(Modifier.size(44.dp).clip(RoundedCornerShape(12.dp))
                            .background(colorFor(k).copy(alpha = if (k == icon) 0.7f else 0.2f))
                            .clickable { icon = k }, contentAlignment = Alignment.Center) {
                            Icon(iconFor(k), null, tint = Pal.Text)
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(init.copy(start = start, end = end, subject = subject.ifBlank { "Урок" }, room = room, icon = icon)) }) { Text("Сохранить") }
        },
        dismissButton = {
            Row {
                if (init.id != 0L) TextButton(onClick = onDelete) { Text("Удалить") }
                TextButton(onClick = onDismiss) { Text("Отмена") }
            }
        }
    )
}
