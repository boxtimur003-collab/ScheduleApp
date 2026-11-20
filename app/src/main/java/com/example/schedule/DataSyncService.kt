package com.example.schedule

import android.content.Context
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

object DataSyncService {
    const val PATH = "/schedule"
    private const val MAX_BYTES = 100_000

    suspend fun send(ctx: Context, json: String): Int = try {
        val bytes = json.toByteArray(Charsets.UTF_8)
        if (bytes.size > MAX_BYTES) {
            -2
        } else {
            val nodes = Wearable.getNodeClient(ctx).connectedNodes.await()
            nodes.forEach {
                Wearable.getMessageClient(ctx).sendMessage(it.id, PATH, bytes).await()
            }
            nodes.size
        }
    } catch (e: Exception) {
        -1
    }
}
