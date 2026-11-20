@file:OptIn(ExperimentalFoundationApi::class)

package com.example.schedule

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

private const val RANGE = 30

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ScheduleRepository.init(this)
        setContent { WearApp() }
    }
}

@Composable
fun WearApp() {
    val lessons by ScheduleRepository.lessons.collectAsState()
    var detail by remember { mutableStateOf<Lesson?>(null) }
    val today = remember { LocalDate.now() }
    val pager = rememberPagerState(initialPage = RANGE) { RANGE * 2 + 1 }
    BackHandler(enabled = detail != null) { detail = null }

    MaterialTheme {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            val d = detail
            if (d == null) {
                HorizontalPager(state = pager) { page ->
                    DayPage(today.plusDays((page - RANGE).toLong()), lessons) { detail = it }
                }
            } else {
                DetailScreen(d) { detail = null }
            }
        }
    }
}

@Composable
fun DayPage(date: LocalDate, all: List<Lesson>, onOpen: (Lesson) -> Unit) {
    val day = remember(all, date) {
        all.filter { it.occursOn(date) }
            .sortedWith(compareByDescending<Lesson> { it.isAllDay }.thenBy { it.start })
    }
    val title = date.format(DateTimeFormatter.ofPattern("EEE, d MMM", Locale("ru")))
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
                contentPadding = PaddingValues(top = 56.dp, bottom = 36.dp, start = 14.dp, end = 14.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) { items(day) { WearCard(it) { onOpen(it) } } }
        }
        Text(
            "‹   $title   ›", color = Pal.Text, fontSize = 14.sp, fontWeight = FontWeight.Medium,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 20.dp)
        )
    }
}

@Composable
fun WearCard(l: Lesson, onClick: () -> Unit) {
    val col = parseColor(l.color)
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Pal.Card)
            .clickable(onClick = onClick).padding(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(4.dp).height(36.dp).clip(RoundedCornerShape(2.dp)).background(col))
        Column(Modifier.weight(1f).padding(start = 8.dp)) {
            Text(l.timeLabel(), color = Pal.Dim, fontSize = 12.sp, maxLines = 1)
            Text(l.title, color = Pal.Text, fontSize = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        }
        Box(
            Modifier.size(34.dp).clip(RoundedCornerShape(10.dp)).background(col.copy(alpha = 0.3f)),
            contentAlignment = Alignment.Center
        ) {
            if (l.emoji.isNotBlank()) Text(l.emoji, fontSize = 18.sp)
            else Icon(iconFor(l.icon), null, tint = col, modifier = Modifier.size(22.dp))
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
