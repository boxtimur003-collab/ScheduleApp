#!/data/data/com.termux/files/usr/bin/bash
# Что делает скрипт (зависимости в build.gradle.kts НЕ меняются):
#  - Lesson.kt (оба модуля): поле notificationMinutes (хранится в JSON, значит и в экспорте/импорте).
#  - Notifier.kt (оба модуля): AlarmManager-напоминания; на часах показывают название, время и кабинет.
#  - Телефон: Extras.kt (выпадающий список «Напоминание», «Мои файлы», правка и удаление файлов),
#    DataSyncService.kt. MainActivity.kt правится точечными sed-патчами.
#  - Часы: WearHome.kt (главный экран по референсу), DataSyncService.kt. В MainActivity.kt
#    старый WearApp переименовывается в WearAppOld, остальной код (формулы, меню, шкала) не трогается.
#  - Требуются файлы, созданные прошлыми скриптами. Это не системный WatchFace, а главный экран приложения.
#  - Фон: wear/src/main/res/drawable/watch_face_bg.png (заглушка, нужен python3).
#    Своя картинка с тем же именем подхватится сама. Без файла экран рисуется на чёрном.
#  - Проект я не собирал. При ошибке сборки пришли лог.
set +H
cd "${1:-$HOME/ScheduleApp}" || { echo 'Папка проекта не найдена'; exit 1; }

AOS=$(find app -name MainActivity.kt -not -path '*/build/*' 2>/dev/null | head -1)
WOS=$(find wear -name MainActivity.kt -not -path '*/build/*' 2>/dev/null | head -1)
AMAN=$(find app -name AndroidManifest.xml -not -path '*/build/*' 2>/dev/null | head -1)
WMAN=$(find wear -name AndroidManifest.xml -not -path '*/build/*' 2>/dev/null | head -1)
if [ -z "$AOS" ] || [ -z "$WOS" ] || [ -z "$AMAN" ] || [ -z "$WMAN" ]; then
  echo 'Файлы проекта не найдены. Запусти из корня проекта'; exit 1
fi
ADIR=$(dirname "$AOS"); WDIR=$(dirname "$WOS")
ARES="$(dirname "$AMAN")/res"; WRES="$(dirname "$WMAN")/res"
APKG=$(grep -m1 '^package' "$AOS" | tr -d '\r' | sed 's/^package[[:space:]]*//; s/[[:space:]]*$//')
WPKG=$(grep -m1 '^package' "$WOS" | tr -d '\r' | sed 's/^package[[:space:]]*//; s/[[:space:]]*$//')
[ -z "$APKG" ] && APKG="com.example.schedule"
[ -z "$WPKG" ] && WPKG="$APKG"
echo "APP: DIR=$ADIR PKG=$APKG"
echo "WEAR: DIR=$WDIR PKG=$WPKG"
mkdir -p "$ARES/drawable" "$WRES/drawable"

# ======================= Манифесты: разрешения и ресиверы =======================
sed -i 's|android:path="/schedule"|android:pathPrefix="/"|' "$WMAN"
for M in "$AMAN" "$WMAN"; do
  if ! grep -q AlarmReceiver "$M"; then
    sed -i '/<\/application>/i\
        <receiver android:name=".AlarmReceiver" android:exported="false" />\
        <receiver android:name=".BootReceiver" android:exported="true">\
            <intent-filter>\
                <action android:name="android.intent.action.BOOT_COMPLETED" />\
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />\
            </intent-filter>\
        </receiver>' "$M"
    sed -i '/<application/i\
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />\
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32" />\
    <uses-permission android:name="android.permission.USE_EXACT_ALARM" />' "$M"
  fi
done

# ======================= Ресурсы =======================
cat << 'KT_EOF' > "$ARES/drawable/ic_notif.xml"
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF" android:pathData="M12,22c1.1,0 2,-0.9 2,-2h-4c0,1.1 0.89,2 2,2zM18,16v-5c0,-3.07 -1.64,-5.64 -4.5,-6.32V4c0,-0.83 -0.67,-1.5 -1.5,-1.5s-1.5,0.67 -1.5,1.5v0.68C7.64,5.36 6,7.92 6,11v5l-2,2v1h16v-1l-2,-2z" />
</vector>
KT_EOF
cp "$ARES/drawable/ic_notif.xml" "$WRES/drawable/ic_notif.xml"

BG="$WRES/drawable/watch_face_bg.png"
if [ ! -s "$BG" ]; then
  if command -v python3 >/dev/null 2>&1; then
python3 - "$BG" << 'PY'
import struct, sys, zlib
w = h = 64
raw = b''.join(b'\x00' + bytes([int(0x2A*(1-y/63)), int(0x1E*(1-y/63)), int(0x4F*(1-y/63))]) * w for y in range(h))
def ch(t, d):
    c = struct.pack('>I', len(d)) + t + d
    return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
open(sys.argv[1], 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw, 9)) + ch(b'IEND', b''))
PY
  else
    echo "python3 нет: watch_face_bg.png не создан (pkg install python или положи свою картинку в $WRES/drawable/)"
  fi
fi

# ======================= Lesson.kt (общий) =======================
cat << 'KT_EOF' > "$ADIR/Lesson.kt"
package PKG__

import androidx.compose.ui.graphics.Color
import org.json.JSONArray
import org.json.JSONObject
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * date: "2026-11-20" (разовое - дата события, повторяющееся - дата первого вхождения)
 * recurrence: NONE | DAILY | WEEKLY | MONTHLY | YEARLY
 * exceptions: даты "yyyy-MM-dd", в которые повторяющееся событие НЕ показывается
 * notificationMinutes: -1 = не напоминать, 0 = в момент начала, N = за N минут
 */
data class Lesson(
    val id: Long,
    val title: String,
    val date: String,
    val recurrence: String = "NONE",
    val isAllDay: Boolean = false,
    val color: String = "#1A73E8",
    val start: String = "08:30",
    val end: String = "09:15",
    val room: String = "",
    val icon: String = "other",
    val emoji: String = "",
    val exceptions: List<String> = emptyList(),
    val notificationMinutes: Int = -1
)

val PALETTE = listOf(
    "#1A73E8", "#0B8043", "#D50000", "#F4511E",
    "#F6BF26", "#8E24AA", "#039BE5", "#616161"
)

val RECURRENCES = listOf(
    "NONE" to "Не повторять",
    "DAILY" to "Каждый день",
    "WEEKLY" to "Каждую неделю",
    "MONTHLY" to "Каждый месяц",
    "YEARLY" to "Каждый год"
)

val NOTIFY_OPTIONS = listOf(
    -1 to "Не напоминать",
    0 to "В момент начала",
    5 to "За 5 мин",
    15 to "За 15 мин",
    30 to "За 30 мин",
    60 to "За 1 час"
)

fun notifyLabel(m: Int): String =
    NOTIFY_OPTIONS.firstOrNull { it.first == m }?.second ?: if (m < 0) "Не напоминать" else "За $m мин"

fun recurrenceLabel(r: String): String = RECURRENCES.firstOrNull { it.first == r }?.second ?: "Не повторять"

fun recurrenceStatus(r: String): String = when (r) {
    "DAILY" -> "Каждый день"
    "WEEKLY" -> "Каждую неделю"
    "MONTHLY" -> "Каждый месяц"
    "YEARLY" -> "Каждый год"
    else -> "Разовое"
}

fun parseColor(hex: String): Color = try {
    Color(android.graphics.Color.parseColor(hex))
} catch (e: Exception) {
    Color(0xFF1A73E8)
}

fun parseDate(s: String): LocalDate = try {
    LocalDate.parse(s)
} catch (e: Exception) {
    LocalDate.now()
}

fun Lesson.timeLabel(): String = if (isAllDay) "Весь день" else "$start – $end"

fun Lesson.occursOn(d: LocalDate): Boolean {
    if (exceptions.isNotEmpty() && exceptions.contains(d.toString())) return false
    val base = try { LocalDate.parse(date) } catch (e: Exception) { return false }
    if (d.isBefore(base)) return false
    return when (recurrence) {
        "DAILY" -> true
        "WEEKLY" -> ChronoUnit.DAYS.between(base, d) % 7L == 0L
        "MONTHLY" -> d.dayOfMonth == minOf(base.dayOfMonth, d.lengthOfMonth())
        "YEARLY" -> d.month == base.month && d.dayOfMonth == minOf(base.dayOfMonth, d.lengthOfMonth())
        else -> d == base
    }
}

object LessonJson {
    fun toJson(list: List<Lesson>): String {
        val arr = JSONArray()
        list.forEach {
            arr.put(
                JSONObject()
                    .put("id", it.id)
                    .put("title", it.title)
                    .put("date", it.date)
                    .put("recurrence", it.recurrence)
                    .put("isAllDay", it.isAllDay)
                    .put("color", it.color)
                    .put("start", it.start)
                    .put("end", it.end)
                    .put("room", it.room)
                    .put("icon", it.icon)
                    .put("emoji", it.emoji)
                    .put("exceptions", JSONArray(it.exceptions))
                    .put("notificationMinutes", it.notificationMinutes)
            )
        }
        return arr.toString()
    }

    fun fromJson(s: String): List<Lesson> = try {
        val a = JSONArray(s)
        (0 until a.length()).mapNotNull { i ->
            try { parse(a.getJSONObject(i)) } catch (e: Exception) { null }
        }
    } catch (e: Exception) {
        emptyList()
    }

    private fun parse(o: JSONObject): Lesson {
        var date = o.optString("date", "")
        var rec = o.optString("recurrence", "NONE")
        if (date.isEmpty()) {
            val day = o.optInt("day", 1).coerceIn(1, 7)
            date = LocalDate.now().with(DayOfWeek.of(day)).minusWeeks(8).toString()
            rec = "WEEKLY"
        }
        val ex = o.optJSONArray("exceptions")
        val exceptions = if (ex == null) emptyList() else (0 until ex.length()).map { ex.getString(it) }
        return Lesson(
            id = o.getLong("id"),
            title = o.optString("title", o.optString("subject", "")),
            date = date,
            recurrence = rec,
            isAllDay = o.optBoolean("isAllDay", false),
            color = o.optString("color", "#1A73E8"),
            start = o.optString("start", "08:30"),
            end = o.optString("end", "09:15"),
            room = o.optString("room", ""),
            icon = o.optString("icon", "other"),
            emoji = o.optString("emoji", ""),
            exceptions = exceptions,
            notificationMinutes = o.optInt("notificationMinutes", -1)
        )
    }
}
KT_EOF
cp "$ADIR/Lesson.kt" "$WDIR/Lesson.kt"

# ======================= Notifier.kt (общий: AlarmManager + уведомления) =======================
cat << 'KT_EOF' > "$ADIR/Notifier.kt"
package PKG__

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

object Notifier {
    private const val CH = "reminders"

    private fun codeOf(id: Long): Int = (id xor (id ushr 32)).toInt() and 0x7fffffff

    private fun pending(ctx: Context, code: Int, flag: Int, title: String = "", text: String = ""): PendingIntent? {
        val i = Intent(ctx, AlarmReceiver::class.java).setAction(ctx.packageName + ".REMINDER")
            .putExtra("code", code).putExtra("title", title).putExtra("text", text)
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

    private fun textOf(l: Lesson): String {
        val m = l.notificationMinutes
        val lead = when {
            m <= 0 -> ""
            m < 60 -> "Через $m мин"
            else -> "Через ${m / 60} ч"
        }
        return listOf(lead, l.timeLabel(), l.room).filter { it.isNotBlank() }.joinToString(" · ")
    }

    fun rescheduleAll(ctx: Context, list: List<Lesson>) {
        val app = ctx.applicationContext
        val am = app.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val sp = app.getSharedPreferences("notifier", Context.MODE_PRIVATE)
        sp.getStringSet("codes", emptySet())?.forEach { c ->
            pending(app, c.toInt(), PendingIntent.FLAG_NO_CREATE)?.let { am.cancel(it); it.cancel() }
        }
        val now = LocalDateTime.now().plusSeconds(2)
        val codes = HashSet<String>()
        for (l in list) {
            if (l.notificationMinutes < 0) continue
            val tr = nextTrigger(l, now) ?: continue
            val c = codeOf(l.id)
            val p = pending(app, c, PendingIntent.FLAG_UPDATE_CURRENT, l.title.ifBlank { "Событие" }, textOf(l)) ?: continue
            val at = tr.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
            val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
            try {
                if (exact) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, p)
                else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, p)
            } catch (e: SecurityException) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, p)
            }
            codes.add(c.toString())
        }
        sp.edit().putStringSet("codes", codes).apply()
    }

    fun rescheduleFromStore(ctx: Context) {
        val json = ctx.getSharedPreferences("schedule", Context.MODE_PRIVATE).getString("json", null) ?: return
        rescheduleAll(ctx, LessonJson.fromJson(json))
    }

    fun show(ctx: Context, code: Int, title: String, text: String) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CH) == null) {
            nm.createNotificationChannel(NotificationChannel(CH, "Напоминания", NotificationManager.IMPORTANCE_HIGH))
        }
        val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
            PendingIntent.getActivity(ctx, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val n = NotificationCompat.Builder(ctx, CH)
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setLocalOnly(true)
            .setContentIntent(open)
            .build()
        try { nm.notify(code, n) } catch (e: SecurityException) { }
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        Notifier.show(ctx, i.getIntExtra("code", 0), i.getStringExtra("title") ?: "Событие", i.getStringExtra("text") ?: "")
        Notifier.rescheduleFromStore(ctx)
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        Notifier.rescheduleFromStore(ctx)
    }
}
KT_EOF
cp "$ADIR/Notifier.kt" "$WDIR/Notifier.kt"

# ======================= APP: DataSyncService.kt =======================
cat << 'KT_EOF' > "$ADIR/DataSyncService.kt"
package PKG__

import android.content.Context
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await
import org.json.JSONObject

object DataSyncService {
    const val PATH = "/schedule"
    const val FILE_PATH = "/file"
    const val FILE_DELETE_PATH = "/file_delete"
    private const val MAX_BYTES = 100_000

    /** Расписание. >0 - число часов; 0 - часов нет; -1 - ошибка; -2 - слишком большой объём. */
    suspend fun send(ctx: Context, json: String): Int = sendTo(ctx, PATH, json)

    /** Шпаргалка: сначала сохраняется в истории на телефоне, затем уходит на часы (перезаписывая по id). */
    suspend fun sendFile(ctx: Context, json: String): Int {
        val o = try { JSONObject(json) } catch (e: Exception) { return -1 }
        val f = SentStore.upsert(ctx, o.optString("id"), o.optString("name"), o.optString("text"), o.optString("time"))
        return sendTo(ctx, FILE_PATH, SentStore.toJson(f))
    }

    suspend fun sendFileDelete(ctx: Context, id: String): Int = sendTo(ctx, FILE_DELETE_PATH, id)

    private suspend fun sendTo(ctx: Context, path: String, payload: String): Int = try {
        val bytes = payload.toByteArray(Charsets.UTF_8)
        if (bytes.size > MAX_BYTES) {
            -2
        } else {
            val nodes = Wearable.getNodeClient(ctx).connectedNodes.await()
            nodes.forEach {
                Wearable.getMessageClient(ctx).sendMessage(it.id, path, bytes).await()
            }
            nodes.size
        }
    } catch (e: Exception) {
        -1
    }
}
KT_EOF

# ======================= APP: Extras.kt (напоминание, мои файлы) =======================
cat << 'KT_EOF' > "$ADIR/Extras.kt"
package PKG__

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalTime
import java.time.format.DateTimeFormatter

// ---------------------- история отправленных файлов (SharedPreferences) ----------------------
data class SentFile(val id: String, val name: String, val text: String, val time: String)

object SentStore {
    private fun sp(ctx: Context) = ctx.getSharedPreferences("sent_files", Context.MODE_PRIVATE)

    fun load(ctx: Context): List<SentFile> = try {
        val a = JSONArray(sp(ctx).getString("json", "[]"))
        (0 until a.length()).map {
            val o = a.getJSONObject(it)
            SentFile(o.getString("id"), o.optString("name", "Файл"), o.optString("text", ""), o.optString("time", ""))
        }
    } catch (e: Exception) {
        emptyList()
    }

    private fun save(ctx: Context, list: List<SentFile>) {
        val a = JSONArray()
        list.forEach {
            a.put(JSONObject().put("id", it.id).put("name", it.name).put("text", it.text).put("time", it.time))
        }
        sp(ctx).edit().putString("json", a.toString()).apply()
    }

    fun toJson(f: SentFile): String =
        JSONObject().put("id", f.id).put("name", f.name).put("text", f.text).put("time", f.time).toString()

    @Synchronized
    fun upsert(ctx: Context, id: String, name: String, text: String, time: String): SentFile {
        val list = load(ctx).toMutableList()
        val nid = id.ifBlank { System.currentTimeMillis().toString() }
        val t = time.ifBlank { LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm")) }
        val i = list.indexOfFirst { it.id == nid }
        val f = if (i >= 0) {
            list[i].copy(name = name.ifBlank { list[i].name }, text = text, time = t)
        } else {
            val n = sp(ctx).getInt("counter", 0) + 1
            sp(ctx).edit().putInt("counter", n).apply()
            SentFile(nid, name.ifBlank { "Файл $n" }, text, t)
        }
        if (i >= 0) list[i] = f else list.add(f)
        save(ctx, list)
        return f
    }

    @Synchronized
    fun delete(ctx: Context, id: String) {
        save(ctx, load(ctx).filter { it.id != id })
    }
}

// ---------------------- разрешение на уведомления ----------------------
@Composable
fun NotifPermission() {
    val ctx = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}

// ---------------------- «Напоминание» в EditScreen ----------------------
@Composable
fun NotifyRow(value: Int, onChange: (Int) -> Unit) {
    val c = C
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.card)
                .clickable { menu = true }.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Filled.Notifications, null, tint = c.sub)
            Text("Напоминание", fontSize = 16.sp, color = c.text, modifier = Modifier.weight(1f).padding(start = 12.dp))
            Text(notifyLabel(value), color = c.accent, fontSize = 15.sp)
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            NOTIFY_OPTIONS.forEach { (k, v) ->
                DropdownMenuItem(text = { Text(v) }, onClick = { onChange(k); menu = false })
            }
        }
    }
}

// ---------------------- «Мои файлы» ----------------------
@Composable
fun MyFilesHost(onClose: () -> Unit) {
    val c = C
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var files by remember { mutableStateOf(SentStore.load(ctx)) }
    var editing by remember { mutableStateOf<SentFile?>(null) }
    BackHandler { if (editing != null) editing = null else onClose() }

    fun toast(r: Int) {
        val msg = when {
            r > 0 -> "Отправлено на часы"
            r == -2 -> "Текст слишком большой"
            else -> "Сохранено на телефоне, часы не найдены"
        }
        Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show()
    }

    val cur = editing
    Column(Modifier.fillMaxSize().background(c.bg).pointerInput(Unit) {}) {
        if (cur == null) {
            Row(
                Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onClose) { Icon(Icons.Filled.ArrowBack, null, tint = c.text) }
                Text("Мои файлы", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = c.text)
            }
            if (files.isEmpty()) {
                Text("Отправленных файлов пока нет", color = c.sub, modifier = Modifier.padding(16.dp))
            }
            LazyColumn(
                Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp)
            ) {
                items(files.reversed(), key = { it.id }) { f ->
                    Row(
                        Modifier.fillMaxWidth().padding(vertical = 4.dp).clip(RoundedCornerShape(12.dp))
                            .background(c.card).clickable { editing = f }.padding(start = 14.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(Modifier.weight(1f).padding(vertical = 10.dp)) {
                            Text(f.name, fontSize = 16.sp, fontWeight = FontWeight.Medium, color = c.text)
                            Text(
                                f.text.lineSequence().firstOrNull().orEmpty(),
                                fontSize = 13.sp, color = c.sub, maxLines = 1, overflow = TextOverflow.Ellipsis
                            )
                        }
                        Text(f.time, fontSize = 13.sp, color = c.sub)
                        IconButton(onClick = {
                            SentStore.delete(ctx, f.id)
                            files = SentStore.load(ctx)
                            scope.launch { DataSyncService.sendFileDelete(ctx, f.id) }
                        }) { Icon(Icons.Filled.Delete, null, tint = Color(0xFFE53935)) }
                    }
                }
            }
        } else {
            var text by remember(cur.id) { mutableStateOf(cur.text) }
            Row(
                Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = { editing = null }) { Icon(Icons.Filled.Close, null, tint = c.text) }
                Text(
                    cur.name, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.text,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = {
                    SentStore.delete(ctx, cur.id)
                    files = SentStore.load(ctx)
                    editing = null
                    scope.launch { DataSyncService.sendFileDelete(ctx, cur.id) }
                }) { Icon(Icons.Filled.Delete, null, tint = Color(0xFFE53935)) }
            }
            OutlinedTextField(
                value = text, onValueChange = { text = it },
                label = { Text("Текст или формулы") },
                modifier = Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
            )
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                TextButton(onClick = { editing = null }) { Text("Отмена", fontSize = 16.sp) }
                TextButton(onClick = {
                    if (text.isNotBlank()) {
                        val time = LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm"))
                        val saved = SentStore.upsert(ctx, cur.id, cur.name, text, time)
                        files = SentStore.load(ctx)
                        editing = null
                        scope.launch { toast(DataSyncService.sendFile(ctx, SentStore.toJson(saved))) }
                    }
                }) { Text("Сохранить и отправить", fontSize = 16.sp, fontWeight = FontWeight.Bold) }
            }
        }
    }
}
KT_EOF

# ======================= APP: патчи MainActivity.kt =======================
if ! grep -q 'MyFilesHost' "$AOS"; then
  sed -i '/^    var showSend by remember { mutableStateOf(false) }$/a\
    var showFiles by remember { mutableStateOf(false) }' "$AOS"
  sed -i '/^    LaunchedEffect(Unit) { sync(lessons, false) }$/c\
    LaunchedEffect(Unit) { sync(lessons, false); Notifier.rescheduleAll(ctx, lessons) }\
    NotifPermission()' "$AOS"
  sed -i '/^        repo.save(list)$/a\
        Notifier.rescheduleAll(ctx, list)' "$AOS"
  sed -i '/vertical = 24.dp)$/{
n
a\
                    NavigationDrawerItem(\
                        label = { Text("Мои файлы") },\
                        icon = { Icon(Icons.Filled.Description, null) },\
                        selected = false,\
                        onClick = {\
                            scope.launch { drawerState.close() }\
                            showFiles = true\
                        },\
                        modifier = Modifier.padding(horizontal = 12.dp)\
                    )
}' "$AOS"
  sed -i '/^        editing?.let { orig ->$/i\
        if (showFiles) MyFilesHost { showFiles = false }' "$AOS"
fi
if ! grep -q 'notifyMin' "$AOS"; then
  sed -i '/^    var recurrence by remember { mutableStateOf(init.recurrence) }$/a\
    var notifyMin by remember { mutableStateOf(init.notificationMinutes) }' "$AOS"
  sed -i 's/room = room.trim(), recurrence = recurrence/room = room.trim(), recurrence = recurrence, notificationMinutes = notifyMin/' "$AOS"
  sed -i '/^            if (init.id != 0L) {$/i\
            NotifyRow(notifyMin) { notifyMin = it }' "$AOS"
fi

# ======================= WEAR: DataSyncService.kt =======================
cat << 'KT_EOF' > "$WDIR/DataSyncService.kt"
package PKG__

import android.content.Context
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalTime
import java.time.format.DateTimeFormatter

data class WearFile(val id: String, val name: String, val text: String, val time: String)

/** Полученные шпаргалки: список JSON-объектов в SharedPreferences. */
object FileStore {
    private const val MAX = 50
    private val _files = MutableStateFlow<List<WearFile>>(emptyList())
    val files: StateFlow<List<WearFile>> = _files.asStateFlow()

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("files", Context.MODE_PRIVATE)

    private fun read(ctx: Context): List<WearFile> = try {
        val a = JSONArray(prefs(ctx).getString("json", "[]") ?: "[]")
        (0 until a.length()).map {
            val o = a.getJSONObject(it)
            WearFile(o.getString("id"), o.optString("name", "Файл"), o.optString("text", ""), o.optString("time", ""))
        }
    } catch (e: Exception) {
        emptyList()
    }

    private fun write(ctx: Context, list: List<WearFile>) {
        val a = JSONArray()
        list.forEach {
            a.put(JSONObject().put("id", it.id).put("name", it.name).put("text", it.text).put("time", it.time))
        }
        prefs(ctx).edit().putString("json", a.toString()).apply()
        _files.value = list
    }

    fun init(ctx: Context) {
        _files.value = read(ctx)
    }

    /** json: {"id","name","text","time"}. Файл с тем же id перезаписывается. */
    @Synchronized
    fun upsert(ctx: Context, json: String) {
        val o = try { JSONObject(json) } catch (e: Exception) { return }
        val text = o.optString("text", "")
        if (text.isBlank()) return
        val id = o.optString("id", "").ifBlank { System.currentTimeMillis().toString() }
        val time = o.optString("time", "").ifBlank { LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm")) }
        val name = o.optString("name", "")
        val cur = read(ctx)
        val i = cur.indexOfFirst { it.id == id }
        val next = if (i >= 0) {
            cur.toMutableList().also { it[i] = it[i].copy(name = name.ifBlank { it[i].name }, text = text, time = time) }
        } else {
            val p = prefs(ctx)
            val n = p.getInt("counter", 0) + 1
            p.edit().putInt("counter", n).apply()
            cur + WearFile(id, name.ifBlank { "Файл $n" }, text, time)
        }
        write(ctx, next.takeLast(MAX))
    }

    @Synchronized
    fun delete(ctx: Context, id: String) {
        write(ctx, read(ctx).filter { it.id != id })
    }
}

class DataSyncService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        try {
            val body = String(event.data, Charsets.UTF_8)
            when (event.path) {
                "/schedule" -> if (body.trim().startsWith("[")) {
                    ScheduleRepository.update(applicationContext, body)
                    Notifier.rescheduleAll(applicationContext, LessonJson.fromJson(body))
                }
                "/file" -> FileStore.upsert(applicationContext, body)
                "/file_delete" -> FileStore.delete(applicationContext, body.trim())
            }
        } catch (e: Exception) {
            // повреждённые данные игнорируем, на часах остаётся прежнее состояние
        }
    }
}
KT_EOF

# ======================= WEAR: WearHome.kt (главный экран по референсу) =======================
cat << 'KT_EOF' > "$WDIR/WearHome.kt"
@file:OptIn(ExperimentalFoundationApi::class)

package PKG__

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

const val DAYS_RANGE = 30
private val WRU: Locale = Locale("ru")

private fun nowMinutes(): Int {
    val t = LocalTime.now()
    return t.hour * 60 + t.minute
}

private fun hm(s: String): Int =
    (s.substringBefore(":").toIntOrNull() ?: 0) * 60 + (s.substringAfter(":").toIntOrNull() ?: 0)

private fun batteryPct(ctx: Context): Int = try {
    (ctx.getSystemService(Context.BATTERY_SERVICE) as BatteryManager)
        .getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
} catch (e: Exception) {
    -1
}

private fun lessonsWord(n: Int): String {
    val m100 = n % 100
    val m10 = n % 10
    return if (m100 in 11..14) "уроков" else when (m10) {
        1 -> "урок"
        in 2..4 -> "урока"
        else -> "уроков"
    }
}

@Composable
fun WearApp() {
    val ctx = LocalContext.current
    val lessons by ScheduleRepository.lessons.collectAsState()
    val files by FileStore.files.collectAsState()
    var detail by remember { mutableStateOf<Lesson?>(null) }
    var overlay by remember { mutableStateOf(Overlay.NONE) }
    var viaMenu by remember { mutableStateOf(false) }
    var openId by remember { mutableStateOf<String?>(null) }
    var inDays by remember { mutableStateOf(false) }
    var startPage by remember { mutableStateOf(DAYS_RANGE) }
    var daysKey by remember { mutableStateOf(0) }
    var picked by remember { mutableStateOf(0) }
    var nowMin by remember { mutableStateOf(nowMinutes()) }
    var battery by remember { mutableStateOf(batteryPct(ctx)) }
    val today = remember { LocalDate.now() }
    val perm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }

    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            perm.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    LaunchedEffect(lessons) { Notifier.rescheduleAll(ctx, lessons) }
    LaunchedEffect(Unit) {
        while (true) {
            nowMin = nowMinutes()
            battery = batteryPct(ctx)
            delay(60_000L - System.currentTimeMillis() % 60_000L)
        }
    }

    BackHandler(enabled = detail != null || overlay != Overlay.NONE || inDays) {
        when {
            overlay == Overlay.FILE -> overlay = Overlay.FILES
            overlay == Overlay.FILES || overlay == Overlay.DATES ->
                overlay = if (viaMenu) Overlay.MENU else Overlay.NONE
            overlay == Overlay.MENU -> overlay = Overlay.NONE
            detail != null -> detail = null
            else -> inDays = false
        }
    }

    MaterialTheme {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            val d = detail
            if (d != null) {
                DetailScreen(d) { detail = null }
            } else {
                if (inDays) {
                    key(daysKey) {
                        DaysScreen(
                            startPage, lessons, today, nowMin,
                            onOpen = { detail = it },
                            onMenu = { viaMenu = true; overlay = Overlay.MENU }
                        )
                    }
                } else {
                    HomeScreen(
                        lessons, today, nowMin, battery,
                        onOpen = { detail = it },
                        onFiles = { viaMenu = false; overlay = Overlay.FILES },
                        onDates = { viaMenu = false; overlay = Overlay.DATES },
                        onDays = { startPage = DAYS_RANGE; picked = 0; daysKey++; inDays = true }
                    )
                }
                when (overlay) {
                    Overlay.MENU -> MenuPanel(
                        filesCount = files.size,
                        onDates = { overlay = Overlay.DATES },
                        onFiles = { overlay = Overlay.FILES }
                    )
                    Overlay.DATES -> DatesDrawer(today, picked) { i ->
                        picked = i
                        startPage = DAYS_RANGE + i
                        daysKey++
                        inDays = true
                        overlay = Overlay.NONE
                    }
                    Overlay.FILES -> FilesScreen(files) { f ->
                        openId = f.id
                        overlay = Overlay.FILE
                    }
                    Overlay.FILE -> {
                        val f = files.firstOrNull { it.id == openId }
                        if (f != null) {
                            FileViewer(f) {
                                FileStore.delete(ctx, f.id)
                                overlay = Overlay.FILES
                            }
                        } else {
                            FilesScreen(files) { x ->
                                openId = x.id
                                overlay = Overlay.FILE
                            }
                        }
                    }
                    Overlay.NONE -> {}
                }
            }
        }
    }
}

@Composable
private fun DaysScreen(
    startPage: Int, lessons: List<Lesson>, today: LocalDate, nowMin: Int,
    onOpen: (Lesson) -> Unit, onMenu: () -> Unit
) {
    val pager = rememberPagerState(initialPage = startPage) { DAYS_RANGE * 2 + 1 }
    Box(Modifier.fillMaxSize()) {
        HorizontalPager(state = pager) { page ->
            val date = today.plusDays((page - DAYS_RANGE).toLong())
            DayPage(date, lessons, date == today, nowMin, onOpen, onMenu)
        }
        // левый край: свайп слева направо открывает меню
        Box(
            Modifier.align(Alignment.CenterStart).fillMaxHeight().width(24.dp)
                .pointerInput(Unit) {
                    var total = 0f
                    detectHorizontalDragGestures(
                        onDragStart = { total = 0f },
                        onDragEnd = { if (total > 40f) onMenu() },
                        onDragCancel = { total = 0f },
                        onHorizontalDrag = { _, dx -> total += dx }
                    )
                }
        )
    }
}

@Composable
private fun HomeScreen(
    lessons: List<Lesson>, today: LocalDate, nowMin: Int, battery: Int,
    onOpen: (Lesson) -> Unit, onFiles: () -> Unit, onDates: () -> Unit, onDays: () -> Unit
) {
    val ctx = LocalContext.current
    val bgId = remember { ctx.resources.getIdentifier("watch_face_bg", "drawable", ctx.packageName) }
    val all = remember(lessons, today) {
        lessons.filter { it.occursOn(today) }
            .sortedWith(compareByDescending<Lesson> { it.isAllDay }.thenBy { it.start })
    }
    val next = remember(all, nowMin) { all.filter { it.isAllDay || hm(it.end) > nowMin } }
    val prog = ((nowMin - 480) / 600f).coerceIn(0f, 1f)
    val dateText = remember(today) {
        today.format(DateTimeFormatter.ofPattern("EEE, d MMM", WRU)).replaceFirstChar { it.uppercase() }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (bgId != 0) {
            Image(painterResource(bgId), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alpha = 0.55f)
        }
        // дуга по левому краю: прогресс учебного дня (08:00-18:00)
        Canvas(Modifier.fillMaxSize()) {
            val sw = 4.dp.toPx()
            val inset = sw / 2f + 2.dp.toPx()
            val tl = Offset(inset, inset)
            val sz = Size(size.width - 2f * inset, size.height - 2f * inset)
            drawArc(Color(0xFF2A2740), 270f, -170f, false, tl, sz, style = Stroke(sw, cap = StrokeCap.Round))
            if (prog > 0f) {
                drawArc(Pal.Purple, 270f, -170f * prog, false, tl, sz, style = Stroke(sw, cap = StrokeCap.Round))
            }
        }
        Column(
            Modifier.fillMaxSize().padding(top = 10.dp, bottom = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.CalendarMonth, null, tint = Pal.Lilac, modifier = Modifier.size(16.dp))
                Text(
                    "  $dateText", color = Color(0xFFE6E0FF), fontSize = 14.sp,
                    fontWeight = FontWeight.Bold, maxLines = 1
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    buildAnnotatedString {
                        withStyle(SpanStyle(color = Color.White)) { append("%02d".format(nowMin / 60)) }
                        withStyle(SpanStyle(color = Color(0xFF8C88A8))) { append(":") }
                        withStyle(SpanStyle(color = Pal.Purple)) { append("%02d".format(nowMin % 60)) }
                    },
                    fontSize = 42.sp, lineHeight = 44.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1
                )
                Spacer(Modifier.width(6.dp))
                Box(
                    Modifier.size(38.dp).background(
                        Brush.radialGradient(listOf(Color(0x667C5CFF), Color.Transparent)), CircleShape
                    ),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Filled.CalendarMonth, null, tint = Pal.Lilac, modifier = Modifier.size(26.dp))
                }
            }
            Spacer(Modifier.height(4.dp))
            Row(
                Modifier.clip(RoundedCornerShape(14.dp)).background(Color(0xFF14131C))
                    .clickable(onClick = onDays).padding(horizontal = 10.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(Modifier.size(7.dp).clip(CircleShape).background(Pal.Purple))
                Text(
                    "  Сегодня • " + (if (all.isEmpty()) "занятий нет" else "${all.size} ${lessonsWord(all.size)}"),
                    color = Color(0xFFE6E0FF), fontSize = 12.sp, maxLines = 1
                )
            }
            Spacer(Modifier.height(6.dp))
            Column(
                Modifier.weight(1f).fillMaxWidth().padding(horizontal = 24.dp).clipToBounds(),
                verticalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                if (next.isEmpty()) {
                    Text(
                        if (all.isEmpty()) "Занятий нет" else "На сегодня всё",
                        color = Pal.Dim, fontSize = 13.sp,
                        modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp)
                    )
                }
                next.take(3).forEach { HomeCard(it) { onOpen(it) } }
            }
        }
        // стрелки: левая - «Файлы», правая - «Даты»
        Box(
            Modifier.align(Alignment.CenterStart).padding(start = 3.dp).size(28.dp).clip(CircleShape)
                .background(Color(0xFF1B1A22)).clickable(onClick = onFiles),
            contentAlignment = Alignment.Center
        ) { Icon(Icons.Filled.ChevronLeft, null, tint = Color.White, modifier = Modifier.size(20.dp)) }
        Box(
            Modifier.align(Alignment.CenterEnd).padding(end = 3.dp).size(28.dp).clip(CircleShape)
                .background(Color(0xFF1B1A22)).clickable(onClick = onDates),
            contentAlignment = Alignment.Center
        ) { Icon(Icons.Filled.ChevronRight, null, tint = Color.White, modifier = Modifier.size(20.dp)) }
        if (battery > 0) {
            Row(
                Modifier.align(Alignment.TopEnd).padding(top = 28.dp, end = 34.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Filled.BatteryFull, null, tint = Pal.Lilac, modifier = Modifier.size(13.dp))
                Text(" $battery%", color = Pal.Dim, fontSize = 11.sp, maxLines = 1)
            }
        }
        Row(
            Modifier.align(Alignment.BottomCenter).padding(bottom = 7.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(Modifier.size(7.dp).clip(CircleShape).background(Pal.Purple))
            Box(Modifier.size(6.dp).clip(CircleShape).background(Color(0xFF3A3A44)))
            Box(Modifier.size(6.dp).clip(CircleShape).background(Color(0xFF3A3A44)))
        }
    }
}

@Composable
private fun HomeCard(l: Lesson, onClick: () -> Unit) {
    val col = parseColor(l.color)
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Color(0xFF17161F))
            .clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(5.dp).height(46.dp).background(col))
        Column(Modifier.weight(1f).padding(horizontal = 8.dp, vertical = 5.dp)) {
            Text(l.timeLabel(), color = Color(0xFFB8B2D6), fontSize = 11.sp, maxLines = 1)
            Text(l.title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            if (l.room.isNotBlank()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.LocationOn, null, tint = Pal.Lilac, modifier = Modifier.size(11.dp))
                    Text(" ${l.room}", color = Color(0xFFB8B2D6), fontSize = 10.sp, maxLines = 1)
                }
            }
        }
        Box(
            Modifier.padding(end = 8.dp).size(28.dp).clip(RoundedCornerShape(8.dp))
                .background(col.copy(alpha = 0.35f)),
            contentAlignment = Alignment.Center
        ) {
            if (l.emoji.isNotBlank()) Text(l.emoji, fontSize = 14.sp)
            else Icon(iconFor(l.icon), null, tint = Color.White, modifier = Modifier.size(18.dp))
        }
    }
}
KT_EOF

# ======================= WEAR: старый WearApp -> WearAppOld (остальной код не трогаем) =======================
if ! grep -q 'fun WearAppOld' "$WOS"; then
  sed -i 's/^fun WearApp() {$/fun WearAppOld() {/' "$WOS"
fi

# ======================= Подстановка пакета =======================
for f in Lesson.kt Notifier.kt Extras.kt DataSyncService.kt; do
  sed -i "s/PKG__/${APKG}/g" "$ADIR/$f"
done
for f in Lesson.kt Notifier.kt WearHome.kt DataSyncService.kt; do
  sed -i "s/PKG__/${WPKG}/g" "$WDIR/$f"
done

# ======================= Проверка патчей =======================
chk() { grep -q "$1" "$2" || echo "!! ПАТЧ НЕ ПРИМЕНЁН: $3 (файл изменён вручную?)"; }
chk 'MyFilesHost'          "$AOS" 'телефон: экран «Мои файлы»'
chk 'showFiles = true'     "$AOS" 'телефон: пункт «Мои файлы» в меню'
chk 'Notifier.rescheduleAll(ctx, list)' "$AOS" 'телефон: планирование при сохранении'
chk 'NotifPermission()'    "$AOS" 'телефон: запрос разрешения'
chk 'notifyMin'            "$AOS" 'телефон: список «Напоминание»'
chk 'notificationMinutes = notifyMin' "$AOS" 'телефон: сохранение напоминания'
chk 'fun WearAppOld'       "$WOS" 'часы: переименование старого WearApp'

echo 'Готово!'
echo 'Дальше: git add . && git commit -m "Notifications, my files, watch face" && git push'
