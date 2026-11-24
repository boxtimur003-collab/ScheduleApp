#!/data/data/com.termux/files/usr/bin/bash
# Что делает скрипт (build.gradle.kts не меняется):
#  ТЕЛЕФОН: app/Notifier.kt становится заглушкой. Уведомлений нет, ранее поставленные будильники снимаются
#           при первом запуске приложения. Поле «Напоминание» остаётся и уходит на часы вместе с расписанием.
#  ЧАСЫ:    wear/Notifier.kt: AlarmManager по notificationMinutes. Уведомление: название, «через X минут»
#           (или «начинается сейчас»), время, кабинет, кнопка-крестик «Закрыть», setLocalOnly(true).
#           Вибрация через Vibrator/VibratorManager, паттерн 0-200-100-200. Вибрация канала отключена,
#           чтобы не было двойного сигнала. При режиме «Не беспокоить» (полная тишина/только будильники)
#           вибрации нет. Канал пересоздаётся (reminders -> reminders_v2).
#           Меню: третья кнопка «Циферблат» (WatchFacePicker.kt).
#  Маркеры в манифесте часов переписываются целиком (добавлены VIBRATE и NotifDismissReceiver).
set +H
cd "${1:-$HOME/ScheduleApp}" || { echo 'Папка проекта не найдена'; exit 1; }

AOS=$(find app -name MainActivity.kt -not -path '*/build/*' 2>/dev/null | head -1)
WOS=$(find wear -name MainActivity.kt -not -path '*/build/*' 2>/dev/null | head -1)
WMAN=$(find wear -name AndroidManifest.xml -not -path '*/build/*' 2>/dev/null | head -1)
if [ -z "$AOS" ] || [ -z "$WOS" ] || [ -z "$WMAN" ]; then
  echo 'Файлы проекта не найдены. Запусти из корня проекта'; exit 1
fi
ADIR=$(dirname "$AOS")
WDIR=$(dirname "$WOS")
WRES="$(dirname "$WMAN")/res"
APKG=$(grep -m1 '^package' "$AOS" | tr -d '\r' | sed 's/^package[[:space:]]*//; s/[[:space:]]*$//')
WPKG=$(grep -m1 '^package' "$WOS" | tr -d '\r' | sed 's/^package[[:space:]]*//; s/[[:space:]]*$//')
[ -z "$APKG" ] && APKG="com.example.schedule"
[ -z "$WPKG" ] && WPKG="$APKG"
echo "APP: DIR=$ADIR PKG=$APKG"
echo "WEAR: DIR=$WDIR PKG=$WPKG"
mkdir -p "$WRES/drawable"

# ======================= ТЕЛЕФОН: Notifier.kt (уведомления отключены) =======================
cat << 'KT_EOF' > "$ADIR/Notifier.kt"
package PKG__

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
KT_EOF

# телефон больше не запрашивает разрешение на уведомления
sed -i '/^    NotifPermission()$/d' "$AOS"

# ======================= ЧАСЫ: ресурсы =======================
cat << 'KT_EOF' > "$WRES/drawable/ic_close.xml"
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF" android:pathData="M19,6.41L17.59,5 12,10.59 6.41,5 5,6.41 10.59,12 5,17.59 6.41,19 12,13.41 17.59,19 19,17.59 13.41,12z" />
</vector>
KT_EOF

cat << 'KT_EOF' > "$WRES/drawable/ic_notif.xml"
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF" android:pathData="M12,22c1.1,0 2,-0.9 2,-2h-4c0,1.1 0.89,2 2,2zM18,16v-5c0,-3.07 -1.64,-5.64 -4.5,-6.32V4c0,-0.83 -0.67,-1.5 -1.5,-1.5s-1.5,0.67 -1.5,1.5v0.68C7.64,5.36 6,7.92 6,11v5l-2,2v1h16v-1l-2,-2z" />
</vector>
KT_EOF

# ======================= ЧАСЫ: AndroidManifest.xml =======================
cat << 'KT_EOF' > "$WMAN"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-feature android:name="android.hardware.type.watch" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.VIBRATE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.USE_EXACT_ALARM" />
    <application
        android:allowBackup="true"
        android:icon="@drawable/ic_launcher"
        android:label="@string/app_name"
        android:theme="@style/Theme.Schedule">
        <meta-data android:name="com.google.android.wearable.standalone" android:value="true" />
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service android:name=".DataSyncService" android:exported="true">
            <intent-filter>
                <action android:name="com.google.android.gms.wearable.MESSAGE_RECEIVED" />
                <data android:scheme="wear" android:host="*" android:pathPrefix="/" />
            </intent-filter>
        </service>
        <receiver android:name=".AlarmReceiver" android:exported="false" />
        <receiver android:name=".NotifDismissReceiver" android:exported="false" />
        <receiver android:name=".BootReceiver" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            </intent-filter>
        </receiver>
    </application>
</manifest>
KT_EOF

# ======================= ЧАСЫ: Notifier.kt =======================
cat << 'KT_EOF' > "$WDIR/Notifier.kt"
package PKG__

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
KT_EOF

# ======================= ЧАСЫ: WatchFacePicker.kt =======================
cat << 'KT_EOF' > "$WDIR/WatchFacePicker.kt"
package PKG__

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
KT_EOF

# ======================= ЧАСЫ: патчи MainActivity.kt =======================
# вернуть WearApp, если после отката осталось только переименованное WearAppOld
if grep -q 'fun WearAppOld' "$WOS" && ! grep -rqs 'fun WearApp()' "$WDIR"; then
  sed -i 's/^fun WearAppOld() {$/fun WearApp() {/' "$WOS"
  echo 'WearAppOld переименован обратно в WearApp'
fi

if ! grep -q 'openWatchFacePicker' "$WOS"; then
  sed -i 's/^fun MenuPanel(filesCount: Int, onDates: () -> Unit, onFiles: () -> Unit) {$/fun MenuPanel(filesCount: Int, onDates: () -> Unit, onFiles: () -> Unit, onFace: () -> Unit = {}) {/' "$WOS"
  sed -i '/MenuButton(Icons.Filled.Description,/a\
            MenuButton(Icons.Filled.Watch, "Циферблат", onFace)' "$WOS"
  sed -i 's|onFiles = { overlay = Overlay.FILES }|onFiles = { overlay = Overlay.FILES },\n                        onFace = { openWatchFacePicker(ctx) }|' "$WOS"
fi

# разрешение на уведомления и перепланирование при запуске приложения
if ! grep -q 'Notifier.askPermission' "$WOS"; then
  sed -i '/^        FileStore.init(this)$/a\
        Notifier.askPermission(this)\
        Notifier.rescheduleFromStore(this)' "$WOS"
fi

# ======================= Подстановка пакета =======================
sed -i "s/PKG__/${APKG}/g" "$ADIR/Notifier.kt"
for f in Notifier.kt WatchFacePicker.kt; do
  sed -i "s/PKG__/${WPKG}/g" "$WDIR/$f"
done

# ======================= Проверка патчей =======================
chk() { grep -q "$1" "$2" || echo "!! $3"; }
chk 'notificationMinutes' "$ADIR/Lesson.kt" 'телефон: в Lesson.kt нет notificationMinutes (запусти прошлый скрипт)'
chk 'notificationMinutes' "$WDIR/Lesson.kt" 'часы: в Lesson.kt нет notificationMinutes (скопируй Lesson.kt из app)'
chk 'fun WearApp()' "$WOS" 'часы: в MainActivity.kt нет WearApp()'
chk 'onFace: () -> Unit' "$WOS" 'часы: не пропатчена сигнатура MenuPanel (файл изменён вручную?)'
chk 'Notifier.askPermission' "$WOS" 'часы: не вставлен запрос разрешения (нет строки FileStore.init(this)?)'
chk 'onFace = { openWatchFacePicker(ctx) }' "$WOS" 'часы: не вставлен вызов в MenuPanel(...)'
chk 'val ctx = LocalContext.current' "$WOS" 'часы: в WearApp нет val ctx = LocalContext.current (нужен для кнопки)'
chk 'Notifier.rescheduleAll' "$WDIR/DataSyncService.kt" 'часы: DataSyncService не вызывает Notifier.rescheduleAll (расписание перепланируется только при запуске приложения)'

echo 'Готово!'
echo 'Дальше: git add . && git commit -m "Watch-only reminders with vibration, watch face button" && git push'
