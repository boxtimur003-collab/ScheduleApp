package com.example.schedule

import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

class DataSyncService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path == "/schedule") {
            ScheduleRepository.update(applicationContext, String(event.data))
        }
    }
}
