#!/data/data/com.termux/files/usr/bin/bash
set +H
cd "${1:-$HOME/ScheduleApp}" || { echo 'Папка проекта не найдена'; exit 1; }

AOS=$(find app -name MainActivity.kt -not -path '*/build/*' 2>/dev/null | head -1)
WOS=$(find wear -name MainActivity.kt -not -path '*/build/*' 2>/dev/null | head -1)
WMAN=$(find wear -name AndroidManifest.xml -not -path '*/build/*' 2>/dev/null | head -1)
if [ -z "$AOS" ] || [ -z "$WOS" ] || [ -z "$WMAN" ]; then
  echo 'Файлы проекта не найдены. Запусти из корня проекта'; exit 1
fi
ADIR=$(dirname "$AOS"); WDIR=$(dirname "$WOS"); WRES="$(dirname "$WMAN")/res"
APKG=$(grep -m1 '^package' "$AOS" | tr -d '\r' | sed 's/^package[[:space:]]*//; s/[[:space:]]*$//')
WPKG=$(grep -m1 '^package' "$WOS" | tr -d '\r' | sed 's/^package[[:space:]]*//; s/[[:space:]]*$//')
[ -z "$APKG" ] && APKG="com.example.schedule"
[ -z "$WPKG" ] && WPKG="$APKG"
echo "APP: DIR=$ADIR PKG=$APKG"
echo "WEAR: DIR=$WDIR PKG=$WPKG"

# ---------- резервные копии (вне репозитория) ----------
BAK="$HOME/.schedule_bak/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BAK"
cp "$AOS" "$BAK/app_MainActivity.kt"
cp "$WOS" "$BAK/wear_MainActivity.kt"
cp "$WMAN" "$BAK/wear_AndroidManifest.xml"
cp wear/build.gradle.kts "$BAK/wear_build.gradle.kts"
[ -f "$WDIR/Notifier.kt" ] && cp "$WDIR/Notifier.kt" "$BAK/wear_Notifier.kt"
echo "Резервные копии: $BAK"

# =====================================================================
#  ТЕЛЕФОН: свайп дней в нижнем списке (синхронно с календарём)
# =====================================================================
cat << 'KT_EOF' > "$ADIR/DayPager.kt"
@file:OptIn(ExperimentalFoundationApi::class)

package PKG__

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.abs

private const val SW_BASE = 36500
private const val SW_COUNT = 73001

private fun swPage(anchor: LocalDate, d: LocalDate): Int =
    (SW_BASE + ChronoUnit.DAYS.between(anchor, d)).toInt().coerceIn(0, SW_COUNT - 1)

/** Список событий выбранного дня: свайп влево/вправо переключает день. */
@Composable
fun DayEventsPager(
    selected: LocalDate,
    lessons: List<Lesson>,
    anchor: LocalDate,
    nested: NestedScrollConnection,
    onSelect: (LocalDate) -> Unit,
    onOpen: (Lesson, LocalDate) -> Unit,
    modifier: Modifier = Modifier
) {
    val c = C
    val pager = rememberPagerState(initialPage = swPage(anchor, selected)) { SW_COUNT }
    val selNow by rememberUpdatedState(selected)
    val onSelectNow by rememberUpdatedState(onSelect)

    // свайп списка -> выбранная дата
    LaunchedEffect(pager) {
        snapshotFlow { pager.settledPage }.collect { p ->
            val d = anchor.plusDays((p - SW_BASE).toLong())
            if (d != selNow) onSelectNow(d)
        }
    }
    // выбранная дата (календарь, кнопка «сегодня») -> страница списка
    LaunchedEffect(selected) {
        val target = swPage(anchor, selected)
        if (pager.currentPage != target) {
            if (abs(pager.currentPage - target) > 3) pager.scrollToPage(target)
            else pager.animateScrollToPage(target)
        }
    }

    HorizontalPager(state = pager, modifier = modifier) { page ->
        val date = anchor.plusDays((page - SW_BASE).toLong())
        val list = remember(lessons, date) {
            lessons.filter { it.occursOn(date) }
                .sortedWith(compareByDescending<Lesson> { it.isAllDay }.thenBy { it.start })
        }
        LazyColumn(
            Modifier.fillMaxSize().nestedScroll(nested),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 88.dp)
        ) {
            if (list.isEmpty()) {
                item { Text("Нет событий", color = c.sub, modifier = Modifier.padding(vertical = 8.dp)) }
            }
            items(list, key = { it.id }) { l -> LessonCard(l, null) { onOpen(l, date) } }
        }
    }
}
KT_EOF

if grep -q 'DayEventsPager' "$AOS"; then
  echo 'Телефон: DayEventsPager уже подключён'
else
  RNG=$(sed -n '/^                    LazyColumn($/,/^                    }$/p' "$AOS")
  if [ -n "$RNG" ] && [ "$(printf '%s\n' "$RNG" | wc -l)" -le 14 ] \
     && printf '%s\n' "$RNG" | tail -1 | grep -q '^                    }$' \
     && printf '%s\n' "$RNG" | grep -q 'dayList'; then
    sed -i '/^                    LazyColumn($/,/^                    }$/c\
                    DayEventsPager(\
                        selected = selected, lessons = lessons, anchor = today, nested = nested,\
                        onSelect = onSelect, onOpen = onOpen,\
                        modifier = Modifier.fillMaxWidth().weight(1f)\
                    )' "$AOS"
    echo 'Телефон: список дня заменён на DayEventsPager'
  else
    echo '!! Телефон: не найден блок LazyColumn списка дня в MainActivity.kt (файл изменён вручную?). Свайп дней не подключён.'
  fi
fi

# =====================================================================
#  ЧАСЫ: зависимость циферблата
# =====================================================================
if ! grep -q 'androidx.wear.watchface:watchface' wear/build.gradle.kts; then
  sed -i '/^dependencies {$/a\
    implementation("androidx.wear.watchface:watchface:1.2.1")' wear/build.gradle.kts
fi

# =====================================================================
#  ЧАСЫ: ресурсы
# =====================================================================
mkdir -p "$WRES/xml" "$WRES/values" "$WRES/drawable"

cat << 'KT_EOF' > "$WRES/values/watch_face.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="watch_face_name">Расписание</string>
</resources>
KT_EOF

cat << 'KT_EOF' > "$WRES/xml/watch_face.xml"
<?xml version="1.0" encoding="UTF-8"?>
<wallpaper xmlns:android="http://schemas.android.com/apk/res/android"
    android:thumbnail="@drawable/watch_face_preview" />
KT_EOF

cat << 'KT_EOF' > "$WRES/drawable/watch_face_preview.xml"
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="400dp" android:height="400dp"
    android:viewportWidth="400" android:viewportHeight="400">
    <path android:fillColor="#FF000000" android:pathData="M200,200m-200,0a200,200 0 1,0 400,0a200,200 0 1,0 -400,0" />
    <path android:fillColor="#00000000" android:strokeColor="#FF7C5CFF" android:strokeWidth="8" android:strokeLineCap="round" android:pathData="M200,10A190,190 0 0,0 18,150" />
    <path android:fillColor="#FFFFFFFF" android:pathData="M78,80h64a18,18 0 0 1 18,18v64a18,18 0 0 1 -18,18h-64a18,18 0 0 1 -18,-18v-64a18,18 0 0 1 18,-18z" />
    <path android:fillColor="#FF7C5CFF" android:pathData="M208,80h64a18,18 0 0 1 18,18v64a18,18 0 0 1 -18,18h-64a18,18 0 0 1 -18,-18v-64a18,18 0 0 1 18,-18z" />
    <path android:fillColor="#FF2A2740" android:pathData="M93,200h164a13,13 0 0 1 13,13v0a13,13 0 0 1 -13,13h-164a13,13 0 0 1 -13,-13v0a13,13 0 0 1 13,-13z" />
    <path android:fillColor="#FF26242F" android:pathData="M84,240h232a14,14 0 0 1 14,14v24a14,14 0 0 1 -14,14h-232a14,14 0 0 1 -14,-14v-24a14,14 0 0 1 14,-14z" />
    <path android:fillColor="#FF26242F" android:pathData="M84,302h232a14,14 0 0 1 14,14v24a14,14 0 0 1 -14,14h-232a14,14 0 0 1 -14,-14v-24a14,14 0 0 1 14,-14z" />
    <path android:fillColor="#FF7C5CFF" android:pathData="M70,244h8v44h-8z" />
    <path android:fillColor="#FF4D8DFF" android:pathData="M70,306h8v44h-8z" />
</vector>
KT_EOF

if [ ! -f "$WRES/drawable/ic_close.xml" ]; then
cat << 'KT_EOF' > "$WRES/drawable/ic_close.xml"
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF" android:pathData="M19,6.41L17.59,5 12,10.59 6.41,5 5,6.41 10.59,12 5,17.59 6.41,19 12,13.41 17.59,19 19,17.59 13.41,12z" />
</vector>
KT_EOF
fi
if [ ! -f "$WRES/drawable/ic_notif.xml" ]; then
cat << 'KT_EOF' > "$WRES/drawable/ic_notif.xml"
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF" android:pathData="M12,22c1.1,0 2,-0.9 2,-2h-4c0,1.1 0.89,2 2,2zM18,16v-5c0,-3.07 -1.64,-5.64 -4.5,-6.32V4c0,-0.83 -0.67,-1.5 -1.5,-1.5s-1.5,0.67 -1.5,1.5v0.68C7.64,5.36 6,7.92 6,11v5l-2,2v1h16v-1l-2,-2z" />
</vector>
KT_EOF
fi

# =====================================================================
#  ЧАСЫ: манифест (патчи без перезаписи файла)
# =====================================================================
add_perm() {
  grep -q "android.permission.$2\"" "$1" || sed -i "/<application/i <uses-permission android:name=\"android.permission.$2\" />" "$1"
}
for P in VIBRATE POST_NOTIFICATIONS USE_FULL_SCREEN_INTENT SYSTEM_ALERT_WINDOW WAKE_LOCK RECEIVE_BOOT_COMPLETED USE_EXACT_ALARM; do
  add_perm "$WMAN" "$P"
done
grep -q 'SCHEDULE_EXACT_ALARM' "$WMAN" || sed -i '/<application/i <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32" />' "$WMAN"

grep -q 'ReminderActivity' "$WMAN" || sed -i '/<\/application>/i <activity android:name=".ReminderActivity" android:exported="false" android:launchMode="singleTop" android:excludeFromRecents="true" android:taskAffinity="" android:showWhenLocked="true" android:turnScreenOn="true" />' "$WMAN"
grep -q 'ScheduleWatchFaceService' "$WMAN" || sed -i '/<\/application>/i <service android:name=".ScheduleWatchFaceService" android:exported="true" android:label="@string/watch_face_name" android:permission="android.permission.BIND_WALLPAPER"><meta-data android:name="android.service.wallpaper" android:resource="@xml/watch_face" /><meta-data android:name="com.google.android.wearable.watchface.preview" android:resource="@drawable/watch_face_preview" /><meta-data android:name="com.google.android.wearable.watchface.preview_circular" android:resource="@drawable/watch_face_preview" /><intent-filter><action android:name="android.service.wallpaper.WallpaperService" /><category android:name="com.google.android.wearable.watchface.category.WATCH_FACE" /></intent-filter></service>' "$WMAN"
grep -q 'NotifDismissReceiver' "$WMAN" || sed -i '/<\/application>/i <receiver android:name=".NotifDismissReceiver" android:exported="false" />' "$WMAN"
grep -q '\.AlarmReceiver' "$WMAN" || sed -i '/<\/application>/i <receiver android:name=".AlarmReceiver" android:exported="false" />' "$WMAN"
if ! grep -q '\.BootReceiver' "$WMAN"; then
  sed -i '/<\/application>/i <receiver android:name=".BootReceiver" android:exported="true"><intent-filter><action android:name="android.intent.action.BOOT_COMPLETED" /><action android:name="android.intent.action.MY_PACKAGE_REPLACED" /></intent-filter></receiver>' "$WMAN"
fi
sed -i 's|android:path="/schedule"|android:pathPrefix="/"|' "$WMAN"

# =====================================================================
#  ЧАСЫ: Notifier.kt (полноэкранное напоминание, звук + вибрация канала)
# =====================================================================
cat << 'KT_EOF' > "$WDIR/Notifier.kt"
package PKG__

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
KT_EOF

# =====================================================================
#  ЧАСЫ: Perms.kt (последовательный запрос разрешений)
# =====================================================================
cat << 'KT_EOF' > "$WDIR/Perms.kt"
package PKG__

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
KT_EOF

# =====================================================================
#  ЧАСЫ: ReminderActivity.kt (напоминание на весь экран)
# =====================================================================
cat << 'KT_EOF' > "$WDIR/ReminderActivity.kt"
package PKG__

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
KT_EOF

# =====================================================================
#  ЧАСЫ: ScheduleWatchFaceService.kt (интерактивный циферблат, Canvas)
# =====================================================================
cat << 'KT_EOF' > "$WDIR/ScheduleWatchFaceService.kt"
package PKG__

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.BatteryManager
import android.view.SurfaceHolder
import androidx.wear.watchface.CanvasType
import androidx.wear.watchface.ComplicationSlot
import androidx.wear.watchface.ComplicationSlotsManager
import androidx.wear.watchface.DrawMode
import androidx.wear.watchface.Renderer
import androidx.wear.watchface.TapEvent
import androidx.wear.watchface.TapType
import androidx.wear.watchface.WatchFace
import androidx.wear.watchface.WatchFaceService
import androidx.wear.watchface.WatchFaceType
import androidx.wear.watchface.WatchState
import androidx.wear.watchface.style.CurrentUserStyleRepository
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.sqrt

/** С какого экрана открыть приложение: циферблат передаёт extra "open" = files | dates. */
fun initialOverlay(ctx: Context): Overlay {
    var c: Context? = ctx
    while (c is ContextWrapper) {
        if (c is Activity) {
            return when (c.intent?.getStringExtra("open")) {
                "files" -> Overlay.FILES
                "dates" -> Overlay.DATES
                else -> Overlay.NONE
            }
        }
        c = c.baseContext
    }
    return Overlay.NONE
}

private val WF_PURPLE = 0xFF7C5CFF.toInt()
private val WF_LILAC = 0xFFA78BFA.toInt()
private val WF_DIM = 0xFFB8B2D6.toInt()
private val WF_SOFT = 0xFFE6E0FF.toInt()
private val WF_CARD = 0xFF17161F.toInt()
private val WF_PILL = 0xFF14131C.toInt()
private val WF_RING = 0xFF2A2740.toInt()
private val WF_BTN = 0xFF1B1A22.toInt()
private val WF_DOT = 0xFF3A3A44.toInt()
private val WF_COLON = 0xFF8C88A8.toInt()

class ScheduleWatchFaceService : WatchFaceService() {
    override suspend fun createWatchFace(
        surfaceHolder: SurfaceHolder,
        watchState: WatchState,
        complicationSlotsManager: ComplicationSlotsManager,
        currentUserStyleRepository: CurrentUserStyleRepository
    ): WatchFace {
        val renderer = ScheduleRenderer(applicationContext, surfaceHolder, currentUserStyleRepository, watchState)
        val face = WatchFace(WatchFaceType.DIGITAL, renderer)
        face.setTapListener(object : WatchFace.TapListener {
            override fun onTapEvent(tapType: Int, tapEvent: TapEvent, complicationSlot: ComplicationSlot?) {
                if (tapType == TapType.UP) renderer.onTap(tapEvent.xPos.toFloat(), tapEvent.yPos.toFloat())
            }
        })
        return face
    }
}

private class ScheduleRenderer(
    private val ctx: Context,
    surfaceHolder: SurfaceHolder,
    currentUserStyleRepository: CurrentUserStyleRepository,
    watchState: WatchState
) : Renderer.CanvasRenderer2<ScheduleRenderer.Assets>(
    surfaceHolder, currentUserStyleRepository, watchState,
    CanvasType.HARDWARE, 1000L, false
) {
    class Assets : Renderer.SharedAssets {
        override fun onDestroy() {}
    }

    private class Hit(val r: RectF, val target: String)

    private val prefs: SharedPreferences = ctx.getSharedPreferences("schedule", Context.MODE_PRIVATE)

    @Volatile
    private var lessons: List<Lesson> = loadLessons()

    // слушатель хранится в поле: SharedPreferences держит его только слабой ссылкой
    private val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "json") {
            lessons = loadLessons()
            invalidate()
        }
    }

    private val p = Paint(Paint.ANTI_ALIAS_FLAG)
    private val normalFace: Typeface = Typeface.create("sans-serif", Typeface.NORMAL)
    private val boldFace: Typeface = Typeface.create("sans-serif", Typeface.BOLD)
    private val heavyFace: Typeface = Typeface.create("sans-serif-black", Typeface.NORMAL)
    private val dateFmt = DateTimeFormatter.ofPattern("EEE, d MMM", Locale("ru"))
    private val hits = ArrayList<Hit>()
    private var originX = 0f
    private var originY = 0f

    init {
        prefs.registerOnSharedPreferenceChangeListener(listener)
    }

    private fun loadLessons(): List<Lesson> =
        LessonJson.fromJson(prefs.getString("json", "[]") ?: "[]")

    override suspend fun createSharedAssets(): Assets = Assets()

    override fun render(canvas: Canvas, bounds: Rect, zonedDateTime: ZonedDateTime, sharedAssets: Assets) {
        hits.clear()
        originX = bounds.left.toFloat()
        originY = bounds.top.toFloat()
        val s = bounds.width().toFloat()
        canvas.drawColor(Color.BLACK)
        canvas.save()
        canvas.translate(originX, originY)
        if (renderParameters.drawMode == DrawMode.AMBIENT) drawAmbient(canvas, s, zonedDateTime)
        else drawInteractive(canvas, s, zonedDateTime)
        canvas.restore()
    }

    override fun renderHighlightLayer(canvas: Canvas, bounds: Rect, zonedDateTime: ZonedDateTime, sharedAssets: Assets) {
        canvas.drawColor(Color.TRANSPARENT)
    }

    // ---------------- нажатия ----------------
    fun onTap(x: Float, y: Float) {
        val lx = x - originX
        val ly = y - originY
        val target = hits.firstOrNull { it.r.contains(lx, ly) }?.target ?: "app"
        open(target)
    }

    private fun open(target: String) {
        val i = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            .putExtra("open", target)
        try {
            PendingIntent.getActivity(
                ctx, target.hashCode(), i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            ).send()
        } catch (e: Exception) {
            try {
                ctx.startActivity(i)
            } catch (e2: Exception) {
            }
        }
    }

    // ---------------- помощники рисования ----------------
    private fun fill(color: Int) {
        p.reset(); p.isAntiAlias = true
        p.style = Paint.Style.FILL; p.color = color
    }

    private fun stroke(color: Int, w: Float) {
        p.reset(); p.isAntiAlias = true
        p.style = Paint.Style.STROKE; p.color = color; p.strokeWidth = w
        p.strokeCap = Paint.Cap.ROUND; p.strokeJoin = Paint.Join.ROUND
    }

    private fun measure(str: String, size: Float, face: Typeface): Float {
        p.reset(); p.textSize = size; p.typeface = face
        return p.measureText(str)
    }

    private fun txt(
        c: Canvas, str: String, x: Float, y: Float, size: Float, color: Int, face: Typeface,
        align: Paint.Align = Paint.Align.LEFT, maxW: Float = 0f
    ) {
        p.reset(); p.isAntiAlias = true; p.style = Paint.Style.FILL
        p.color = color; p.textSize = size; p.typeface = face; p.textAlign = align
        var out = str
        if (maxW > 0f && p.measureText(out) > maxW) {
            var n = out.length
            while (n > 1 && p.measureText(out, 0, n) + p.measureText("…") > maxW) n--
            out = out.substring(0, n) + "…"
        }
        c.drawText(out, x, y, p)
    }

    private fun withAlpha(col: Int, a: Int): Int = Color.argb(a, Color.red(col), Color.green(col), Color.blue(col))

    private fun colorInt(hex: String): Int = try {
        Color.parseColor(hex)
    } catch (e: Exception) {
        WF_PURPLE
    }

    private fun hm(s: String): Int =
        (s.substringBefore(":").toIntOrNull() ?: 0) * 60 + (s.substringAfter(":").toIntOrNull() ?: 0)

    private fun battery(): Int = try {
        (ctx.getSystemService(Context.BATTERY_SERVICE) as BatteryManager)
            .getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    } catch (e: Exception) {
        -1
    }

    private fun lw(n: Int): String {
        val a = n % 100
        val b = n % 10
        return if (a in 11..14) "уроков" else when (b) {
            1 -> "урок"
            in 2..4 -> "урока"
            else -> "уроков"
        }
    }

    // ---------------- ambient ----------------
    private fun drawAmbient(c: Canvas, s: Float, t: ZonedDateTime) {
        val day = lessons.count { it.occursOn(t.toLocalDate()) }
        txt(c, "%02d:%02d".format(t.hour, t.minute), s / 2f, s * 0.56f, s * 0.26f, 0xFFD0D0D0.toInt(), normalFace, Paint.Align.CENTER)
        txt(
            c, t.format(dateFmt).replaceFirstChar { it.uppercase() },
            s / 2f, s * 0.67f, s * 0.06f, 0xFF808080.toInt(), normalFace, Paint.Align.CENTER
        )
        if (day > 0) {
            txt(c, "$day ${lw(day)}", s / 2f, s * 0.76f, s * 0.045f, 0xFF606060.toInt(), normalFace, Paint.Align.CENTER)
        }
    }

    // ---------------- интерактивный режим ----------------
    private fun drawInteractive(c: Canvas, s: Float, t: ZonedDateTime) {
        val nowMin = t.hour * 60 + t.minute
        val today = t.toLocalDate()
        val all = lessons.filter { it.occursOn(today) }
            .sortedWith(compareByDescending<Lesson> { it.isAllDay }.thenBy { it.start })
        val upcoming = all.filter { it.isAllDay || hm(it.end) > nowMin }

        // свечение справа сверху
        p.reset(); p.isAntiAlias = true
        p.shader = RadialGradient(s * 0.78f, s * 0.36f, s * 0.36f, 0x557C5CFF, 0x00000000, Shader.TileMode.CLAMP)
        c.drawCircle(s * 0.78f, s * 0.36f, s * 0.36f, p)

        // дуга прогресса учебного дня (08:00-18:00) по левому краю
        val sw = s * 0.012f
        val inset = sw / 2f + s * 0.008f
        val oval = RectF(inset, inset, s - inset, s - inset)
        stroke(WF_RING, sw)
        c.drawArc(oval, 100f, 170f, false, p)
        val prog = ((nowMin - 480) / 600f).coerceIn(0f, 1f)
        if (prog > 0f) {
            stroke(WF_PURPLE, sw)
            c.drawArc(oval, 270f - 170f * prog, 170f * prog, false, p)
        }

        // иконка календаря и дата
        fill(WF_LILAC)
        c.drawRoundRect(RectF(s * 0.465f, s * 0.055f, s * 0.535f, s * 0.115f), s * 0.014f, s * 0.014f, p)
        fill(WF_PURPLE)
        c.drawRoundRect(RectF(s * 0.465f, s * 0.055f, s * 0.535f, s * 0.075f), s * 0.014f, s * 0.014f, p)
        txt(
            c, t.format(dateFmt).replaceFirstChar { it.uppercase() },
            s / 2f, s * 0.168f, s * 0.062f, WF_SOFT, boldFace, Paint.Align.CENTER
        )

        // время
        var ts = s * 0.20f
        val hs = "%02d".format(t.hour)
        val ms = "%02d".format(t.minute)
        var wh = measure(hs, ts, heavyFace)
        var wc = measure(":", ts, heavyFace)
        var wm = measure(ms, ts, heavyFace)
        val maxTotal = s * 0.50f
        if (wh + wc + wm > maxTotal) {
            val k = maxTotal / (wh + wc + wm)
            ts *= k; wh *= k; wc *= k; wm *= k
        }
        val x0 = s * 0.15f
        val ty = s * 0.335f
        txt(c, hs, x0, ty, ts, Color.WHITE, heavyFace)
        txt(c, ":", x0 + wh, ty, ts, WF_COLON, heavyFace)
        txt(c, ms, x0 + wh + wc, ty, ts, WF_PURPLE, heavyFace)

        drawIllustration(c, s)

        // батарея
        val bat = battery()
        if (bat >= 0) {
            stroke(WF_DIM, s * 0.004f)
            c.drawRoundRect(RectF(s * 0.685f, s * 0.188f, s * 0.725f, s * 0.214f), s * 0.006f, s * 0.006f, p)
            fill(WF_DIM)
            c.drawRect(RectF(s * 0.69f, s * 0.193f, s * 0.69f + s * 0.03f * (bat / 100f), s * 0.209f), p)
            txt(c, "$bat%", s * 0.84f, s * 0.214f, s * 0.04f, WF_DIM, normalFace, Paint.Align.RIGHT)
        }

        // плашка «Сегодня • N уроков»
        val pillTxt = "Сегодня • " + (if (all.isEmpty()) "занятий нет" else "${all.size} ${lw(all.size)}")
        val pw = measure(pillTxt, s * 0.045f, normalFace)
        val pl = s * 0.15f
        val pr = pl + s * 0.055f + pw + s * 0.035f
        val pillRect = RectF(pl, s * 0.36f, pr, s * 0.425f)
        fill(WF_PILL)
        c.drawRoundRect(pillRect, s * 0.0325f, s * 0.0325f, p)
        stroke(WF_RING, s * 0.003f)
        c.drawRoundRect(pillRect, s * 0.0325f, s * 0.0325f, p)
        fill(WF_PURPLE)
        c.drawCircle(pl + s * 0.03f, s * 0.3925f, s * 0.01f, p)
        txt(c, pillTxt, pl + s * 0.055f, s * 0.407f, s * 0.045f, WF_SOFT, normalFace)
        hits.add(Hit(pillRect, "app"))

        // карточки ближайших уроков (нижняя часть обрезается круглой рамкой)
        val cardH = s * 0.15f
        val gap = s * 0.015f
        var top = s * 0.45f
        for (l in upcoming.take(3)) {
            drawCard(c, s, l, top, cardH)
            top += cardH + gap
        }
        if (upcoming.isEmpty()) {
            txt(
                c, if (all.isEmpty()) "Занятий нет" else "На сегодня всё",
                s / 2f, s * 0.62f, s * 0.05f, WF_DIM, normalFace, Paint.Align.CENTER
            )
        }

        // стрелки: слева «Файлы», справа «Даты»
        drawArrow(c, s, s * 0.075f, s * 0.52f, -1)
        drawArrow(c, s, s * 0.925f, s * 0.52f, 1)
        hits.add(Hit(RectF(0f, s * 0.40f, s * 0.16f, s * 0.64f), "files"))
        hits.add(Hit(RectF(s * 0.84f, s * 0.40f, s, s * 0.64f), "dates"))

        // точки-индикаторы
        fill(WF_PURPLE)
        c.drawCircle(s * 0.47f, s * 0.955f, s * 0.012f, p)
        fill(WF_DOT)
        c.drawCircle(s * 0.50f, s * 0.955f, s * 0.010f, p)
        c.drawCircle(s * 0.53f, s * 0.955f, s * 0.010f, p)
    }

    private fun drawCard(c: Canvas, s: Float, l: Lesson, top: Float, h: Float) {
        val cy = top + h / 2f
        val dy = abs(cy - s / 2f)
        val half = sqrt(maxOf(0f, (s / 2f) * (s / 2f) - dy * dy))
        val pad = s * 0.035f
        val left = s / 2f - half + pad
        val right = s / 2f + half - pad
        val rect = RectF(left, top, right, top + h)
        val col = colorInt(l.color)

        fill(WF_CARD)
        c.drawRoundRect(rect, s * 0.05f, s * 0.05f, p)
        fill(col)
        c.drawRoundRect(RectF(left, top, left + s * 0.022f, top + h), s * 0.011f, s * 0.011f, p)

        val tx = left + s * 0.06f
        val iconSz = s * 0.095f
        val iconL = right - s * 0.04f - iconSz
        val maxW = iconL - tx - s * 0.02f
        txt(c, l.timeLabel(), tx, top + h * 0.30f, s * 0.042f, WF_DIM, normalFace, maxW = maxW)
        txt(c, l.title, tx, top + h * 0.62f, s * 0.056f, Color.WHITE, boldFace, maxW = maxW)
        val room = roomLabel(l.room)
        if (room.isNotBlank()) {
            stroke(WF_LILAC, s * 0.006f)
            c.drawCircle(tx + s * 0.012f, top + h * 0.86f - s * 0.012f, s * 0.011f, p)
            txt(c, room, tx + s * 0.035f, top + h * 0.90f, s * 0.038f, WF_DIM, normalFace, maxW = maxW - s * 0.035f)
        }

        val ir = RectF(iconL, cy - iconSz / 2f, iconL + iconSz, cy + iconSz / 2f)
        fill(withAlpha(col, 90))
        c.drawRoundRect(ir, s * 0.025f, s * 0.025f, p)
        val glyph = if (l.emoji.isNotBlank()) l.emoji else l.title.take(1).uppercase()
        txt(c, glyph, ir.centerX(), ir.centerY() + s * 0.02f, s * 0.055f, Color.WHITE, boldFace, Paint.Align.CENTER)

        hits.add(Hit(rect, "app"))
    }

    private fun drawArrow(c: Canvas, s: Float, cx: Float, cy: Float, dir: Int) {
        fill(WF_BTN)
        c.drawCircle(cx, cy, s * 0.043f, p)
        stroke(Color.WHITE, s * 0.009f)
        val path = Path()
        val d = dir.toFloat()
        path.moveTo(cx + d * s * 0.010f, cy - s * 0.020f)
        path.lineTo(cx - d * s * 0.010f, cy)
        path.lineTo(cx + d * s * 0.010f, cy + s * 0.020f)
        c.drawPath(path, p)
    }

    private fun drawIllustration(c: Canvas, s: Float) {
        // календарь
        fill(0xFFD8D0FF.toInt())
        c.drawRoundRect(RectF(s * 0.66f, s * 0.25f, s * 0.87f, s * 0.41f), s * 0.025f, s * 0.025f, p)
        fill(WF_PURPLE)
        c.drawRoundRect(RectF(s * 0.66f, s * 0.25f, s * 0.87f, s * 0.285f), s * 0.025f, s * 0.025f, p)
        fill(0xFFB8B0F0.toInt())
        c.drawRoundRect(RectF(s * 0.70f, s * 0.225f, s * 0.715f, s * 0.265f), s * 0.007f, s * 0.007f, p)
        c.drawRoundRect(RectF(s * 0.815f, s * 0.225f, s * 0.83f, s * 0.265f), s * 0.007f, s * 0.007f, p)
        fill(WF_PURPLE)
        for (row in 0..1) {
            for (col in 0..2) {
                val x = s * (0.685f + col * 0.047f)
                val y = s * (0.30f + row * 0.04f)
                c.drawRoundRect(RectF(x, y, x + s * 0.035f, y + s * 0.03f), s * 0.006f, s * 0.006f, p)
            }
        }
        // часы
        fill(0xFF1E1B33.toInt())
        c.drawCircle(s * 0.85f, s * 0.405f, s * 0.045f, p)
        stroke(Color.WHITE, s * 0.006f)
        c.drawCircle(s * 0.85f, s * 0.405f, s * 0.045f, p)
        val hands = Path()
        hands.moveTo(s * 0.85f, s * 0.38f)
        hands.lineTo(s * 0.85f, s * 0.405f)
        hands.lineTo(s * 0.868f, s * 0.415f)
        c.drawPath(hands, p)
    }
}
KT_EOF

# =====================================================================
#  ЧАСЫ: патчи MainActivity.kt
# =====================================================================
if ! grep -q 'initialOverlay(ctx)' "$WOS"; then
  sed -i 's|mutableStateOf(Overlay.NONE)|mutableStateOf(initialOverlay(ctx))|' "$WOS"
fi

# =====================================================================
#  Подстановка пакета
# =====================================================================
sed -i "s/PKG__/${APKG}/g" "$ADIR/DayPager.kt"
for f in Notifier.kt Perms.kt ReminderActivity.kt ScheduleWatchFaceService.kt; do
  sed -i "s/PKG__/${WPKG}/g" "$WDIR/$f"
done

# =====================================================================
#  Проверка патчей
# =====================================================================
chk() { grep -q "$1" "$2" || echo "!! $3"; }
chk 'DayEventsPager'                       "$AOS"                          'телефон: свайп дней не подключён (см. сообщение выше)'
chk 'androidx.wear.watchface:watchface'    wear/build.gradle.kts           'часы: нет зависимости androidx.wear.watchface'
chk 'ScheduleWatchFaceService'             "$WMAN"                         'часы: в манифесте нет сервиса циферблата'
chk 'ReminderActivity'                     "$WMAN"                         'часы: в манифесте нет ReminderActivity'
chk 'USE_FULL_SCREEN_INTENT'               "$WMAN"                         'часы: нет разрешения USE_FULL_SCREEN_INTENT'
chk 'fun WearApp()'                        "$WOS"                          'часы: в MainActivity.kt нет WearApp()'
chk 'initialOverlay(ctx)'                  "$WOS"                          'часы: не подключён переход с циферблата (нет mutableStateOf(Overlay.NONE) или val ctx)'
chk 'val ctx = LocalContext.current'       "$WOS"                          'часы: в WearApp нет val ctx = LocalContext.current'
chk 'Notifier.askPermission'               "$WOS"                          'часы: нет вызова Notifier.askPermission(this) в onCreate (добавь после ScheduleRepository.init(this))'
chk 'Notifier.rescheduleAll'               "$WDIR/DataSyncService.kt"      'часы: DataSyncService не вызывает Notifier.rescheduleAll'

echo
echo 'Готово.'
echo '1) git add . && git commit -m "Fullscreen reminders, watch face, day swipe" && git push'
echo '2) Дождись зелёной сборки в Actions, поставь app-release.apk на телефон и wear-release.apk на часы (ключ тот же, поверх).'
echo '3) На часах открой приложение: по очереди попросит разрешения (уведомления, будильники, полный экран, поверх окон).'
echo '   Согласись на всё, что покажет система.'
echo '4) Проверка напоминания: на телефоне создай событие через 2-3 минуты, "Напоминание: В момент начала", дождись отправки на часы.'
echo '5) Циферблат: долгое нажатие на текущий циферблат -> листай в конец -> выбери "Расписание".'
echo "Резервные копии файлов: $BAK"
