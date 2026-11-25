package com.example.schedule

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

data class UpdateInfo(val code: Int, val name: String, val apkUrl: String)

/** Формат version.json: { "versionCode": 2, "versionName": "1.1", "apkUrl": "https://github.com/.../app-release.apk" } */
object UpdateChecker {
    private const val REPO = "boxtimur003-collab/ScheduleApp"
    private val configured = REPO.contains('/') && !REPO.contains("ТВОЙ")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private fun fetch(): UpdateInfo? {
        return try {
            val c = URL("https://raw.githubusercontent.com/$REPO/main/version.json?t=" + System.currentTimeMillis())
                .openConnection() as HttpURLConnection
            try {
                c.connectTimeout = 10_000
                c.readTimeout = 10_000
                c.setRequestProperty("Cache-Control", "no-cache")
                if (c.responseCode != HttpURLConnection.HTTP_OK) {
                    null
                } else {
                    val text = c.inputStream.bufferedReader().use { it.readText() }
                    val o = JSONObject(text)
                    UpdateInfo(o.optInt("versionCode", 0), o.optString("versionName", ""), o.optString("apkUrl", ""))
                }
            } finally {
                c.disconnect()
            }
        } catch (e: Exception) {
            null
        }
    }

    fun check(ctx: Context) {
        if (!configured) return
        val app = ctx.applicationContext
        scope.launch {
            val info = fetch() ?: return@launch
            if (info.code <= BuildConfig.VERSION_CODE || !info.apkUrl.startsWith("https://")) return@launch
            val sp = app.getSharedPreferences("updates", Context.MODE_PRIVATE)
            if (sp.getInt("notified", 0) < info.code && NotificationManagerCompat.from(app).areNotificationsEnabled()) {
                UpdateInstaller.notifyAvailable(app, info)
                sp.edit().putInt("notified", info.code).apply()
            }
            if (sp.getInt("watch", 0) < info.code) {
                val json = JSONObject().put("versionCode", info.code).put("versionName", info.name).toString()
                if (DataSyncService.sendUpdate(app, json) > 0) sp.edit().putInt("watch", info.code).apply()
            }
        }
    }
}

object UpdateInstaller {
    private const val CH = "updates"
    private const val ID_AVAILABLE = 7001
    private const val ID_READY = 7002
    private var done: BroadcastReceiver? = null

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("updates", Context.MODE_PRIVATE)

    private fun ensureChannel(nm: NotificationManager) {
        if (nm.getNotificationChannel(CH) == null) {
            nm.createNotificationChannel(NotificationChannel(CH, "Обновления", NotificationManager.IMPORTANCE_DEFAULT))
        }
    }

    /** «Доступно обновление»: нажатие запускает загрузку APK. */
    fun notifyAvailable(ctx: Context, info: UpdateInfo) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(nm)
        val tap = PendingIntent.getBroadcast(
            ctx, ID_AVAILABLE,
            Intent(ctx, UpdateActionReceiver::class.java)
                .putExtra("apkUrl", info.apkUrl)
                .putExtra("versionName", info.name),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val text = if (info.name.isBlank()) "Нажмите, чтобы скачать и установить"
        else "Версия ${info.name}. Нажмите, чтобы скачать и установить"
        val n = NotificationCompat.Builder(ctx, CH)
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle("Доступно обновление")
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setLocalOnly(true)
            .setContentIntent(tap)
            .build()
        try {
            nm.notify(ID_AVAILABLE, n)
        } catch (e: SecurityException) {
        }
    }

    fun startDownload(ctx: Context, url: String, name: String) {
        val app = ctx.applicationContext
        try {
            File(app.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "update.apk").delete()
            val dm = app.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val req = DownloadManager.Request(Uri.parse(url))
                .setTitle("Расписание " + name)
                .setDescription("Загрузка обновления")
                .setMimeType("application/vnd.android.package-archive")
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalFilesDir(app, Environment.DIRECTORY_DOWNLOADS, "update.apk")
            val id = dm.enqueue(req)
            prefs(app).edit().putLong("dl_id", id).apply()
            registerDone(app)
            Toast.makeText(app, "Загрузка обновления…", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Toast.makeText(app, "Не удалось начать загрузку", Toast.LENGTH_LONG).show()
        }
    }

    /** Ресивер завершения загрузки регистрируется в коде: в манифесте неявные рассылки не приходят. */
    private fun registerDone(app: Context) {
        if (done != null) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) {
                val id = i.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
                if (onDownloadComplete(app, id)) {
                    try {
                        app.unregisterReceiver(this)
                    } catch (e: Exception) {
                    }
                    done = null
                }
            }
        }
        ContextCompat.registerReceiver(
            app, r, IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE), ContextCompat.RECEIVER_EXPORTED
        )
        done = r
    }

    /** true - это была наша загрузка (обработана). */
    fun onDownloadComplete(ctx: Context, id: Long): Boolean {
        val app = ctx.applicationContext
        val saved = prefs(app).getLong("dl_id", -1L)
        if (saved < 0 || id != saved) return false
        prefs(app).edit().remove("dl_id").apply()
        var ok = false
        try {
            val dm = app.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            dm.query(DownloadManager.Query().setFilterById(id))?.use { c ->
                if (c.moveToFirst()) {
                    ok = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)) ==
                        DownloadManager.STATUS_SUCCESSFUL
                }
            }
        } catch (e: Exception) {
        }
        val file = File(app.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "update.apk")
        if (!ok || !file.exists()) {
            Toast.makeText(app, "Не удалось скачать обновление", Toast.LENGTH_LONG).show()
            return true
        }
        notifyReady(app, file)
        return true
    }

    /** «Обновление загружено»: нажатие открывает установщик (FileProvider + ACTION_VIEW). */
    private fun notifyReady(app: Context, file: File) {
        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(nm)
        val uri = FileProvider.getUriForFile(app, app.packageName + ".fileprovider", file)
        val install = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        val pi = PendingIntent.getActivity(
            app, ID_READY, install, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val n = NotificationCompat.Builder(app, CH)
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle("Обновление загружено")
            .setContentText("Нажмите, чтобы установить")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setLocalOnly(true)
            .setContentIntent(pi)
            .build()
        try {
            nm.notify(ID_READY, n)
        } catch (e: SecurityException) {
        }
    }
}

class UpdateActionReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        val url = i.getStringExtra("apkUrl") ?: return
        UpdateInstaller.startDownload(ctx, url, i.getStringExtra("versionName") ?: "")
    }
}

/** Запрос разрешения на уведомления (Android 13+) и проверка обновлений при запуске. */
@Composable
fun UpdateEffect() {
    val ctx = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { _ ->
        UpdateChecker.check(ctx)
    }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(ctx, android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            launcher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        } else {
            UpdateChecker.check(ctx)
        }
    }
}
