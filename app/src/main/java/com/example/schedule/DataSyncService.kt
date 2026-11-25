package com.example.schedule

import android.content.Context
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await
import org.json.JSONObject

object DataSyncService {
    const val PATH = "/schedule"
    const val FILE_PATH = "/file"
    const val FILE_DELETE_PATH = "/file_delete"
    private const val MAX_BYTES = 100_000

    /** Расписание. >0 - число часов; 0 - часов нет; -1 - ошибка; -2 - слишком большой объём. */
    suspend fun send(ctx: Context, json: String): Int = sendTo(ctx, PATH, json)

    /** Шпаргалка: сначала сохраняется в истории на телефоне, затем уходит на часы (перезаписывая по id). */
    suspend fun sendFile(ctx: Context, json: String): Int {
        val o = try { JSONObject(json) } catch (e: Exception) { return -1 }
        val f = SentStore.upsert(ctx, o.optString("id"), o.optString("name"), o.optString("text"), o.optString("time"))
        return sendTo(ctx, FILE_PATH, SentStore.toJson(f))
    }

    suspend fun sendFileDelete(ctx: Context, id: String): Int = sendTo(ctx, FILE_DELETE_PATH, id)

    const val UPDATE_PATH = "/update"

    /** Информация об обновлении для часов: {"versionCode": N, "versionName": "..."}. */
    suspend fun sendUpdate(ctx: Context, json: String): Int = sendTo(ctx, UPDATE_PATH, json)

    private suspend fun sendTo(ctx: Context, path: String, payload: String): Int = try {
        val bytes = payload.toByteArray(Charsets.UTF_8)
        if (bytes.size > MAX_BYTES) {
            -2
        } else {
            val nodes = Wearable.getNodeClient(ctx).connectedNodes.await()
            nodes.forEach {
                Wearable.getMessageClient(ctx).sendMessage(it.id, path, bytes).await()
            }
            nodes.size
        }
    } catch (e: Exception) {
        -1
    }
}
