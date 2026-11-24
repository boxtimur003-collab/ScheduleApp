package com.example.schedule

import android.content.Context
import android.content.Intent
import android.widget.Toast

/**
 * Публичного интента выбора циферблата в документации нет. Перебираем предполагаемые действия
 * (не проверены); если подходящей активности нет, показываем подсказку.
 * true - системный выбор открыт; false - показана подсказка.
 */
private val PICKER_ACTIONS = listOf(
    "android.intent.action.WATCH_FACE_PICKER",
    "com.google.android.wearable.action.WATCH_FACE_PICKER"
)

fun openWatchFacePicker(ctx: Context): Boolean {
    for (action in PICKER_ACTIONS) {
        try {
            ctx.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return true
        } catch (e: Exception) {
        }
    }
    Toast.makeText(
        ctx, "Удерживайте палец на текущем циферблате, чтобы выбрать другой", Toast.LENGTH_LONG
    ).show()
    return false
}
