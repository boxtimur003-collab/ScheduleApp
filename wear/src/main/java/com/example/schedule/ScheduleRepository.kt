package com.example.schedule

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

object ScheduleRepository {
    private val _lessons = MutableStateFlow<List<Lesson>>(emptyList())
    val lessons: StateFlow<List<Lesson>> = _lessons.asStateFlow()

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("schedule", Context.MODE_PRIVATE)

    fun init(ctx: Context) {
        _lessons.value = LessonJson.fromJson(prefs(ctx).getString("json", "[]") ?: "[]")
    }

    fun update(ctx: Context, json: String) {
        if (!json.trim().startsWith("[")) return
        prefs(ctx).edit().putString("json", json).apply()
        _lessons.value = LessonJson.fromJson(json)
    }
}
