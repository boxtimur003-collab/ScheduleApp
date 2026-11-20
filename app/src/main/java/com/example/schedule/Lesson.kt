package com.example.schedule

import androidx.compose.ui.graphics.Color
import org.json.JSONArray
import org.json.JSONObject
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * date: "2026-11-20" (для разовых; для повторяющихся - дата первого вхождения)
 * recurrence: NONE | DAILY | WEEKLY | MONTHLY | YEARLY
 * color: "#RRGGBB"
 */
data class Lesson(
    val id: Long,
    val title: String,
    val date: String,
    val recurrence: String = "NONE",
    val isAllDay: Boolean = false,
    val color: String = "#7C5CFF",
    val start: String = "08:30",
    val end: String = "09:15",
    val room: String = "",
    val icon: String = "other",
    val emoji: String = ""
)

val PALETTE = listOf(
    "#7C5CFF", "#4D8DFF", "#4CC36B", "#F2B72E",
    "#FF6B6B", "#FF8A4C", "#E85DBB", "#9B98AD"
)

val RECURRENCES = listOf(
    "NONE" to "Не повторять",
    "DAILY" to "Каждый день",
    "WEEKLY" to "Каждую неделю",
    "MONTHLY" to "Каждый месяц",
    "YEARLY" to "Каждый год"
)

fun recurrenceLabel(r: String): String = RECURRENCES.firstOrNull { it.first == r }?.second ?: "Не повторять"

fun recurrenceStatus(r: String): String = when (r) {
    "DAILY" -> "Каждый день"
    "WEEKLY" -> "Каждую неделю"
    "MONTHLY" -> "Каждый месяц"
    "YEARLY" -> "Каждый год"
    else -> "Разовое"
}

fun parseColor(hex: String): Color = try {
    Color(android.graphics.Color.parseColor(hex))
} catch (e: Exception) {
    Color(0xFF7C5CFF)
}

fun Lesson.timeLabel(): String = if (isAllDay) "Весь день" else "$start – $end"

fun Lesson.occursOn(d: LocalDate): Boolean {
    val base = try { LocalDate.parse(date) } catch (e: Exception) { return false }
    if (d.isBefore(base)) return false
    return when (recurrence) {
        "DAILY" -> true
        "WEEKLY" -> ChronoUnit.DAYS.between(base, d) % 7L == 0L
        "MONTHLY" -> d.dayOfMonth == minOf(base.dayOfMonth, d.lengthOfMonth())
        "YEARLY" -> d.month == base.month && d.dayOfMonth == minOf(base.dayOfMonth, d.lengthOfMonth())
        else -> d == base
    }
}

object LessonJson {
    fun toJson(list: List<Lesson>): String {
        val arr = JSONArray()
        list.forEach {
            arr.put(
                JSONObject()
                    .put("id", it.id)
                    .put("title", it.title)
                    .put("date", it.date)
                    .put("recurrence", it.recurrence)
                    .put("isAllDay", it.isAllDay)
                    .put("color", it.color)
                    .put("start", it.start)
                    .put("end", it.end)
                    .put("room", it.room)
                    .put("icon", it.icon)
                    .put("emoji", it.emoji)
            )
        }
        return arr.toString()
    }

    fun fromJson(s: String): List<Lesson> = try {
        val a = JSONArray(s)
        (0 until a.length()).mapNotNull { i ->
            try { parse(a.getJSONObject(i)) } catch (e: Exception) { null }
        }
    } catch (e: Exception) {
        emptyList()
    }

    private fun parse(o: JSONObject): Lesson {
        var date = o.optString("date", "")
        var rec = o.optString("recurrence", "NONE")
        if (date.isEmpty()) {
            val day = o.optInt("day", 1).coerceIn(1, 7)
            date = LocalDate.now().with(DayOfWeek.of(day)).minusWeeks(8).toString()
            rec = "WEEKLY"
        }
        return Lesson(
            id = o.getLong("id"),
            title = o.optString("title", o.optString("subject", "")),
            date = date,
            recurrence = rec,
            isAllDay = o.optBoolean("isAllDay", false),
            color = o.optString("color", "#7C5CFF"),
            start = o.optString("start", "08:30"),
            end = o.optString("end", "09:15"),
            room = o.optString("room", ""),
            icon = o.optString("icon", "other"),
            emoji = o.optString("emoji", "")
        )
    }
}
