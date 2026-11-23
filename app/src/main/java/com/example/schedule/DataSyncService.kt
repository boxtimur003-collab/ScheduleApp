package com.example.schedule

import android.content.Context
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

object DataSyncService {
    const val PATH = "/schedule"
    const val FILE_PATH = "/file"
    private const val MAX_BYTES = 100_000

    /** Расписание. >0 - число часов; 0 - часов нет; -1 - ошибка; -2 - слишком большой объём. */
    suspend fun send(ctx: Context, json: String): Int = sendTo(ctx, PATH, json)

    /** Шпаргалка: {"id": "...", "text": "...", "time": "HH:mm"}. Коды те же. */
    suspend fun sendFile(ctx: Context, json: String): Int = sendTo(ctx, FILE_PATH, json)

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
