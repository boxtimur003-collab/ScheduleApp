package com.example.schedule

import android.content.Context
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalTime
import java.time.format.DateTimeFormatter

data class WearFile(val id: String, val name: String, val text: String, val time: String)

/** Полученные шпаргалки: список JSON-объектов в SharedPreferences. */
object FileStore {
    private const val MAX = 50
    private val _files = MutableStateFlow<List<WearFile>>(emptyList())
    val files: StateFlow<List<WearFile>> = _files.asStateFlow()

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("files", Context.MODE_PRIVATE)

    private fun read(ctx: Context): List<WearFile> = try {
        val a = JSONArray(prefs(ctx).getString("json", "[]") ?: "[]")
        (0 until a.length()).map {
            val o = a.getJSONObject(it)
            WearFile(
                o.getString("id"), o.optString("name", "Файл"),
                o.optString("text", ""), o.optString("time", "")
            )
        }
    } catch (e: Exception) {
        emptyList()
    }

    private fun write(ctx: Context, list: List<WearFile>) {
        val a = JSONArray()
        list.forEach {
            a.put(JSONObject().put("id", it.id).put("name", it.name).put("text", it.text).put("time", it.time))
        }
        prefs(ctx).edit().putString("json", a.toString()).apply()
        _files.value = list
    }

    fun init(ctx: Context) {
        _files.value = read(ctx)
    }

    /** json: {"id": "...", "text": "...", "time": "HH:mm"} */
    @Synchronized
    fun add(ctx: Context, json: String) {
        val o = try { JSONObject(json) } catch (e: Exception) { return }
        val text = o.optString("text", "")
        if (text.isBlank()) return
        val id = o.optString("id", "").ifBlank { System.currentTimeMillis().toString() }
        val time = o.optString("time", "").ifBlank {
            LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm"))
        }
        val cur = read(ctx)
        if (cur.any { it.id == id }) return
        val p = prefs(ctx)
        val n = p.getInt("counter", 0) + 1
        p.edit().putInt("counter", n).apply()
        write(ctx, (cur + WearFile(id, "Файл $n", text, time)).takeLast(MAX))
    }

    @Synchronized
    fun delete(ctx: Context, id: String) {
        write(ctx, read(ctx).filter { it.id != id })
    }
}

class DataSyncService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        try {
            val body = String(event.data, Charsets.UTF_8)
            when (event.path) {
                "/schedule" -> ScheduleRepository.update(applicationContext, body)
                "/file" -> FileStore.add(applicationContext, body)
            }
        } catch (e: Exception) {
            // повреждённые данные игнорируем, на часах остаётся прежнее состояние
        }
    }
}
