#!/data/data/com.termux/files/usr/bin/bash
set +H
cd "${1:-$HOME/ScheduleApp}" || { echo 'Папка проекта не найдена'; exit 1; }

AOS=$(find app -name MainActivity.kt -not -path '*/build/*' 2>/dev/null | head -1)
WOS=$(find wear -name MainActivity.kt -not -path '*/build/*' 2>/dev/null | head -1)
if [ -z "$AOS" ] || [ -z "$WOS" ]; then echo 'MainActivity.kt не найден. Запусти из корня проекта'; exit 1; fi
ADIR=$(dirname "$AOS")
WDIR=$(dirname "$WOS")
APKG=$(grep -m1 '^package' "$AOS" | tr -d '\r' | sed 's/^package[[:space:]]*//; s/[[:space:]]*$//')
WPKG=$(grep -m1 '^package' "$WOS" | tr -d '\r' | sed 's/^package[[:space:]]*//; s/[[:space:]]*$//')
if [ -z "$APKG" ]; then APKG="com.example.schedule"; fi
if [ -z "$WPKG" ]; then WPKG="$APKG"; fi
echo "APP: DIR=$ADIR PKG=$APKG"
echo "WEAR: DIR=$WDIR PKG=$WPKG"

# ======================= APP: ScheduleRepository.kt =======================
cat << 'KT_EOF' > "$ADIR/ScheduleRepository.kt"
package PKG__

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.time.DayOfWeek
import java.time.LocalDate

data class TimeSlot(val id: Long, val name: String, val start: String, val end: String)

class ScheduleRepository(ctx: Context) {
    private val sp = ctx.getSharedPreferences("schedule", Context.MODE_PRIVATE)

    fun load(): List<Lesson> {
        val s = sp.getString("json", null) ?: return defaults().also { save(it) }
        return LessonJson.fromJson(s)
    }

    fun save(list: List<Lesson>) {
        sp.edit().putString("json", LessonJson.toJson(list)).apply()
    }

    // ---------- слоты времени ----------
    fun loadSlots(): List<TimeSlot> {
        val s = sp.getString("slots", null) ?: return defaultSlots().also { saveSlots(it) }
        return try {
            val a = JSONArray(s)
            (0 until a.length()).map {
                val o = a.getJSONObject(it)
                TimeSlot(o.getLong("id"), o.optString("name", ""), o.getString("start"), o.getString("end"))
            }
        } catch (e: Exception) {
            defaultSlots()
        }
    }

    fun saveSlots(list: List<TimeSlot>) {
        val arr = JSONArray()
        list.forEach {
            arr.put(JSONObject().put("id", it.id).put("name", it.name).put("start", it.start).put("end", it.end))
        }
        sp.edit().putString("slots", arr.toString()).apply()
    }

    private fun defaultSlots() = listOf(
        TimeSlot(1, "1 урок", "08:30", "09:15"),
        TimeSlot(2, "2 урок", "09:25", "10:10"),
        TimeSlot(3, "3 урок", "10:25", "11:10"),
        TimeSlot(4, "4 урок", "11:20", "12:05")
    )

    private fun weekly(
        id: Long, dow: DayOfWeek, start: String, end: String,
        title: String, room: String, icon: String, color: String
    ) = Lesson(
        id = id, title = title,
        date = LocalDate.now().with(dow).minusWeeks(8).toString(),
        recurrence = "WEEKLY", isAllDay = false, color = color,
        start = start, end = end, room = room, icon = icon, emoji = "",
        exceptions = emptyList()
    )

    private fun defaults() = listOf(
        weekly(1, DayOfWeek.WEDNESDAY, "08:30", "09:15", "Математика", "Каб. 101", "math", "#8E24AA"),
        weekly(2, DayOfWeek.WEDNESDAY, "09:25", "10:10", "Физика", "Каб. 203", "physics", "#1A73E8"),
        weekly(3, DayOfWeek.WEDNESDAY, "10:25", "11:10", "Информатика", "Каб. 305", "it", "#0B8043"),
        weekly(4, DayOfWeek.WEDNESDAY, "11:20", "12:05", "История", "Каб. 110", "history", "#F6BF26"),
        weekly(5, DayOfWeek.THURSDAY, "08:30", "09:15", "Русский язык", "Каб. 204", "lit", "#F4511E"),
        weekly(6, DayOfWeek.THURSDAY, "09:25", "10:10", "Биология", "Каб. 301", "bio", "#0B8043"),
        weekly(7, DayOfWeek.THURSDAY, "10:25", "11:10", "Химия", "Каб. 207", "chem", "#039BE5")
    )
}
KT_EOF

# ======================= APP: MainActivity.kt =======================
cat << 'KT_EOF' > "$ADIR/MainActivity.kt"
@file:OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)

package PKG__

import android.content.res.Configuration
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale

const val MONTH_BASE = 12
const val MONTH_COUNT = 25   // ±12 месяцев

val RU: Locale = Locale("ru")
val DAYS = listOf("Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс")
val EMOJIS = listOf(
    "📚", "🧮", "🔬", "💻", "🎨", "🎵", "⚽", "🌍",
    "📝", "🧪", "🏛️", "🧬", "🗣️", "🎭", "⏰", "⭐"
)

// ======================= РАСШИРЕННАЯ ПАЛИТРА (по 16 цветов) =======================
val PALETTE_BRIGHT = listOf(
    "#D50000", "#F4511E", "#FB8C00", "#F6BF26", "#C0CA33", "#0B8043", "#00897B", "#039BE5",
    "#1A73E8", "#3F51B5", "#7C5CFF", "#8E24AA", "#E91E63", "#FF4081", "#00BCD4", "#76FF03"
)
val PALETTE_PASTEL = listOf(
    "#FFB3BA", "#FFDFBA", "#FFFFBA", "#BAFFC9", "#BAE1FF", "#D7BAFF", "#FFC8DD", "#CDB4DB",
    "#A2D2FF", "#B5EAD7", "#E2F0CB", "#FFDAC1", "#C7CEEA", "#F8C8DC", "#B9FBC0", "#FDE4CF"
)
val PALETTE_DARK = listOf(
    "#B71C1C", "#BF360C", "#E65100", "#827717", "#1B5E20", "#004D40", "#006064", "#01579B",
    "#0D47A1", "#1A237E", "#311B92", "#4A148C", "#880E4F", "#3E2723", "#37474F", "#212121"
)

fun onColor(col: Color): Color = if (col.luminance() > 0.55f) Color.Black else Color.White

private fun hmOf(s: String): Pair<Int, Int> =
    (s.substringBefore(":").toIntOrNull() ?: 0).coerceIn(0, 23) to
        (s.substringAfter(":").toIntOrNull() ?: 0).coerceIn(0, 59)

// ======================= ТЕМА =======================
class AppColors(
    val bg: Color, val text: Color, val sub: Color, val accent: Color,
    val card: Color, val sat: Color, val sun: Color, val dark: Boolean
)

val LightColors = AppColors(
    Color(0xFFFFFFFF), Color(0xFF000000), Color(0xFF757575), Color(0xFF1A73E8),
    Color(0xFFF5F5F5), Color(0xFF1A73E8), Color(0xFFE53935), false
)
val DarkColors = AppColors(
    Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFF9E9E9E), Color(0xFF1A73E8),
    Color(0xFF1E1E1E), Color(0xFF5C9DFF), Color(0xFFFF6B6B), true
)
val LocalAppColors = staticCompositionLocalOf { LightColors }
val C: AppColors
    @Composable @ReadOnlyComposable get() = LocalAppColors.current

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Locale.setDefault(RU)
        val repo = ScheduleRepository(this)
        setContent {
            val dark = isSystemInDarkTheme()
            val c = if (dark) DarkColors else LightColors
            val scheme = if (dark) darkColorScheme(
                primary = c.accent, onPrimary = Color.White, background = c.bg,
                onBackground = c.text, surface = c.bg, onSurface = c.text,
                surfaceVariant = c.card, onSurfaceVariant = c.sub
            ) else lightColorScheme(
                primary = c.accent, onPrimary = Color.White, background = c.bg,
                onBackground = c.text, surface = c.bg, onSurface = c.text,
                surfaceVariant = c.card, onSurfaceVariant = c.sub
            )
            SideEffect {
                window.statusBarColor = c.bg.toArgb()
                window.navigationBarColor = c.bg.toArgb()
                val ctl = WindowCompat.getInsetsController(window, window.decorView)
                ctl.isAppearanceLightStatusBars = !dark
                ctl.isAppearanceLightNavigationBars = !dark
            }
            CompositionLocalProvider(LocalAppColors provides c) {
                MaterialTheme(colorScheme = scheme) {
                    Surface(Modifier.fillMaxSize(), color = c.bg, contentColor = c.text) {
                        App(repo)
                    }
                }
            }
        }
    }
}

// ======================= КОРНЕВОЙ ЭКРАН =======================
@Composable
fun App(repo: ScheduleRepository) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val today = remember { LocalDate.now() }
    var lessons by remember { mutableStateOf(repo.load()) }
    var slots by remember { mutableStateOf(repo.loadSlots()) }
    var selected by remember { mutableStateOf(today) }
    var editing by remember { mutableStateOf<Lesson?>(null) }
    var editDate by remember { mutableStateOf(today) }
    var pendingSave by remember { mutableStateOf<Lesson?>(null) }
    var pendingDelete by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    val drawerState = rememberDrawerState(DrawerValue.Closed)

    fun sync(list: List<Lesson>, notify: Boolean) {
        scope.launch {
            val r = DataSyncService.send(ctx, LessonJson.toJson(list))
            if (notify) {
                val msg = when {
                    r > 0 -> "Отправлено на часы"
                    r == -2 -> "Слишком много событий для отправки"
                    else -> "Часы не найдены"
                }
                Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun persist(list: List<Lesson>) {
        lessons = list
        repo.save(list)
        sync(list, true)
    }

    fun persistSlots(list: List<TimeSlot>) {
        slots = list
        repo.saveSlots(list)
    }

    LaunchedEffect(Unit) { sync(lessons, false) }
    BackHandler(enabled = drawerState.isOpen) { scope.launch { drawerState.close() } }
    BackHandler(enabled = showSettings && editing == null) { showSettings = false }
    BackHandler(enabled = editing != null) { editing = null }

    Box(Modifier.fillMaxSize()) {
        ModalNavigationDrawer(
            drawerState = drawerState,
            gesturesEnabled = drawerState.isOpen,
            drawerContent = {
                ModalDrawerSheet {
                    Text(
                        "Расписание", fontSize = 22.sp, fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 24.dp)
                    )
                    NavigationDrawerItem(
                        label = { Text("Настройки") },
                        icon = { Icon(Icons.Filled.Settings, null) },
                        selected = false,
                        onClick = {
                            scope.launch { drawerState.close() }
                            showSettings = true
                        },
                        modifier = Modifier.padding(horizontal = 12.dp)
                    )
                }
            }
        ) {
            MainScreen(
                lessons = lessons, today = today, selected = selected,
                onSelect = { selected = it },
                onOpen = { l, d -> editDate = d; editing = l },
                onNew = {
                    editDate = selected
                    editing = Lesson(id = 0L, title = "", date = selected.toString(), color = PALETTE[0])
                },
                onManualSync = { sync(lessons, true) },
                onMenu = { scope.launch { drawerState.open() } }
            )
        }

        if (showSettings) {
            SettingsScreen(
                lessons = lessons, slots = slots,
                onSlots = { persistSlots(it) },
                onImport = { list, replace ->
                    if (replace) {
                        persist(list)
                    } else {
                        val used = lessons.mapTo(HashSet()) { it.id }
                        var k = System.currentTimeMillis()
                        val add = list.map { l ->
                            var id = l.id
                            while (!used.add(id)) { k++; id = k }
                            l.copy(id = id)
                        }
                        persist(lessons + add)
                    }
                    Toast.makeText(ctx, "Импортировано событий: ${list.size}", Toast.LENGTH_SHORT).show()
                },
                onBack = { showSettings = false }
            )
        }

        editing?.let { orig ->
            key(orig.id) {
                EditScreen(
                    init = orig, initDate = editDate, all = lessons, slots = slots,
                    onSave = { edited ->
                        when {
                            orig.id == 0L -> {
                                persist(lessons + edited.copy(id = System.currentTimeMillis()))
                                editing = null
                            }
                            orig.recurrence == "NONE" -> {
                                persist(lessons.map { if (it.id == orig.id) edited else it })
                                editing = null
                            }
                            else -> pendingSave = edited
                        }
                    },
                    onDelete = {
                        if (orig.recurrence == "NONE") {
                            persist(lessons.filter { it.id != orig.id })
                            editing = null
                        } else {
                            pendingDelete = true
                        }
                    },
                    onCancel = { editing = null }
                )
            }
        }
    }

    val orig = editing
    val ps = pendingSave
    if (ps != null && orig != null) {
        AlertDialog(
            onDismissRequest = { pendingSave = null },
            title = { Text("Изменить событие") },
            text = { Text("Это повторяющееся событие.") },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    TextButton(onClick = {
                        val one = ps.copy(id = System.currentTimeMillis(), recurrence = "NONE", exceptions = emptyList())
                        persist(
                            lessons.map {
                                if (it.id == orig.id) it.copy(exceptions = it.exceptions + editDate.toString()) else it
                            } + one
                        )
                        pendingSave = null; editing = null
                    }) { Text("Изменить только это") }
                    TextButton(onClick = {
                        val delta = ChronoUnit.DAYS.between(editDate, parseDate(ps.date))
                        val base = parseDate(orig.date).plusDays(delta)
                        persist(
                            lessons.map {
                                if (it.id == orig.id) ps.copy(date = base.toString(), exceptions = orig.exceptions) else it
                            }
                        )
                        pendingSave = null; editing = null
                    }) { Text("Изменить всю серию") }
                    TextButton(onClick = { pendingSave = null }) { Text("Отмена") }
                }
            }
        )
    }
    if (pendingDelete && orig != null) {
        AlertDialog(
            onDismissRequest = { pendingDelete = false },
            title = { Text("Удалить событие") },
            text = { Text("Это повторяющееся событие.") },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    TextButton(onClick = {
                        persist(
                            lessons.map {
                                if (it.id == orig.id) it.copy(exceptions = it.exceptions + editDate.toString()) else it
                            }
                        )
                        pendingDelete = false; editing = null
                    }) { Text("Удалить это событие") }
                    TextButton(onClick = {
                        persist(lessons.filter { it.id != orig.id })
                        pendingDelete = false; editing = null
                    }) { Text("Удалить всю серию") }
                    TextButton(onClick = { pendingDelete = false }) { Text("Отмена") }
                }
            }
        )
    }
}

// ======================= НАСТРОЙКИ =======================
@Composable
fun SettingsScreen(
    lessons: List<Lesson>,
    slots: List<TimeSlot>,
    onSlots: (List<TimeSlot>) -> Unit,
    onImport: (List<Lesson>, Boolean) -> Unit,
    onBack: () -> Unit
) {
    val c = C
    val ctx = LocalContext.current
    var editSlot by remember { mutableStateOf<TimeSlot?>(null) }
    var pending by remember { mutableStateOf<List<Lesson>?>(null) }

    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        if (uri != null) {
            val ok = try {
                val out = ctx.contentResolver.openOutputStream(uri)
                if (out == null) {
                    false
                } else {
                    out.use { it.write(LessonJson.toJson(lessons).toByteArray(Charsets.UTF_8)) }
                    true
                }
            } catch (e: Exception) {
                false
            }
            Toast.makeText(
                ctx, if (ok) "События выгружены" else "Не удалось сохранить файл", Toast.LENGTH_SHORT
            ).show()
        }
    }

    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            val text = try {
                ctx.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
            } catch (e: Exception) {
                null
            }
            val list = if (text != null && text.trim().startsWith("[")) LessonJson.fromJson(text) else emptyList()
            if (list.isEmpty()) {
                Toast.makeText(ctx, "Файл не содержит событий", Toast.LENGTH_SHORT).show()
            } else {
                pending = list
            }
        }
    }

    Column(Modifier.fillMaxSize().background(c.bg).pointerInput(Unit) {}) {
        Row(
            Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, null, tint = c.text) }
            Text("Настройки", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = c.text)
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text("Слоты времени", fontSize = 14.sp, color = c.accent, fontWeight = FontWeight.Bold)
            if (slots.isEmpty()) Text("Слотов пока нет", color = c.sub)
            slots.forEach { s ->
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.card).padding(start = 14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f).padding(vertical = 10.dp)) {
                        Text(s.name, fontSize = 16.sp, color = c.text, fontWeight = FontWeight.Medium)
                        Text("${s.start} – ${s.end}", fontSize = 13.sp, color = c.sub)
                    }
                    IconButton(onClick = { editSlot = s }) { Icon(Icons.Filled.Edit, null, tint = c.sub) }
                    IconButton(onClick = { onSlots(slots.filter { it.id != s.id }) }) {
                        Icon(Icons.Filled.Delete, null, tint = Color(0xFFE53935))
                    }
                }
            }
            TextButton(onClick = { editSlot = TimeSlot(0L, "", "08:30", "09:15") }) {
                Icon(Icons.Filled.Add, null)
                Spacer(Modifier.width(8.dp))
                Text("Добавить слот")
            }

            Spacer(Modifier.height(8.dp))
            Text("Экспорт / Импорт", fontSize = 14.sp, color = c.accent, fontWeight = FontWeight.Bold)
            Button(
                onClick = { exportLauncher.launch("schedule_events.json") },
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Filled.Save, null)
                Spacer(Modifier.width(8.dp))
                Text("Выгрузить события")
            }
            OutlinedButton(
                onClick = { importLauncher.launch(arrayOf("*/*")) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Filled.FolderOpen, null)
                Spacer(Modifier.width(8.dp))
                Text("Загрузить события")
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    editSlot?.let { s ->
        SlotDialog(
            init = s,
            onSave = { v ->
                val fixed = if (v.id == 0L) v.copy(id = System.currentTimeMillis()) else v
                val next = if (slots.any { it.id == fixed.id }) slots.map { if (it.id == fixed.id) fixed else it }
                else slots + fixed
                onSlots(next.sortedBy { it.start })
                editSlot = null
            },
            onDismiss = { editSlot = null }
        )
    }

    pending?.let { list ->
        AlertDialog(
            onDismissRequest = { pending = null },
            title = { Text("Загрузка событий") },
            text = { Text("Найдено событий в файле: ${list.size}") },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    TextButton(onClick = { onImport(list, true); pending = null }) { Text("Заменить все") }
                    TextButton(onClick = { onImport(list, false); pending = null }) { Text("Добавить") }
                    TextButton(onClick = { pending = null }) { Text("Отмена") }
                }
            }
        )
    }
}

@Composable
fun SlotDialog(init: TimeSlot, onSave: (TimeSlot) -> Unit, onDismiss: () -> Unit) {
    val c = C
    val (h1, m1) = remember { hmOf(init.start) }
    val (h2, m2) = remember { hmOf(init.end) }
    var name by remember { mutableStateOf(init.name) }
    var sh by remember { mutableStateOf(h1) }
    var sm by remember { mutableStateOf(m1) }
    var eh by remember { mutableStateOf(h2) }
    var em by remember { mutableStateOf(m2) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (init.id == 0L) "Новый слот" else "Редактирование слота") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    name, { name = it }, label = { Text("Название") },
                    singleLine = true, modifier = Modifier.fillMaxWidth()
                )
                Text("Начало", color = c.sub, fontSize = 13.sp)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    Wheel(24, sh) { sh = it }
                    Text(":", fontSize = 22.sp)
                    Wheel(60, sm) { sm = it }
                }
                Text("Конец", color = c.sub, fontSize = 13.sp)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    Wheel(24, eh) { eh = it }
                    Text(":", fontSize = 22.sp)
                    Wheel(60, em) { em = it }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val s = "%02d:%02d".format(sh, sm)
                var e = "%02d:%02d".format(eh, em)
                if (e < s) e = s
                onSave(init.copy(name = name.trim().ifBlank { "Слот" }, start = s, end = e))
            }) { Text("Сохранить") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } }
    )
}

// ======================= ГЛАВНЫЙ ЭКРАН =======================
@Composable
fun MainScreen(
    lessons: List<Lesson>, today: LocalDate, selected: LocalDate,
    onSelect: (LocalDate) -> Unit, onOpen: (Lesson, LocalDate) -> Unit,
    onNew: () -> Unit, onManualSync: () -> Unit, onMenu: () -> Unit
) {
    val c = C
    val scope = rememberCoroutineScope()
    val anchorMonth = remember { YearMonth.from(today) }
    val pager = rememberPagerState(initialPage = MONTH_BASE) { MONTH_COUNT }
    var frac by remember { mutableFloatStateOf(0f) }          // 0 = свёрнут, 1 = развёрнут
    var searching by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    val selNow by rememberUpdatedState(selected)
    val onSelectNow by rememberUpdatedState(onSelect)
    val jobRef = remember { arrayOfNulls<Job>(1) }

    BackHandler(enabled = searching) { searching = false; query = "" }

    LaunchedEffect(pager) {
        snapshotFlow { pager.settledPage }.collect { p ->
            val ym = anchorMonth.plusMonths((p - MONTH_BASE).toLong())
            val s = selNow
            if (YearMonth.from(s) != ym) {
                onSelectNow(ym.atDay(minOf(s.dayOfMonth, ym.lengthOfMonth())))
            }
        }
    }
    LaunchedEffect(selected) {
        val target = (MONTH_BASE + ChronoUnit.MONTHS.between(anchorMonth, YearMonth.from(selected))).toInt()
        if (target in 0 until MONTH_COUNT && pager.currentPage != target) pager.animateScrollToPage(target)
    }

    fun settle(target: Float) {
        jobRef[0]?.cancel()
        jobRef[0] = scope.launch {
            animate(frac, target, animationSpec = tween(220)) { v, _ -> frac = v }
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(c.bg)) {
        val collapsedCell = 46.dp
        val raw = (maxHeight - 56.dp - 28.dp) / 6
        val expandedCell = if (raw > collapsedCell) raw else collapsedCell
        val cellH = lerp(collapsedCell, expandedCell, frac)
        val rangePx = with(LocalDensity.current) { (expandedCell - collapsedCell).toPx() }.coerceAtLeast(1f)
        val strips by remember { derivedStateOf { frac > 0.5f } }

        val dragState = rememberDraggableState { d ->
            jobRef[0]?.cancel()
            frac = (frac + d / rangePx).coerceIn(0f, 1f)
        }
        val dragMod = Modifier.draggable(
            state = dragState, orientation = Orientation.Vertical,
            onDragStopped = { v ->
                settle(if (v > 600f) 1f else if (v < -600f) 0f else if (frac > 0.5f) 1f else 0f)
            }
        )
        val nested = remember(rangePx) {
            object : NestedScrollConnection {
                private fun shift(dy: Float): Float {
                    val nf = (frac + dy / rangePx).coerceIn(0f, 1f)
                    val used = (nf - frac) * rangePx
                    frac = nf
                    return used
                }
                override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset =
                    if (available.y < 0f && frac > 0f) Offset(0f, shift(available.y)) else Offset.Zero
                override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset =
                    if (available.y > 0f && frac < 1f) Offset(0f, shift(available.y)) else Offset.Zero
                override suspend fun onPreFling(available: Velocity): Velocity {
                    if (frac > 0f && frac < 1f) settle(if (frac > 0.5f) 1f else 0f)
                    return Velocity.Zero
                }
            }
        }

        val dayList = remember(lessons, selected) {
            lessons.filter { it.occursOn(selected) }
                .sortedWith(compareByDescending<Lesson> { it.isAllDay }.thenBy { it.start })
        }
        val results = remember(lessons, query) {
            if (query.isBlank()) emptyList()
            else lessons.filter { it.title.contains(query, true) || it.room.contains(query, true) }
                .sortedBy { it.date }
        }

        Column(Modifier.fillMaxSize()) {
            if (searching) {
                val fr = remember { FocusRequester() }
                LaunchedEffect(Unit) { fr.requestFocus() }
                Row(
                    Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = { searching = false; query = "" }) {
                        Icon(Icons.Filled.ArrowBack, null, tint = c.text)
                    }
                    TextField(
                        value = query, onValueChange = { query = it },
                        placeholder = { Text("Поиск событий") }, singleLine = true,
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = Color.Transparent,
                            unfocusedContainerColor = Color.Transparent,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent
                        ),
                        modifier = Modifier.weight(1f).focusRequester(fr)
                    )
                }
                LazyColumn(
                    Modifier.fillMaxWidth().weight(1f),
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 88.dp)
                ) {
                    if (query.isNotBlank() && results.isEmpty()) {
                        item { Text("Ничего не найдено", color = c.sub, modifier = Modifier.padding(8.dp)) }
                    }
                    items(results, key = { it.id }) { l ->
                        val d = parseDate(l.date)
                        LessonCard(l, d.format(DateTimeFormatter.ofPattern("d MMM yyyy", RU))) {
                            onSelect(d)
                            onOpen(l, d)
                            searching = false; query = ""
                        }
                    }
                }
            } else {
                val shown = anchorMonth.plusMonths((pager.currentPage - MONTH_BASE).toLong())
                val title = shown.month.getDisplayName(TextStyle.FULL_STANDALONE, RU)
                    .replaceFirstChar { it.uppercase() } + " " + shown.year
                Row(
                    Modifier.fillMaxWidth().height(56.dp).padding(start = 4.dp, end = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = onMenu) { Icon(Icons.Filled.Menu, null, tint = c.text) }
                    Text(
                        title, fontSize = 22.sp, fontWeight = FontWeight.Bold,
                        color = c.text, modifier = Modifier.weight(1f).padding(start = 4.dp)
                    )
                    IconButton(onClick = { searching = true }) {
                        Icon(Icons.Filled.Search, null, tint = c.text)
                    }
                    Box(
                        Modifier.padding(start = 4.dp).size(34.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .border(1.5.dp, c.text, RoundedCornerShape(8.dp))
                            .combinedClickable(onClick = { onSelect(today) }, onLongClick = onManualSync),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("${today.dayOfMonth}", color = c.text, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    }
                }
                Row(Modifier.fillMaxWidth().height(28.dp), verticalAlignment = Alignment.CenterVertically) {
                    DAYS.forEachIndexed { i, d ->
                        Text(
                            d, Modifier.weight(1f), textAlign = TextAlign.Center, fontSize = 13.sp,
                            color = when (i) { 5 -> c.sat; 6 -> c.sun; else -> c.sub }
                        )
                    }
                }
                Box(Modifier.fillMaxWidth().height(cellH * 6).then(dragMod).clipToBounds()) {
                    HorizontalPager(state = pager, modifier = Modifier.fillMaxSize()) { page ->
                        MonthGrid(
                            anchorMonth.plusMonths((page - MONTH_BASE).toLong()),
                            lessons, selected, today, cellH, strips, onSelect
                        )
                    }
                }
                Column(Modifier.weight(1f).fillMaxWidth().clipToBounds()) {
                    Row(
                        Modifier.fillMaxWidth().height(48.dp).then(dragMod).padding(start = 16.dp, end = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "${selected.dayOfMonth} ${selected.dayOfWeek.getDisplayName(TextStyle.SHORT, RU)}",
                            fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.text,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(onClick = onNew) { Icon(Icons.Filled.Add, null, tint = c.accent) }
                    }
                    LazyColumn(
                        Modifier.fillMaxWidth().weight(1f).nestedScroll(nested),
                        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 88.dp)
                    ) {
                        if (dayList.isEmpty()) {
                            item { Text("Нет событий", color = c.sub, modifier = Modifier.padding(vertical = 8.dp)) }
                        }
                        items(dayList, key = { it.id }) { l -> LessonCard(l, null) { onOpen(l, selected) } }
                    }
                }
            }
        }

        if (!searching) {
            Box(
                Modifier.align(Alignment.BottomEnd).padding(16.dp).size(56.dp)
                    .shadow(6.dp, CircleShape).clip(CircleShape).background(c.accent)
                    .clickable(onClick = onNew),
                contentAlignment = Alignment.Center
            ) { Icon(Icons.Filled.Add, null, tint = Color.White) }
        }
    }
}

@Composable
fun MonthGrid(
    ym: YearMonth, lessons: List<Lesson>, selected: LocalDate, today: LocalDate,
    cellH: Dp, strips: Boolean, onSelect: (LocalDate) -> Unit
) {
    val offset = ym.atDay(1).dayOfWeek.value - 1
    val len = ym.lengthOfMonth()
    val byDay: Map<Int, List<Lesson>> = remember(lessons, ym) {
        val m = HashMap<Int, List<Lesson>>()
        for (n in 1..len) {
            val d = ym.atDay(n)
            val l = lessons.filter { it.occursOn(d) }
            if (l.isNotEmpty()) m[n] = l.sortedBy { it.start }
        }
        m
    }
    val selDay = if (YearMonth.from(selected) == ym) selected.dayOfMonth else -1
    val todayDay = if (YearMonth.from(today) == ym) today.dayOfMonth else -1

    LazyVerticalGrid(
        columns = GridCells.Fixed(7),
        modifier = Modifier.fillMaxSize(),
        userScrollEnabled = false
    ) {
        items(42) { i ->
            val n = i - offset + 1
            if (n in 1..len) {
                DayCell(n, i % 7, byDay[n], n == selDay, n == todayDay, cellH, strips) { onSelect(ym.atDay(n)) }
            } else {
                Spacer(Modifier.height(cellH))
            }
        }
    }
}

@Composable
fun DayCell(
    n: Int, col: Int, list: List<Lesson>?, sel: Boolean, isToday: Boolean,
    cellH: Dp, strips: Boolean, onClick: () -> Unit
) {
    val c = C
    val numColor = when {
        isToday -> Color.White
        col == 5 -> c.sat
        col == 6 -> c.sun
        else -> c.text
    }
    Column(
        Modifier.fillMaxWidth().height(cellH).clickable(onClick = onClick)
            .padding(horizontal = 1.dp, vertical = 3.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            Modifier.size(26.dp).clip(CircleShape).background(
                when {
                    isToday -> c.accent
                    sel -> c.accent.copy(alpha = 0.18f)
                    else -> Color.Transparent
                }
            ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                "$n", fontSize = 14.sp, color = numColor,
                fontWeight = if (isToday || sel) FontWeight.Bold else FontWeight.Normal
            )
        }
        if (list != null) {
            if (strips) {
                val max = ((cellH.value - 36f) / 16f).toInt().coerceIn(0, 4)
                Spacer(Modifier.height(2.dp))
                list.take(max).forEach { l ->
                    val bg = parseColor(l.color)
                    Box(
                        Modifier.fillMaxWidth().padding(vertical = 1.dp).height(14.dp)
                            .clip(RoundedCornerShape(3.dp)).background(bg)
                            .padding(horizontal = 3.dp),
                        contentAlignment = Alignment.CenterStart
                    ) {
                        Text(l.title, fontSize = 9.sp, color = onColor(bg), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            } else {
                Spacer(Modifier.height(3.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    list.take(3).forEach { l ->
                        Box(Modifier.size(4.dp).clip(CircleShape).background(parseColor(l.color)))
                    }
                }
            }
        }
    }
}

@Composable
fun LessonCard(l: Lesson, dateLabel: String?, onClick: () -> Unit) {
    val c = C
    val col = parseColor(l.color)
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp).clip(RoundedCornerShape(12.dp))
            .background(c.card).clickable(onClick = onClick).height(IntrinsicSize.Min),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(5.dp).fillMaxHeight().background(col))
        Column(Modifier.weight(1f).padding(12.dp)) {
            Text(
                (if (l.emoji.isNotBlank()) l.emoji + " " else "") + l.title,
                fontSize = 16.sp, fontWeight = FontWeight.Medium, color = c.text
            )
            Text(
                if (dateLabel != null) "$dateLabel · ${l.timeLabel()}" else l.timeLabel(),
                fontSize = 13.sp, color = c.sub
            )
            if (l.room.isNotBlank()) Text(l.room, fontSize = 12.sp, color = c.sub)
        }
        if (l.recurrence != "NONE") {
            Icon(Icons.Filled.Repeat, null, tint = c.sub, modifier = Modifier.padding(end = 12.dp).size(18.dp))
        }
    }
}

// ======================= ПАЛИТРА =======================
@Composable
fun ColorPicker(current: String, onPick: (String) -> Unit) {
    val c = C
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf("Яркие" to PALETTE_BRIGHT, "Пастельные" to PALETTE_PASTEL, "Тёмные" to PALETTE_DARK)
            .forEach { (label, list) ->
                Text(label, fontSize = 12.sp, color = c.sub)
                list.chunked(8).forEach { row ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        row.forEach { hex ->
                            val col = parseColor(hex)
                            Box(
                                Modifier.size(32.dp).clip(CircleShape).background(col)
                                    .border(1.dp, c.sub.copy(alpha = 0.3f), CircleShape)
                                    .clickable { onPick(hex) },
                                contentAlignment = Alignment.Center
                            ) {
                                if (hex.equals(current, true)) {
                                    Icon(Icons.Filled.Check, null, tint = onColor(col), modifier = Modifier.size(18.dp))
                                }
                            }
                        }
                    }
                }
            }
    }
}

// ======================= СОЗДАНИЕ / РЕДАКТИРОВАНИЕ =======================
@Composable
fun EditScreen(
    init: Lesson, initDate: LocalDate, all: List<Lesson>, slots: List<TimeSlot>,
    onSave: (Lesson) -> Unit, onDelete: () -> Unit, onCancel: () -> Unit
) {
    val c = C
    var title by remember { mutableStateOf(init.title) }
    var typed by remember { mutableStateOf(false) }
    var emoji by remember { mutableStateOf(init.emoji) }
    var color by remember { mutableStateOf(init.color) }
    var allDay by remember { mutableStateOf(init.isAllDay) }
    var date by remember { mutableStateOf(initDate) }
    var sh by remember { mutableStateOf(init.start.substringBefore(":").toIntOrNull() ?: 8) }
    var sm by remember { mutableStateOf(init.start.substringAfter(":").toIntOrNull() ?: 30) }
    var eh by remember { mutableStateOf(init.end.substringBefore(":").toIntOrNull() ?: 9) }
    var em by remember { mutableStateOf(init.end.substringAfter(":").toIntOrNull() ?: 15) }
    var timeVer by remember { mutableStateOf(0) }
    var room by remember { mutableStateOf(init.room) }
    var recurrence by remember { mutableStateOf(init.recurrence) }
    var showEmoji by remember { mutableStateOf(false) }
    var showColors by remember { mutableStateOf(false) }
    var showDate by remember { mutableStateOf(false) }
    var showTime by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }

    val suggestions = remember(title, all, typed) {
        if (!typed || title.isBlank()) emptyList()
        else all.filter { it.id != init.id && it.title.contains(title.trim(), true) }
            .distinctBy { listOf(it.title.lowercase(), it.recurrence, it.room, it.color) }
            .take(4)
    }

    val save = {
        val s = "%02d:%02d".format(sh, sm)
        var e = "%02d:%02d".format(eh, em)
        if (e < s) e = s
        onSave(
            init.copy(
                title = title.trim().ifBlank { "Событие" }, emoji = emoji, color = color,
                isAllDay = allDay, date = date.toString(), start = s, end = e,
                room = room.trim(), recurrence = recurrence
            )
        )
    }

    Column(Modifier.fillMaxSize().background(c.bg).pointerInput(Unit) {}) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(
                if (init.id == 0L) "Новое событие" else "Событие",
                fontSize = 22.sp, fontWeight = FontWeight.Bold, color = c.text,
                modifier = Modifier.padding(top = 8.dp)
            )

            // название + эмодзи + цвет
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    title, { title = it; typed = true }, label = { Text("Название") },
                    singleLine = true, modifier = Modifier.weight(1f)
                )
                Box(
                    Modifier.size(40.dp).clip(CircleShape).background(c.card)
                        .clickable { showEmoji = !showEmoji; showColors = false },
                    contentAlignment = Alignment.Center
                ) {
                    if (emoji.isBlank()) Icon(Icons.Filled.EmojiEmotions, null, tint = c.sub)
                    else Text(emoji, fontSize = 22.sp)
                }
                Box(
                    Modifier.size(32.dp).clip(CircleShape).background(parseColor(color))
                        .border(1.dp, c.sub.copy(alpha = 0.3f), CircleShape)
                        .clickable { showColors = !showColors; showEmoji = false }
                )
            }

            // умные подсказки
            if (suggestions.isNotEmpty()) {
                Text("Похожие события", fontSize = 12.sp, color = c.sub)
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.card)) {
                    suggestions.forEach { s ->
                        val sub = listOf(
                            s.room,
                            if (s.recurrence != "NONE") recurrenceLabel(s.recurrence) else ""
                        ).filter { it.isNotBlank() }.joinToString(" · ")
                        Row(
                            Modifier.fillMaxWidth().clickable {
                                title = s.title
                                recurrence = s.recurrence
                                room = s.room
                                color = s.color
                                typed = false
                            }.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Box(Modifier.size(10.dp).clip(CircleShape).background(parseColor(s.color)))
                            Column(Modifier.padding(start = 10.dp)) {
                                Text(s.title, fontSize = 15.sp, color = c.text)
                                if (sub.isNotEmpty()) Text(sub, fontSize = 12.sp, color = c.sub)
                            }
                        }
                    }
                }
            }

            if (showEmoji) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    EMOJIS.chunked(8).forEach { chunk ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            chunk.forEach { e ->
                                Text(
                                    e, fontSize = 24.sp,
                                    modifier = Modifier.clip(RoundedCornerShape(8.dp))
                                        .clickable { emoji = e; showEmoji = false }.padding(4.dp)
                                )
                            }
                        }
                    }
                    TextButton(onClick = { emoji = ""; showEmoji = false }) { Text("Убрать эмодзи") }
                }
            }
            if (showColors) {
                ColorPicker(color) { color = it }
            }

            // весь день
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.AccessTime, null, tint = c.sub)
                Text("Весь день", fontSize = 16.sp, color = c.text, modifier = Modifier.weight(1f).padding(start = 12.dp))
                Switch(checked = allDay, onCheckedChange = { allDay = it })
            }

            // дата
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { showDate = true }.padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Filled.CalendarToday, null, tint = c.sub)
                Text(
                    date.format(DateTimeFormatter.ofPattern("EEEE, d MMMM yyyy", RU)),
                    fontSize = 16.sp, color = c.text, modifier = Modifier.padding(start = 12.dp)
                )
            }

            // слоты и время
            if (!allDay) {
                if (slots.isNotEmpty()) {
                    Text("Слоты времени", fontSize = 12.sp, color = c.sub)
                    Row(
                        Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        slots.forEach { s ->
                            val (h1, m1) = hmOf(s.start)
                            val (h2, m2) = hmOf(s.end)
                            val active = sh == h1 && sm == m1 && eh == h2 && em == m2
                            Box(
                                Modifier.clip(RoundedCornerShape(16.dp))
                                    .background(if (active) c.accent.copy(alpha = 0.18f) else c.card)
                                    .border(1.dp, if (active) c.accent else Color.Transparent, RoundedCornerShape(16.dp))
                                    .clickable {
                                        sh = h1; sm = m1; eh = h2; em = m2
                                        timeVer += 1
                                    }
                                    .padding(horizontal = 12.dp, vertical = 8.dp)
                            ) {
                                Text("${s.name}  ${s.start}–${s.end}", fontSize = 13.sp, color = c.text)
                            }
                        }
                    }
                }
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { showTime = !showTime }.padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Filled.Schedule, null, tint = c.sub)
                    Text(
                        "%02d:%02d – %02d:%02d".format(sh, sm, eh, em),
                        fontSize = 16.sp, color = c.accent, modifier = Modifier.padding(start = 12.dp)
                    )
                }
                if (showTime) {
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("Начало", color = c.sub, fontSize = 13.sp)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Wheel(24, sh, timeVer) { sh = it }
                                Text(":", fontSize = 22.sp, color = c.text)
                                Wheel(60, sm, timeVer) { sm = it }
                            }
                        }
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("Конец", color = c.sub, fontSize = 13.sp)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Wheel(24, eh, timeVer) { eh = it }
                                Text(":", fontSize = 22.sp, color = c.text)
                                Wheel(60, em, timeVer) { em = it }
                            }
                        }
                    }
                }
            }

            // место
            OutlinedTextField(
                room, { room = it }, label = { Text("Место") },
                leadingIcon = { Icon(Icons.Filled.LocationOn, null) },
                singleLine = true, modifier = Modifier.fillMaxWidth()
            )

            // повторение
            Box {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.card)
                        .clickable { menu = true }.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Filled.Repeat, null, tint = c.sub)
                    Text("Повторение", fontSize = 16.sp, color = c.text, modifier = Modifier.weight(1f).padding(start = 12.dp))
                    Text(recurrenceLabel(recurrence), color = c.accent, fontSize = 15.sp)
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    RECURRENCES.forEach { (k, v) ->
                        DropdownMenuItem(text = { Text(v) }, onClick = { recurrence = k; menu = false })
                    }
                }
            }

            if (init.id != 0L) {
                TextButton(onClick = onDelete) { Text("Удалить событие", color = Color(0xFFE53935)) }
            }
        }

        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            TextButton(onClick = onCancel) { Text("Отмена", fontSize = 16.sp) }
            TextButton(onClick = { save() }) { Text("Сохранить", fontSize = 16.sp, fontWeight = FontWeight.Bold) }
        }
    }

    if (showDate) {
        val st = rememberDatePickerState(initialSelectedDateMillis = date.toEpochDay() * 86_400_000L)
        val base = LocalContext.current
        val ruCtx = remember(base) {
            base.createConfigurationContext(
                Configuration(base.resources.configuration).apply { setLocale(RU) }
            )
        }
        CompositionLocalProvider(
            LocalContext provides ruCtx,
            LocalConfiguration provides ruCtx.resources.configuration
        ) {
            DatePickerDialog(
                onDismissRequest = { showDate = false },
                confirmButton = {
                    TextButton(onClick = {
                        st.selectedDateMillis?.let { date = LocalDate.ofEpochDay(Math.floorDiv(it, 86_400_000L)) }
                        showDate = false
                    }) { Text("OK") }
                },
                dismissButton = { TextButton(onClick = { showDate = false }) { Text("Отмена") } }
            ) { DatePicker(state = st) }
        }
    }
}

@Composable
fun Wheel(count: Int, value: Int, version: Int = 0, onChange: (Int) -> Unit) {
    val c = C
    val itemH = 40.dp
    val itemPx = with(LocalDensity.current) { itemH.toPx() }
    val state = rememberLazyListState(initialFirstVisibleItemIndex = value.coerceIn(0, count - 1))
    val fling = rememberSnapFlingBehavior(state)
    val cb by rememberUpdatedState(onChange)
    val sel by remember {
        derivedStateOf {
            (state.firstVisibleItemIndex + if (state.firstVisibleItemScrollOffset > itemPx / 2) 1 else 0)
                .coerceIn(0, count - 1)
        }
    }
    LaunchedEffect(Unit) { snapshotFlow { sel }.collect { cb(it) } }
    // внешнее изменение значения (выбор слота времени)
    LaunchedEffect(version) {
        if (version > 0) state.scrollToItem(value.coerceIn(0, count - 1))
    }

    Box(Modifier.width(56.dp).height(itemH * 3), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxWidth().height(itemH).clip(RoundedCornerShape(10.dp)).background(c.card))
        LazyColumn(
            state = state,
            flingBehavior = fling,
            contentPadding = PaddingValues(vertical = itemH),
            modifier = Modifier.fillMaxSize()
        ) {
            items(count) { i ->
                Box(Modifier.fillMaxWidth().height(itemH), contentAlignment = Alignment.Center) {
                    Text(
                        "%02d".format(i), fontSize = 22.sp,
                        color = if (i == sel) c.text else c.sub
                    )
                }
            }
        }
    }
}
KT_EOF

# ======================= WEAR: MainActivity.kt =======================
cat << 'KT_EOF' > "$WDIR/MainActivity.kt"
@file:OptIn(ExperimentalFoundationApi::class)

package PKG__

import android.graphics.Paint
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

private const val RANGE = 30
private val RU: Locale = Locale("ru")

private fun curMin(): Int {
    val t = LocalTime.now()
    return t.hour * 60 + t.minute
}

private fun toMin(s: String): Int {
    val h = s.substringBefore(":").toIntOrNull() ?: 0
    val m = s.substringAfter(":").toIntOrNull() ?: 0
    return h * 60 + m
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ScheduleRepository.init(this)
        setContent { WearApp() }
    }
}

@Composable
fun WearApp() {
    val lessons by ScheduleRepository.lessons.collectAsState()
    var detail by remember { mutableStateOf<Lesson?>(null) }
    var drawer by remember { mutableStateOf(false) }
    var nowMin by remember { mutableStateOf(curMin()) }
    val today = remember { LocalDate.now() }
    val pager = rememberPagerState(initialPage = RANGE) { RANGE * 2 + 1 }   // ±30 дней
    val scope = rememberCoroutineScope()

    // обновление шкалы времени раз в минуту
    LaunchedEffect(Unit) {
        while (true) {
            delay(60_000L)
            nowMin = curMin()
        }
    }

    BackHandler(enabled = detail != null || drawer) {
        if (drawer) drawer = false else detail = null
    }

    MaterialTheme {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            val d = detail
            if (d == null) {
                HorizontalPager(state = pager) { page ->
                    val date = today.plusDays((page - RANGE).toLong())
                    DayPage(
                        date, lessons, isToday = date == today, nowMin = nowMin,
                        onOpen = { detail = it }, onTitle = { drawer = true }
                    )
                }
                // левый край: свайп слева направо открывает панель выбора даты
                Box(
                    Modifier.align(Alignment.CenterStart).fillMaxHeight().width(24.dp)
                        .pointerInput(Unit) {
                            var total = 0f
                            detectHorizontalDragGestures(
                                onDragStart = { total = 0f },
                                onDragEnd = { if (total > 40f) drawer = true },
                                onDragCancel = { total = 0f },
                                onHorizontalDrag = { _, dx -> total += dx }
                            )
                        }
                )
            } else {
                DetailScreen(d) { detail = null }
            }
            if (drawer && d == null) {
                DatesDrawer(today, pager.currentPage - RANGE) { i ->
                    drawer = false
                    scope.launch { pager.animateScrollToPage(RANGE + i) }
                }
            }
        }
    }
}

@Composable
fun DatesDrawer(today: LocalDate, current: Int, onPick: (Int) -> Unit) {
    val fmt = remember { DateTimeFormatter.ofPattern("EEE, d MMM", RU) }
    Box(
        Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.96f)).pointerInput(Unit) {}
    ) {
        ScalingLazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = 36.dp, bottom = 36.dp, start = 16.dp, end = 16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            item {
                Text(
                    "Выбор даты", color = Pal.Dim, fontSize = 13.sp,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
                )
            }
            items((0..6).toList()) { i ->
                val d = today.plusDays(i.toLong())
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                        .background(if (i == current) Pal.Purple else Pal.Card)
                        .clickable { onPick(i) }
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        d.format(fmt), color = Pal.Text, fontSize = 15.sp,
                        fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)
                    )
                    if (i == 0) Text("сегодня", color = Pal.Dim, fontSize = 11.sp)
                }
            }
        }
    }
}

@Composable
fun TimeScale(lessons: List<Lesson>, isToday: Boolean, nowMin: Int, modifier: Modifier) {
    val hourPaint = remember {
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.parseColor("#9B98AD")
            textAlign = Paint.Align.RIGHT
        }
    }
    val timePaint = remember {
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.RED
            textAlign = Paint.Align.RIGHT
            isFakeBoldText = true
        }
    }
    Canvas(modifier) {
        val startMin = 8 * 60
        val endMin = 18 * 60
        val total = (endMin - startMin).toFloat()
        val h = size.height
        fun y(min: Int): Float = (min - startMin) / total * h

        hourPaint.textSize = 9.sp.toPx()
        timePaint.textSize = 9.sp.toPx()
        val axisX = 17.dp.toPx()
        val axisColor = Color(0xFF3A3A44)

        drawLine(axisColor, Offset(axisX, 0f), Offset(axisX, h), strokeWidth = 1.dp.toPx())
        for (hr in 8..18 step 2) {
            val yy = y(hr * 60)
            drawLine(axisColor, Offset(axisX - 3.dp.toPx(), yy), Offset(axisX + 3.dp.toPx(), yy), strokeWidth = 1.dp.toPx())
            drawContext.canvas.nativeCanvas.drawText("%02d".format(hr), axisX - 5.dp.toPx(), yy + 3.dp.toPx(), hourPaint)
        }

        lessons.forEach { l ->
            if (l.isAllDay) return@forEach
            val s = toMin(l.start)
            val e = toMin(l.end)
            val cs = maxOf(s, startMin)
            val ce = minOf(e, endMin)
            if (ce <= cs) return@forEach
            val current = isToday && nowMin >= s && nowMin < e
            val col = if (current) Color(0xFF8A8A8A) else parseColor(l.color)
            val top = y(cs)
            val hh = (y(ce) - top).coerceAtLeast(2.dp.toPx())
            drawRoundRect(
                color = col,
                topLeft = Offset(axisX + 3.dp.toPx(), top),
                size = Size(10.dp.toPx(), hh),
                cornerRadius = CornerRadius(3.dp.toPx())
            )
        }

        if (isToday && nowMin in startMin..endMin) {
            val yy = y(nowMin)
            val tagW = 24.dp.toPx()
            drawRect(Color.Black, Offset(0f, yy - 6.dp.toPx()), Size(tagW, 12.dp.toPx()))
            drawContext.canvas.nativeCanvas.drawText(
                "%02d:%02d".format(nowMin / 60, nowMin % 60),
                tagW, yy + 3.dp.toPx(), timePaint
            )
            drawLine(Color.Red, Offset(tagW, yy), Offset(size.width, yy), strokeWidth = 1.5.dp.toPx())
        }
    }
}

@Composable
fun DayPage(
    date: LocalDate, all: List<Lesson>, isToday: Boolean, nowMin: Int,
    onOpen: (Lesson) -> Unit, onTitle: () -> Unit
) {
    val day = remember(all, date) {
        all.filter { it.occursOn(date) }
            .sortedWith(compareByDescending<Lesson> { it.isAllDay }.thenBy { it.start })
    }
    val title = date.format(DateTimeFormatter.ofPattern("EEE, d MMM", RU))
    Box(Modifier.fillMaxSize()) {
        if (day.isEmpty()) {
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Filled.EventAvailable, null, tint = Pal.Lilac, modifier = Modifier.size(44.dp))
                Spacer(Modifier.height(8.dp))
                Text("Занятий нет", color = Pal.Text, fontSize = 16.sp, textAlign = TextAlign.Center)
            }
        } else {
            ScalingLazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(top = 56.dp, bottom = 36.dp, start = 68.dp, end = 12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) { items(day) { WearCard(it) { onOpen(it) } } }
        }
        TimeScale(
            lessons = day, isToday = isToday, nowMin = nowMin,
            modifier = Modifier.align(Alignment.CenterStart).padding(start = 24.dp)
                .width(40.dp).fillMaxHeight(0.56f)
        )
        Text(
            "‹   $title   ›", color = Pal.Text, fontSize = 14.sp, fontWeight = FontWeight.Medium,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 20.dp).clickable(onClick = onTitle)
        )
    }
}

@Composable
fun WearCard(l: Lesson, onClick: () -> Unit) {
    val col = parseColor(l.color)
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Pal.Card)
            .clickable(onClick = onClick).padding(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(4.dp).height(32.dp).clip(RoundedCornerShape(2.dp)).background(col))
        Column(Modifier.weight(1f).padding(start = 6.dp)) {
            Text(l.timeLabel(), color = Pal.Dim, fontSize = 11.sp, maxLines = 1)
            Text(l.title, color = Pal.Text, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        }
        Box(
            Modifier.size(26.dp).clip(RoundedCornerShape(8.dp)).background(col.copy(alpha = 0.3f)),
            contentAlignment = Alignment.Center
        ) {
            if (l.emoji.isNotBlank()) Text(l.emoji, fontSize = 14.sp)
            else Icon(iconFor(l.icon), null, tint = col, modifier = Modifier.size(16.dp))
        }
    }
}

@Composable
fun DetailScreen(l: Lesson, onBack: () -> Unit) {
    val col = parseColor(l.color)
    Column(
        Modifier.fillMaxSize().padding(horizontal = 26.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(col),
            contentAlignment = Alignment.Center
        ) {
            if (l.emoji.isNotBlank()) Text(l.emoji, fontSize = 24.sp)
            else Icon(iconFor(l.icon), null, tint = Color.White, modifier = Modifier.size(28.dp))
        }
        Spacer(Modifier.height(4.dp))
        Text(
            l.title, color = Pal.Text, fontSize = 20.sp, fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center, maxLines = 2
        )
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Schedule, null, tint = Pal.Dim, modifier = Modifier.size(16.dp))
            Text("  ${l.timeLabel()}", color = Pal.Text, fontSize = 14.sp)
        }
        if (l.room.isNotBlank()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.LocationOn, null, tint = Pal.Dim, modifier = Modifier.size(16.dp))
                Text("  ${l.room}", color = Pal.Text, fontSize = 14.sp, maxLines = 1)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Repeat, null, tint = col, modifier = Modifier.size(16.dp))
            Text("  ${recurrenceStatus(l.recurrence)}", color = col, fontSize = 14.sp)
        }
        Spacer(Modifier.height(8.dp))
        Box(
            Modifier.clip(RoundedCornerShape(20.dp)).background(Pal.Card).clickable(onClick = onBack)
                .padding(horizontal = 28.dp, vertical = 6.dp)
        ) {
            Text("Назад", color = Pal.Text, fontSize = 13.sp)
        }
    }
}
KT_EOF

# ======================= ЗАМЕНА PKG__ =======================
for f in ScheduleRepository.kt MainActivity.kt; do
  sed -i "s/PKG__/${APKG}/g" "$ADIR/$f"
done
sed -i "s/PKG__/${WPKG}/g" "$WDIR/MainActivity.kt"

echo 'Файлы обновлены!'
echo 'Дальше: git add . && git commit -m "Burger menu, slots, backup, watch timeline" && git push'
