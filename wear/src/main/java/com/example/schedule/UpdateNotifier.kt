package com.example.schedule

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject

/** Получает с телефона /update и показывает уведомление (один раз для каждой версии). */
object UpdateNotifier {
    private const val CH = "updates"
    private const val ID = 7003

    fun show(ctx: Context, json: String) {
        val app = ctx.applicationContext
        val o = try { JSONObject(json) } catch (e: Exception) { return }
        val code = o.optInt("versionCode", 0)
        val name = o.optString("versionName", "")
        if (code <= BuildConfig.VERSION_CODE) return
        if (!NotificationManagerCompat.from(app).areNotificationsEnabled()) return
        val sp = app.getSharedPreferences("updates", Context.MODE_PRIVATE)
        if (sp.getInt("shown", 0) >= code) return

        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CH) == null) {
            nm.createNotificationChannel(NotificationChannel(CH, "Обновления", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = app.packageManager.getLaunchIntentForPackage(app.packageName)?.let {
            PendingIntent.getActivity(app, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val big = if (name.isBlank()) "Откройте приложение на телефоне"
        else "Версия $name.\nОткройте приложение на телефоне"
        val n = NotificationCompat.Builder(app, CH)
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle("Доступно обновление")
            .setContentText("Откройте приложение на телефоне")
            .setStyle(NotificationCompat.BigTextStyle().bigText(big))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setLocalOnly(true)
            .setContentIntent(open)
            .build()
        try {
            nm.notify(ID, n)
            sp.edit().putInt("shown", code).apply()
        } catch (e: SecurityException) {
        }
    }
}
