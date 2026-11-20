package com.example.schedule

import android.content.Context
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

object DataSyncService {
    const val PATH = "/schedule"

    /** Возвращает число часов, которым ушло сообщение, или -1 при ошибке. */
    suspend fun send(ctx: Context, json: String): Int = try {
        val nodes = Wearable.getNodeClient(ctx).connectedNodes.await()
        nodes.forEach {
            Wearable.getMessageClient(ctx).sendMessage(it.id, PATH, json.toByteArray()).await()
        }
        nodes.size
    } catch (e: Exception) { -1 }
}
