package com.example.schedule

import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

object Notifier {
    private const val CH = "reminders_v2"
    private const val OLD_CH = "reminders"
    private val PATTERN = longArrayOf(0, 200, 100, 200)   // 2 коротких сигнала

    /** Запрос разрешения на уведомления (Android 13+). */
    fun askPermission(act: Activity) {
        if (Build.VERSION.SDK_INT >= 33 &&
            act.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            act.requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 77)
        }
    }

    private fun codeOf(id: Long): Int = (id xor (id ushr 32)).toInt() and 0x7fffffff

    private fun pending(
        ctx: Context, code: Int, flag: Int,
        title: String = "", lead: String = "", time: String = "", room: String = ""
    ): PendingIntent? {
        val i = Intent(ctx, AlarmReceiver::class.java)
            .setAction(ctx.packageName + ".REMINDER")
            .putExtra("code", code)
            .putExtra("title", title)
            .putExtra("lead", lead)
            .putExtra("time", time)
            .putExtra("room", room)
        return PendingIntent.getBroadcast(ctx, code, i, flag or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun startOf(l: Lesson, d: LocalDate): LocalDateTime {
        if (l.isAllDay) return d.atTime(8, 0)
        val h = (l.start.substringBefore(":").toIntOrNull() ?: 8).coerceIn(0, 23)
        val m = (l.start.substringAfter(":").toIntOrNull() ?: 0).coerceIn(0, 59)
        return d.atTime(h, m)
    }

    /** Ближайшее срабатывание строго позже now (для повторяющихся - ближайшее вхождение). */
    private fun nextTrigger(l: Lesson, now: LocalDateTime): LocalDateTime? {
        val lead = l.notificationMinutes.toLong()
        val today = now.toLocalDate()
        for (k in 0..370) {
            val d = today.plusDays(k.toLong())
            if (!l.occursOn(d)) continue
            val tr = startOf(l, d).minusMinutes(lead)
            if (tr.isAfter(now)) return tr
        }
        return null
    }

    private fun plural(n: Int, one: String, few: String, many: String): String {
        val a = n % 100
        val b = n % 10
        return if (a in 11..14) many else when (b) {
            1 -> one
            in 2..4 -> few
            else -> many
        }
    }

    private fun leadText(m: Int): String = when {
        m <= 0 -> "начинается сейчас"
        m % 60 == 0 -> {
            val h = m / 60
            "через $h ${plural(h, "час", "часа", "часов")}"
        }
        else -> "через $m ${plural(m, "минуту", "минуты", "минут")}"
    }

    fun rescheduleAll(ctx: Context, list: List<Lesson>) {
        val app = ctx.applicationContext
        val am = app.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val sp = app.getSharedPreferences("notifier", Context.MODE_PRIVATE)
        sp.getStringSet("codes", emptySet())?.forEach { c ->
            val code = c.toIntOrNull() ?: return@forEach
            pending(app, code, PendingIntent.FLAG_NO_CREATE)?.let {
                am.cancel(it)
                it.cancel()
            }
        }
        val now = LocalDateTime.now().plusSeconds(2)
        val codes = HashSet<String>()
        for (l in list) {
            if (l.notificationMinutes < 0) continue
            val tr = nextTrigger(l, now) ?: continue
            val code = codeOf(l.id)
            val lead = if (l.isAllDay) "сегодня весь день" else leadText(l.notificationMinutes)
            val p = pending(
                app, code, PendingIntent.FLAG_UPDATE_CURRENT,
                l.title.ifBlank { "Событие" }, lead, l.timeLabel(), l.room
            ) ?: continue
            val at = tr.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
            val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
            try {
                if (exact) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, p)
                else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, p)
            } catch (e: SecurityException) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, p)
            }
            codes.add(code.toString())
        }
        sp.edit().putStringSet("codes", codes).apply()
    }

    fun rescheduleFromStore(ctx: Context) {
        val json = ctx.getSharedPreferences("schedule", Context.MODE_PRIVATE).getString("json", null) ?: return
        rescheduleAll(ctx, LessonJson.fromJson(json))
    }

    private fun ensureChannel(nm: NotificationManager) {
        if (nm.getNotificationChannel(OLD_CH) != null) nm.deleteNotificationChannel(OLD_CH)
        if (nm.getNotificationChannel(CH) == null) {
            val ch = NotificationChannel(CH, "Напоминания", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "Напоминания о событиях расписания"
            ch.enableVibration(false)   // вибрируем вручную через Vibrator, чтобы не было двойного сигнала
            ch.setSound(null, null)
            ch.enableLights(false)
            nm.createNotificationChannel(ch)
        }
    }

    @Suppress("DEPRECATION")
    private fun vibrate(ctx: Context) {
        try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val f = nm.currentInterruptionFilter
            if (f == NotificationManager.INTERRUPTION_FILTER_NONE ||
                f == NotificationManager.INTERRUPTION_FILTER_ALARMS
            ) return
            val v: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
                (ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                ctx.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (v == null || !v.hasVibrator()) return
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            v.vibrate(VibrationEffect.createWaveform(PATTERN, -1), attrs)
        } catch (e: Exception) {
        }
    }

    fun show(ctx: Context, code: Int, title: String, lead: String, time: String, room: String) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(nm)
        val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
            PendingIntent.getActivity(ctx, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val close = PendingIntent.getBroadcast(
            ctx, code,
            Intent(ctx, NotifDismissReceiver::class.java)
                .setAction(ctx.packageName + ".DISMISS")
                .putExtra("code", code),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val short = listOf(lead, room).filter { it.isNotBlank() }.joinToString(" · ")
        val full = listOf(lead, time, room).filter { it.isNotBlank() }.joinToString("\n")
        val n = NotificationCompat.Builder(ctx, CH)
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle(title)
            .setContentText(short)
            .setStyle(NotificationCompat.BigTextStyle().bigText(full))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setLocalOnly(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .addAction(NotificationCompat.Action.Builder(R.drawable.ic_close, "Закрыть", close).build())
            .build()
        try {
            nm.notify(code, n)
        } catch (e: SecurityException) {
        }
    }

    fun fire(ctx: Context, code: Int, title: String, lead: String, time: String, room: String) {
        show(ctx, code, title, lead, time, room)
        vibrate(ctx)
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        Notifier.fire(
            ctx,
            i.getIntExtra("code", 0),
            i.getStringExtra("title") ?: "Событие",
            i.getStringExtra("lead") ?: "",
            i.getStringExtra("time") ?: "",
            i.getStringExtra("room") ?: ""
        )
        Notifier.rescheduleFromStore(ctx)
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        Notifier.rescheduleFromStore(ctx)
    }
}

/** Кнопка-крестик в уведомлении: просто закрывает его. */
class NotifDismissReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(i.getIntExtra("code", 0))
    }
}
