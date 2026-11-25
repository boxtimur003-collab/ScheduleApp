package com.example.schedule

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver

/**
 * Разрешения для напоминаний по очереди: уведомления -> точные будильники -> полноэкранные
 * уведомления -> «поверх других окон». Каждый шаг не больше 2 раз; после возврата из системного
 * окна (onResume) запрашивается следующий. Если страницы настроек на часах нет, показывается подсказка.
 */
object Perms {
    private const val MAX_TRIES = 2

    fun start(act: Activity) {
        if (act is ComponentActivity) {
            act.lifecycle.addObserver(LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_RESUME) ensure(act)
            })
        } else {
            ensure(act)
        }
    }

    private fun step(act: Activity, key: String, needed: Boolean, launch: () -> Unit): Boolean {
        if (!needed) return false
        val sp = act.getSharedPreferences("perms", Context.MODE_PRIVATE)
        val n = sp.getInt(key, 0)
        if (n >= MAX_TRIES) return false
        sp.edit().putInt(key, n + 1).apply()
        launch()
        return true
    }

    private fun open(act: Activity, action: String, key: String) {
        try {
            act.startActivity(Intent(action, Uri.parse("package:" + act.packageName)))
        } catch (e: Exception) {
            act.getSharedPreferences("perms", Context.MODE_PRIVATE).edit().putInt(key, MAX_TRIES).apply()
            Toast.makeText(act, "Разрешите вручную: Настройки → Приложения → Расписание", Toast.LENGTH_LONG).show()
        }
    }

    fun ensure(act: Activity) {
        val needNotif = Build.VERSION.SDK_INT >= 33 &&
            act.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        if (step(act, "notif", needNotif) {
                act.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 77)
            }
        ) return

        val am = act.getSystemService(AlarmManager::class.java)
        val needAlarm = Build.VERSION.SDK_INT >= 31 && am != null && !am.canScheduleExactAlarms()
        if (step(act, "alarm", needAlarm) {
                open(act, Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, "alarm")
            }
        ) return

        val nm = act.getSystemService(NotificationManager::class.java)
        val needFsi = Build.VERSION.SDK_INT >= 34 && nm != null && !nm.canUseFullScreenIntent()
        if (step(act, "fsi", needFsi) {
                open(act, Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, "fsi")
            }
        ) return

        val needOverlay = !Settings.canDrawOverlays(act)
        step(act, "overlay", needOverlay) {
            open(act, Settings.ACTION_MANAGE_OVERLAY_PERMISSION, "overlay")
        }
    }
}
