@file:OptIn(ExperimentalFoundationApi::class)

package com.example.schedule

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.abs

private const val SW_BASE = 36500
private const val SW_COUNT = 73001

private fun swPage(anchor: LocalDate, d: LocalDate): Int =
    (SW_BASE + ChronoUnit.DAYS.between(anchor, d)).toInt().coerceIn(0, SW_COUNT - 1)

/** Список событий выбранного дня: свайп влево/вправо переключает день. */
@Composable
fun DayEventsPager(
    selected: LocalDate,
    lessons: List<Lesson>,
    anchor: LocalDate,
    nested: NestedScrollConnection,
    onSelect: (LocalDate) -> Unit,
    onOpen: (Lesson, LocalDate) -> Unit,
    modifier: Modifier = Modifier
) {
    val c = C
    val pager = rememberPagerState(initialPage = swPage(anchor, selected)) { SW_COUNT }
    val selNow by rememberUpdatedState(selected)
    val onSelectNow by rememberUpdatedState(onSelect)

    // свайп списка -> выбранная дата
    LaunchedEffect(pager) {
        snapshotFlow { pager.settledPage }.collect { p ->
            val d = anchor.plusDays((p - SW_BASE).toLong())
            if (d != selNow) onSelectNow(d)
        }
    }
    // выбранная дата (календарь, кнопка «сегодня») -> страница списка
    LaunchedEffect(selected) {
        val target = swPage(anchor, selected)
        if (pager.currentPage != target) {
            if (abs(pager.currentPage - target) > 3) pager.scrollToPage(target)
            else pager.animateScrollToPage(target)
        }
    }

    HorizontalPager(state = pager, modifier = modifier) { page ->
        val date = anchor.plusDays((page - SW_BASE).toLong())
        val list = remember(lessons, date) {
            lessons.filter { it.occursOn(date) }
                .sortedWith(compareByDescending<Lesson> { it.isAllDay }.thenBy { it.start })
        }
        LazyColumn(
            Modifier.fillMaxSize().nestedScroll(nested),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 88.dp)
        ) {
            if (list.isEmpty()) {
                item { Text("Нет событий", color = c.sub, modifier = Modifier.padding(vertical = 8.dp)) }
            }
            items(list, key = { it.id }) { l -> LessonCard(l, null) { onOpen(l, date) } }
        }
    }
}
