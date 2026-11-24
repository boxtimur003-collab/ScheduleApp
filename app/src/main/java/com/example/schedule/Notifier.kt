package com.example.schedule

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Телефон больше не уведомляет: расписание уходит на часы, напоминания планируются там.
 * API сохранён, чтобы остальной код компилировался; все вызовы только снимают старые будильники.
 */
object Notifier {
    fun rescheduleAll(ctx: Context, list: List<Lesson>) = cancelAll(ctx)

    fun rescheduleFromStore(ctx: Context) = cancelAll(ctx)

    fun show(ctx: Context, code: Int, title: String, text: String) {}

    /** Снимает будильники, поставленные прошлыми версиями. */
    private fun cancelAll(ctx: Context) {
        val app = ctx.applicationContext
        val sp = app.getSharedPreferences("notifier", Context.MODE_PRIVATE)
        val codes = sp.getStringSet("codes", null)
        if (codes.isNullOrEmpty()) return
        val am = app.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        codes.forEach { c ->
            val code = c.toIntOrNull() ?: return@forEach
            val i = Intent(app, AlarmReceiver::class.java)
                .setAction(app.packageName + ".REMINDER")
                .putExtra("code", code)
            val p = PendingIntent.getBroadcast(
                app, code, i, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            if (p != null) {
                am.cancel(p)
                p.cancel()
            }
        }
        sp.edit().remove("codes").apply()
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {}
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {}
}
