@file:OptIn(ExperimentalFoundationApi::class)

package com.example.schedule

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

const val DAYS_RANGE = 30
private val WRU: Locale = Locale("ru")

private fun nowMinutes(): Int {
    val t = LocalTime.now()
    return t.hour * 60 + t.minute
}

private fun hm(s: String): Int =
    (s.substringBefore(":").toIntOrNull() ?: 0) * 60 + (s.substringAfter(":").toIntOrNull() ?: 0)

private fun batteryPct(ctx: Context): Int = try {
    (ctx.getSystemService(Context.BATTERY_SERVICE) as BatteryManager)
        .getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
} catch (e: Exception) {
    -1
}

private fun lessonsWord(n: Int): String {
    val m100 = n % 100
    val m10 = n % 10
    return if (m100 in 11..14) "уроков" else when (m10) {
        1 -> "урок"
        in 2..4 -> "урока"
        else -> "уроков"
    }
}

@Composable
fun WearApp() {
    val ctx = LocalContext.current
    val lessons by ScheduleRepository.lessons.collectAsState()
    val files by FileStore.files.collectAsState()
    var detail by remember { mutableStateOf<Lesson?>(null) }
    var overlay by remember { mutableStateOf(Overlay.NONE) }
    var viaMenu by remember { mutableStateOf(false) }
    var openId by remember { mutableStateOf<String?>(null) }
    var inDays by remember { mutableStateOf(false) }
    var startPage by remember { mutableStateOf(DAYS_RANGE) }
    var daysKey by remember { mutableStateOf(0) }
    var picked by remember { mutableStateOf(0) }
    var nowMin by remember { mutableStateOf(nowMinutes()) }
    var battery by remember { mutableStateOf(batteryPct(ctx)) }
    val today = remember { LocalDate.now() }
    val perm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }

    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            perm.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    LaunchedEffect(lessons) { Notifier.rescheduleAll(ctx, lessons) }
    LaunchedEffect(Unit) {
        while (true) {
            nowMin = nowMinutes()
            battery = batteryPct(ctx)
            delay(60_000L - System.currentTimeMillis() % 60_000L)
        }
    }

    BackHandler(enabled = detail != null || overlay != Overlay.NONE || inDays) {
        when {
            overlay == Overlay.FILE -> overlay = Overlay.FILES
            overlay == Overlay.FILES || overlay == Overlay.DATES ->
                overlay = if (viaMenu) Overlay.MENU else Overlay.NONE
            overlay == Overlay.MENU -> overlay = Overlay.NONE
            detail != null -> detail = null
            else -> inDays = false
        }
    }

    MaterialTheme {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            val d = detail
            if (d != null) {
                DetailScreen(d) { detail = null }
            } else {
                if (inDays) {
                    key(daysKey) {
                        DaysScreen(
                            startPage, lessons, today, nowMin,
                            onOpen = { detail = it },
                            onMenu = { viaMenu = true; overlay = Overlay.MENU }
                        )
                    }
                } else {
                    HomeScreen(
                        lessons, today, nowMin, battery,
                        onOpen = { detail = it },
                        onFiles = { viaMenu = false; overlay = Overlay.FILES },
                        onDates = { viaMenu = false; overlay = Overlay.DATES },
                        onDays = { startPage = DAYS_RANGE; picked = 0; daysKey++; inDays = true }
                    )
                }
                when (overlay) {
                    Overlay.MENU -> MenuPanel(
                        filesCount = files.size,
                        onDates = { overlay = Overlay.DATES },
                        onFiles = { overlay = Overlay.FILES }
                    )
                    Overlay.DATES -> DatesDrawer(today, picked) { i ->
                        picked = i
                        startPage = DAYS_RANGE + i
                        daysKey++
                        inDays = true
                        overlay = Overlay.NONE
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
            }
        }
    }
}

@Composable
private fun DaysScreen(
    startPage: Int, lessons: List<Lesson>, today: LocalDate, nowMin: Int,
    onOpen: (Lesson) -> Unit, onMenu: () -> Unit
) {
    val pager = rememberPagerState(initialPage = startPage) { DAYS_RANGE * 2 + 1 }
    Box(Modifier.fillMaxSize()) {
        HorizontalPager(state = pager) { page ->
            val date = today.plusDays((page - DAYS_RANGE).toLong())
            DayPage(date, lessons, date == today, nowMin, onOpen, onMenu)
        }
        // левый край: свайп слева направо открывает меню
        Box(
            Modifier.align(Alignment.CenterStart).fillMaxHeight().width(24.dp)
                .pointerInput(Unit) {
                    var total = 0f
                    detectHorizontalDragGestures(
                        onDragStart = { total = 0f },
                        onDragEnd = { if (total > 40f) onMenu() },
                        onDragCancel = { total = 0f },
                        onHorizontalDrag = { _, dx -> total += dx }
                    )
                }
        )
    }
}

@Composable
private fun HomeScreen(
    lessons: List<Lesson>, today: LocalDate, nowMin: Int, battery: Int,
    onOpen: (Lesson) -> Unit, onFiles: () -> Unit, onDates: () -> Unit, onDays: () -> Unit
) {
    val ctx = LocalContext.current
    val bgId = remember { ctx.resources.getIdentifier("watch_face_bg", "drawable", ctx.packageName) }
    val all = remember(lessons, today) {
        lessons.filter { it.occursOn(today) }
            .sortedWith(compareByDescending<Lesson> { it.isAllDay }.thenBy { it.start })
    }
    val next = remember(all, nowMin) { all.filter { it.isAllDay || hm(it.end) > nowMin } }
    val prog = ((nowMin - 480) / 600f).coerceIn(0f, 1f)
    val dateText = remember(today) {
        today.format(DateTimeFormatter.ofPattern("EEE, d MMM", WRU)).replaceFirstChar { it.uppercase() }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (bgId != 0) {
            Image(painterResource(bgId), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alpha = 0.55f)
        }
        // дуга по левому краю: прогресс учебного дня (08:00-18:00)
        Canvas(Modifier.fillMaxSize()) {
            val sw = 4.dp.toPx()
            val inset = sw / 2f + 2.dp.toPx()
            val tl = Offset(inset, inset)
            val sz = Size(size.width - 2f * inset, size.height - 2f * inset)
            drawArc(Color(0xFF2A2740), 270f, -170f, false, tl, sz, style = Stroke(sw, cap = StrokeCap.Round))
            if (prog > 0f) {
                drawArc(Pal.Purple, 270f, -170f * prog, false, tl, sz, style = Stroke(sw, cap = StrokeCap.Round))
            }
        }
        Column(
            Modifier.fillMaxSize().padding(top = 10.dp, bottom = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.CalendarMonth, null, tint = Pal.Lilac, modifier = Modifier.size(16.dp))
                Text(
                    "  $dateText", color = Color(0xFFE6E0FF), fontSize = 14.sp,
                    fontWeight = FontWeight.Bold, maxLines = 1
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    buildAnnotatedString {
                        withStyle(SpanStyle(color = Color.White)) { append("%02d".format(nowMin / 60)) }
                        withStyle(SpanStyle(color = Color(0xFF8C88A8))) { append(":") }
                        withStyle(SpanStyle(color = Pal.Purple)) { append("%02d".format(nowMin % 60)) }
                    },
                    fontSize = 42.sp, lineHeight = 44.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1
                )
                Spacer(Modifier.width(6.dp))
                Box(
                    Modifier.size(38.dp).background(
                        Brush.radialGradient(listOf(Color(0x667C5CFF), Color.Transparent)), CircleShape
                    ),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Filled.CalendarMonth, null, tint = Pal.Lilac, modifier = Modifier.size(26.dp))
                }
            }
            Spacer(Modifier.height(4.dp))
            Row(
                Modifier.clip(RoundedCornerShape(14.dp)).background(Color(0xFF14131C))
                    .clickable(onClick = onDays).padding(horizontal = 10.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(Modifier.size(7.dp).clip(CircleShape).background(Pal.Purple))
                Text(
                    "  Сегодня • " + (if (all.isEmpty()) "занятий нет" else "${all.size} ${lessonsWord(all.size)}"),
                    color = Color(0xFFE6E0FF), fontSize = 12.sp, maxLines = 1
                )
            }
            Spacer(Modifier.height(6.dp))
            Column(
                Modifier.weight(1f).fillMaxWidth().padding(horizontal = 24.dp).clipToBounds(),
                verticalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                if (next.isEmpty()) {
                    Text(
                        if (all.isEmpty()) "Занятий нет" else "На сегодня всё",
                        color = Pal.Dim, fontSize = 13.sp,
                        modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp)
                    )
                }
                next.take(3).forEach { HomeCard(it) { onOpen(it) } }
            }
        }
        // стрелки: левая - «Файлы», правая - «Даты»
        Box(
            Modifier.align(Alignment.CenterStart).padding(start = 3.dp).size(28.dp).clip(CircleShape)
                .background(Color(0xFF1B1A22)).clickable(onClick = onFiles),
            contentAlignment = Alignment.Center
        ) { Icon(Icons.Filled.ChevronLeft, null, tint = Color.White, modifier = Modifier.size(20.dp)) }
        Box(
            Modifier.align(Alignment.CenterEnd).padding(end = 3.dp).size(28.dp).clip(CircleShape)
                .background(Color(0xFF1B1A22)).clickable(onClick = onDates),
            contentAlignment = Alignment.Center
        ) { Icon(Icons.Filled.ChevronRight, null, tint = Color.White, modifier = Modifier.size(20.dp)) }
        if (battery > 0) {
            Row(
                Modifier.align(Alignment.TopEnd).padding(top = 28.dp, end = 34.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Filled.BatteryFull, null, tint = Pal.Lilac, modifier = Modifier.size(13.dp))
                Text(" $battery%", color = Pal.Dim, fontSize = 11.sp, maxLines = 1)
            }
        }
        Row(
            Modifier.align(Alignment.BottomCenter).padding(bottom = 7.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(Modifier.size(7.dp).clip(CircleShape).background(Pal.Purple))
            Box(Modifier.size(6.dp).clip(CircleShape).background(Color(0xFF3A3A44)))
            Box(Modifier.size(6.dp).clip(CircleShape).background(Color(0xFF3A3A44)))
        }
    }
}

@Composable
private fun HomeCard(l: Lesson, onClick: () -> Unit) {
    val col = parseColor(l.color)
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Color(0xFF17161F))
            .clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(5.dp).height(46.dp).background(col))
        Column(Modifier.weight(1f).padding(horizontal = 8.dp, vertical = 5.dp)) {
            Text(l.timeLabel(), color = Color(0xFFB8B2D6), fontSize = 11.sp, maxLines = 1)
            Text(l.title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            if (l.room.isNotBlank()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.LocationOn, null, tint = Pal.Lilac, modifier = Modifier.size(11.dp))
                    Text(" ${l.room}", color = Color(0xFFB8B2D6), fontSize = 10.sp, maxLines = 1)
                }
            }
        }
        Box(
            Modifier.padding(end = 8.dp).size(28.dp).clip(RoundedCornerShape(8.dp))
                .background(col.copy(alpha = 0.35f)),
            contentAlignment = Alignment.Center
        ) {
            if (l.emoji.isNotBlank()) Text(l.emoji, fontSize = 14.sp)
            else Icon(iconFor(l.icon), null, tint = Color.White, modifier = Modifier.size(18.dp))
        }
    }
}
