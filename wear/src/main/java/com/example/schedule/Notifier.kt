package com.example.schedule

import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

/** «100» -> «Каб. 100»; если уже написано слово, остаётся как есть. */
fun roomLabel(room: String): String {
    val r = room.trim()
    return if (r.isNotEmpty() && r[0].isDigit()) "Каб. $r" else r
}

object Notifier {
    private const val CH = "reminders_v3"
    private val OLD_CHANNELS = listOf("reminders", "reminders_v2")
    private val PATTERN = longArrayOf(0, 200, 100, 200)   // 2 коротких сигнала
    private const val WITH_SOUND = true                   // false = только вибрация

    /** Последовательный запрос разрешений (уведомления, будильники, полный экран, поверх окон). */
    fun askPermission(act: Activity) = Perms.start(act)

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

    fun leadText(m: Int): String = when {
        m <= 0 -> "начинается сейчас"
        m % 60 == 0 -> "через ${m / 60} ч"
        else -> "через $m мин"
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
        OLD_CHANNELS.forEach { if (nm.getNotificationChannel(it) != null) nm.deleteNotificationChannel(it) }
        if (nm.getNotificationChannel(CH) == null) {
            val ch = NotificationChannel(CH, "Напоминания", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "Напоминания о событиях расписания"
            ch.enableVibration(true)
            ch.vibrationPattern = PATTERN
            if (WITH_SOUND) {
                ch.setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            } else {
                ch.setSound(null, null)
            }
            ch.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            nm.createNotificationChannel(ch)
        }
    }

    /** Показ напоминания: уведомление с полноэкранным интентом + крестик «Закрыть». */
    fun fire(ctx: Context, code: Int, title: String, lead: String, time: String, room: String) {
        val app = ctx.applicationContext
        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(nm)
        val full = Intent(app, ReminderActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra("code", code)
            .putExtra("title", title)
            .putExtra("lead", lead)
            .putExtra("time", time)
            .putExtra("room", room)
        val fs = PendingIntent.getActivity(
            app, code, full, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val close = PendingIntent.getBroadcast(
            app, code,
            Intent(app, NotifDismissReceiver::class.java)
                .setAction(app.packageName + ".DISMISS")
                .putExtra("code", code),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val rl = roomLabel(room)
        val short = listOf(lead, rl).filter { it.isNotBlank() }.joinToString(" · ")
        val big = listOf(lead, time, rl).filter { it.isNotBlank() }.joinToString("\n")
        val n = NotificationCompat.Builder(app, CH)
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle(title)
            .setContentText(short)
            .setStyle(NotificationCompat.BigTextStyle().bigText(big))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setLocalOnly(true)
            .setTimeoutAfter(10 * 60 * 1000L)
            .setFullScreenIntent(fs, true)
            .setContentIntent(fs)
            .addAction(NotificationCompat.Action.Builder(R.drawable.ic_close, "Закрыть", close).build())
            .build()
        try {
            nm.notify(code, n)
        } catch (e: SecurityException) {
        }
        // если выдано «поверх других окон», окно открывается сразу, даже когда экран включён
        try {
            if (Settings.canDrawOverlays(app)) app.startActivity(full)
        } catch (e: Exception) {
        }
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

/** Крестик в уведомлении: просто закрывает его. */
class NotifDismissReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(i.getIntExtra("code", 0))
    }
}
