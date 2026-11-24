package com.example.schedule

import androidx.compose.ui.graphics.Color
import org.json.JSONArray
import org.json.JSONObject
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * date: "2026-11-20" (разовое - дата события, повторяющееся - дата первого вхождения)
 * recurrence: NONE | DAILY | WEEKLY | MONTHLY | YEARLY
 * exceptions: даты "yyyy-MM-dd", в которые повторяющееся событие НЕ показывается
 * notificationMinutes: -1 = не напоминать, 0 = в момент начала, N = за N минут
 */
data class Lesson(
    val id: Long,
    val title: String,
    val date: String,
    val recurrence: String = "NONE",
    val isAllDay: Boolean = false,
    val color: String = "#1A73E8",
    val start: String = "08:30",
    val end: String = "09:15",
    val room: String = "",
    val icon: String = "other",
    val emoji: String = "",
    val exceptions: List<String> = emptyList(),
    val notificationMinutes: Int = -1
)

val PALETTE = listOf(
    "#1A73E8", "#0B8043", "#D50000", "#F4511E",
    "#F6BF26", "#8E24AA", "#039BE5", "#616161"
)

val RECURRENCES = listOf(
    "NONE" to "Не повторять",
    "DAILY" to "Каждый день",
    "WEEKLY" to "Каждую неделю",
    "MONTHLY" to "Каждый месяц",
    "YEARLY" to "Каждый год"
)

val NOTIFY_OPTIONS = listOf(
    -1 to "Не напоминать",
    0 to "В момент начала",
    5 to "За 5 мин",
    15 to "За 15 мин",
    30 to "За 30 мин",
    60 to "За 1 час"
)

fun notifyLabel(m: Int): String =
    NOTIFY_OPTIONS.firstOrNull { it.first == m }?.second ?: if (m < 0) "Не напоминать" else "За $m мин"

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
    Color(0xFF1A73E8)
}

fun parseDate(s: String): LocalDate = try {
    LocalDate.parse(s)
} catch (e: Exception) {
    LocalDate.now()
}

fun Lesson.timeLabel(): String = if (isAllDay) "Весь день" else "$start – $end"

fun Lesson.occursOn(d: LocalDate): Boolean {
    if (exceptions.isNotEmpty() && exceptions.contains(d.toString())) return false
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
                    .put("exceptions", JSONArray(it.exceptions))
                    .put("notificationMinutes", it.notificationMinutes)
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
        val ex = o.optJSONArray("exceptions")
        val exceptions = if (ex == null) emptyList() else (0 until ex.length()).map { ex.getString(it) }
        return Lesson(
            id = o.getLong("id"),
            title = o.optString("title", o.optString("subject", "")),
            date = date,
            recurrence = rec,
            isAllDay = o.optBoolean("isAllDay", false),
            color = o.optString("color", "#1A73E8"),
            start = o.optString("start", "08:30"),
            end = o.optString("end", "09:15"),
            room = o.optString("room", ""),
            icon = o.optString("icon", "other"),
            emoji = o.optString("emoji", ""),
            exceptions = exceptions,
            notificationMinutes = o.optInt("notificationMinutes", -1)
        )
    }
}
