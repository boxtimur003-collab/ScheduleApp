package com.example.schedule

import android.content.Context
import java.time.DayOfWeek
import java.time.LocalDate

class ScheduleRepository(ctx: Context) {
    private val sp = ctx.getSharedPreferences("schedule", Context.MODE_PRIVATE)

    fun load(): List<Lesson> {
        val s = sp.getString("json", null) ?: return defaults().also { save(it) }
        return LessonJson.fromJson(s)
    }

    fun save(list: List<Lesson>) {
        sp.edit().putString("json", LessonJson.toJson(list)).apply()
    }

    private fun weekly(
        id: Long, dow: DayOfWeek, start: String, end: String,
        title: String, room: String, icon: String, color: String
    ) = Lesson(
        id = id, title = title,
        date = LocalDate.now().with(dow).minusWeeks(8).toString(),
        recurrence = "WEEKLY", isAllDay = false, color = color,
        start = start, end = end, room = room, icon = icon, emoji = "",
        exceptions = emptyList()
    )

    private fun defaults() = listOf(
        weekly(1, DayOfWeek.WEDNESDAY, "08:30", "09:15", "Математика", "Каб. 101", "math", "#8E24AA"),
        weekly(2, DayOfWeek.WEDNESDAY, "09:25", "10:10", "Физика", "Каб. 203", "physics", "#1A73E8"),
        weekly(3, DayOfWeek.WEDNESDAY, "10:25", "11:10", "Информатика", "Каб. 305", "it", "#0B8043"),
        weekly(4, DayOfWeek.WEDNESDAY, "11:20", "12:05", "История", "Каб. 110", "history", "#F6BF26"),
        weekly(5, DayOfWeek.THURSDAY, "08:30", "09:15", "Русский язык", "Каб. 204", "lit", "#F4511E"),
        weekly(6, DayOfWeek.THURSDAY, "09:25", "10:10", "Биология", "Каб. 301", "bio", "#0B8043"),
        weekly(7, DayOfWeek.THURSDAY, "10:25", "11:10", "Химия", "Каб. 207", "chem", "#039BE5")
    )
}
