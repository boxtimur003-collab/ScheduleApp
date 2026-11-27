package com.example.schedule

import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Watch
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Icon

/** Закрепляет файл на циферблате и возвращает на экран часов. Нужен выбранный циферблат «Расписание». */
fun pinToFace(ctx: Context, f: WearFile) {
    ctx.getSharedPreferences("files", Context.MODE_PRIVATE).edit().putString("pinned", f.id).apply()
    Toast.makeText(ctx, "Файл на циферблате «Расписание»", Toast.LENGTH_SHORT).show()
    try {
        ctx.startActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    } catch (e: Exception) {
    }
}

@Composable
fun PinButton(f: WearFile) {
    val ctx = LocalContext.current
    Box(
        Modifier.padding(start = 8.dp).size(28.dp).clip(CircleShape)
            .background(Color(0x667C5CFF)).clickable { pinToFace(ctx, f) },
        contentAlignment = Alignment.Center
    ) {
        Icon(Icons.Filled.Watch, "На циферблат", tint = Color.White, modifier = Modifier.size(16.dp))
    }
}
