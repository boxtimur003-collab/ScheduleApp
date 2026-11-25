package com.example.schedule

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay

private data class Reminder(
    val code: Int = 0,
    val title: String = "",
    val lead: String = "",
    val time: String = "",
    val room: String = ""
)

class ReminderActivity : ComponentActivity() {
    private val state = mutableStateOf(Reminder())

    private fun read(i: Intent?): Reminder = Reminder(
        i?.getIntExtra("code", 0) ?: 0,
        i?.getStringExtra("title") ?: "Событие",
        i?.getStringExtra("lead") ?: "",
        i?.getStringExtra("time") ?: "",
        i?.getStringExtra("room") ?: ""
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        state.value = read(intent)
        setContent {
            val r = state.value
            ReminderScreen(r) { dismiss(r.code) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        state.value = read(intent)
    }

    private fun dismiss(code: Int) {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(code)
        finish()
    }
}

@Composable
private fun ReminderScreen(r: Reminder, onClose: () -> Unit) {
    // экран не висит вечно: закрывается сам через минуту
    LaunchedEffect(r.code, r.title) {
        delay(60_000L)
        onClose()
    }
    MaterialTheme {
        Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    r.title, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold,
                    textAlign = TextAlign.Center, maxLines = 2
                )
                Spacer(Modifier.height(4.dp))
                Text(r.lead, color = Pal.Lilac, fontSize = 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                val room = roomLabel(r.room)
                if (room.isNotBlank()) {
                    Spacer(Modifier.height(4.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.LocationOn, null, tint = Pal.Lilac, modifier = Modifier.size(18.dp))
                        Text("  $room", color = Color.White, fontSize = 18.sp)
                    }
                }
                if (r.time.isNotBlank()) {
                    Spacer(Modifier.height(2.dp))
                    Text(r.time, color = Pal.Dim, fontSize = 13.sp)
                }
                Spacer(Modifier.height(12.dp))
                Box(
                    Modifier.size(48.dp).clip(CircleShape).background(Color(0xFF3A3A44)).clickable(onClick = onClose),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Filled.Close, null, tint = Color.White, modifier = Modifier.size(28.dp))
                }
            }
        }
    }
}
