package com.example.schedule

import android.content.Context

class ScheduleRepository(ctx: Context) {
    private val sp = ctx.getSharedPreferences("schedule", Context.MODE_PRIVATE)

    fun load(): List<Lesson> {
        val s = sp.getString("json", null) ?: return defaults().also { save(it) }
        return LessonJson.fromJson(s)
    }

    fun save(list: List<Lesson>) {
        sp.edit().putString("json", LessonJson.toJson(list)).apply()
    }

    private fun defaults() = listOf(
        Lesson(1, 3, "08:30", "09:15", "Математика", "101", "math"),
        Lesson(2, 3, "09:25", "10:10", "Физика", "203", "physics"),
        Lesson(3, 3, "10:25", "11:10", "Информатика", "305", "it"),
        Lesson(4, 3, "11:20", "12:05", "История", "110", "history"),
        Lesson(5, 4, "08:30", "09:15", "Русский язык", "204", "lit"),
        Lesson(6, 4, "09:25", "10:10", "Биология", "301", "bio"),
        Lesson(7, 4, "10:25", "11:10", "Химия", "207", "chem")
    )
}
