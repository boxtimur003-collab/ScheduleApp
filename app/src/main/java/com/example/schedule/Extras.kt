package com.example.schedule

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
    var choosing by remember { mutableStateOf<SentFile?>(null) }
    var viewing by remember { mutableStateOf<SentFile?>(null) }
    var editing by remember { mutableStateOf<SentFile?>(null) }
    BackHandler {
        if (editing != null) {
            editing = null
        } else if (viewing != null) {
            viewing = null
        } else {
            onClose()
        }
    }

    fun toast(r: Int) {
        val msg = when {
            r > 0 -> "Отправлено на часы"
            r == -2 -> "Текст слишком большой"
            else -> "Сохранено на телефоне, часы не найдены"
        }
        Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show()
    }

    val ed = editing
    val vw = viewing
    Column(Modifier.fillMaxSize().background(c.bg).pointerInput(Unit) {}) {
        if (ed == null && vw == null) {
            // ---------- список ----------
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
                            .background(c.card).clickable { choosing = f }.padding(start = 14.dp),
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
        } else if (vw != null) {
            // ---------- просмотр (формулы отрисованы) ----------
            Row(
                Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = { viewing = null }) { Icon(Icons.Filled.ArrowBack, null, tint = c.text) }
                Text(
                    vw.name, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.text,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = { editing = vw; viewing = null }) {
                    Icon(Icons.Filled.Edit, null, tint = c.accent)
                }
            }
            Column(
                Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp)
            ) {
                MxFormulaText(vw.text, 20f, c.text, Modifier.fillMaxWidth())
                Spacer(Modifier.height(32.dp))
            }
        } else if (ed != null) {
            // ---------- редактирование (обычный текст) ----------
            var text by remember(ed.id) { mutableStateOf(ed.text) }
            Row(
                Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = { editing = null }) { Icon(Icons.Filled.Close, null, tint = c.text) }
                Text(
                    ed.name, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.text,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = {
                    SentStore.delete(ctx, ed.id)
                    files = SentStore.load(ctx)
                    editing = null
                    scope.launch { DataSyncService.sendFileDelete(ctx, ed.id) }
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
                        val saved = SentStore.upsert(ctx, ed.id, ed.name, text, time)
                        files = SentStore.load(ctx)
                        editing = null
                        scope.launch { toast(DataSyncService.sendFile(ctx, SentStore.toJson(saved))) }
                    }
                }) { Text("Сохранить и отправить", fontSize = 16.sp, fontWeight = FontWeight.Bold) }
            }
        }
    }

    choosing?.let { f ->
        AlertDialog(
            onDismissRequest = { choosing = null },
            title = { Text(f.name) },
            text = {
                Text(
                    f.text.lineSequence().firstOrNull().orEmpty(),
                    maxLines = 2, overflow = TextOverflow.Ellipsis
                )
            },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    TextButton(onClick = { viewing = f; choosing = null }) { Text("Смотреть") }
                    TextButton(onClick = { editing = f; choosing = null }) { Text("Редактировать") }
                    TextButton(onClick = { choosing = null }) { Text("Отмена") }
                }
            }
        )
    }
}
