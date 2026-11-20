package com.example.schedule

import org.json.JSONArray
import org.json.JSONObject

/** day: 1 = Пн ... 7 = Вс */
data class Lesson(
    val id: Long, val day: Int, val start: String, val end: String,
    val subject: String, val room: String, val icon: String
)

object LessonJson {
    fun toJson(list: List<Lesson>): String {
        val arr = JSONArray()
        list.forEach {
            arr.put(JSONObject().put("id", it.id).put("day", it.day).put("start", it.start)
                .put("end", it.end).put("subject", it.subject).put("room", it.room).put("icon", it.icon))
        }
        return arr.toString()
    }

    fun fromJson(s: String): List<Lesson> = try {
        val a = JSONArray(s)
        (0 until a.length()).map {
            val o = a.getJSONObject(it)
            Lesson(o.getLong("id"), o.getInt("day"), o.getString("start"), o.getString("end"),
                o.getString("subject"), o.getString("room"), o.getString("icon"))
        }
    } catch (e: Exception) { emptyList() }
}
