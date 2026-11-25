#!/data/data/com.termux/files/usr/bin/bash
# Что делает скрипт:
#  1. Генерирует release.keystore (alias/пароли: android), кодирует в Base64 и выводит на экран.
#     Существующий keystore НЕ перезаписывается. Файл в .gitignore, в репозиторий его не коммитить.
#  2. app/ и wear/ build.gradle.kts: signingConfigs.release (из local.properties или переменных
#     окружения), buildTypes.release, buildConfig=true, versionCode/versionName из VERSION_CODE/VERSION_NAME.
#  3. Телефон: UpdateChecker.kt (проверка version.json, уведомление, загрузка через DownloadManager,
#     установка через FileProvider + ACTION_VIEW), отправка на часы по пути /update.
#     Часы: UpdateNotifier.kt, обработка /update в DataSyncService.
#  4. .github/workflows/build.yml: assembleRelease, подпись из secrets, GitHub Release, обновление version.json.
#  5. version.json (шаблон) и инструкция по секретам.
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

# ---------- репозиторий GitHub (owner/repo): из переменной GH_REPO или из git remote ----------
if [ -z "$GH_REPO" ]; then
  REMOTE=$(git remote get-url origin 2>/dev/null || true)
  GH_REPO=$(echo "$REMOTE" | sed -n 's#.*github\.com[:/]\([^/]*/[^/]*\)$#\1#p' | sed 's/\.git$//')
fi
if [ -z "$GH_REPO" ]; then
  GH_REPO='ТВОЙ_НИК/ТВОЙ_РЕПО'
  echo '!! git remote не найден. Запусти: GH_REPO=ник/репо bash этот_скрипт.sh  (или поправь URL в UpdateChecker.kt и version.json)'
fi
echo "GH_REPO=$GH_REPO"

# ======================= 1. KEYSTORE =======================
echo '=== 1. Keystore ==='
if ! command -v keytool >/dev/null 2>&1; then
  echo 'keytool не найден, устанавливаю openjdk-17...'
  pkg install -y openjdk-17 >/dev/null 2>&1 || true
fi
if command -v keytool >/dev/null 2>&1; then
  if [ -f release.keystore ]; then
    echo 'release.keystore уже существует, не перезаписываю'
  else
    keytool -genkeypair -keystore release.keystore -storetype PKCS12 \
      -alias android -keyalg RSA -keysize 2048 -validity 10000 \
      -storepass android -keypass android \
      -dname 'CN=Schedule, OU=App, O=Schedule, C=RU' || echo '!! keytool завершился с ошибкой'
  fi
  if [ -f release.keystore ]; then
    base64 -w 0 release.keystore > keystore.base64.txt
    echo
    echo '----- KEYSTORE_BASE64 (скопируй целиком в GitHub Secret) -----'
    cat keystore.base64.txt
    echo
    echo '----- конец (тот же текст сохранён в keystore.base64.txt) -----'
    command -v termux-clipboard-set >/dev/null 2>&1 && termux-clipboard-set < keystore.base64.txt && echo 'Base64 скопирован в буфер обмена'
  fi
else
  echo '!! keytool недоступен: выполни  pkg install openjdk-17  и запусти скрипт снова'
fi

# ======================= .gitignore =======================
touch .gitignore
[ -n "$(tail -c1 .gitignore)" ] && echo >> .gitignore
for p in release.keystore '*.keystore' keystore.base64.txt .sign_block.tmp; do
  grep -qxF "$p" .gitignore || echo "$p" >> .gitignore
done

# ======================= 2. build.gradle.kts (оба модуля) =======================
SIGN_BLOCK="$PWD/.sign_block.tmp"
cat << 'KT_EOF' > "$SIGN_BLOCK"
    signingConfigs {
        create("release") {
            val props = java.util.Properties()
            val lp = rootProject.file("local.properties")
            if (lp.exists()) lp.inputStream().use { props.load(it) }
            fun pick(key: String, def: String): String = props.getProperty(key) ?: System.getenv(key) ?: def
            storeFile = rootProject.file(pick("KEYSTORE_FILE", "release.keystore"))
            storePassword = pick("KEYSTORE_PASSWORD", "android")
            keyAlias = pick("KEY_ALIAS", "android")
            keyPassword = pick("KEY_PASSWORD", "android")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
        }
    }
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
KT_EOF

patch_gradle() {
  f="$1"
  if [ ! -f "$f" ]; then echo "!! не найден $f"; return; fi
  if ! grep -q 'signingConfigs' "$f"; then
    sed -i "/^android {\$/r ${SIGN_BLOCK}" "$f"
  fi
  sed -i 's/buildFeatures { compose = true }/buildFeatures { compose = true; buildConfig = true }/' "$f"
  sed -i 's/^\([[:space:]]*\)versionCode = 1[[:space:]]*$/\1versionCode = (System.getenv("VERSION_CODE") ?: "1").toInt()/' "$f"
  sed -i 's/^\([[:space:]]*\)versionName = "1.0"[[:space:]]*$/\1versionName = System.getenv("VERSION_NAME") ?: "1.0"/' "$f"
}
patch_gradle app/build.gradle.kts
patch_gradle wear/build.gradle.kts
rm -f "$SIGN_BLOCK"

# ======================= Манифест телефона: права, FileProvider, ресивер =======================
add_perm() {
  grep -q "android.permission.$2\"" "$1" || sed -i "/<application/i <uses-permission android:name=\"android.permission.$2\" />" "$1"
}
add_perm "$AMAN" INTERNET
add_perm "$AMAN" POST_NOTIFICATIONS
add_perm "$AMAN" REQUEST_INSTALL_PACKAGES
grep -q 'UpdateActionReceiver' "$AMAN" || sed -i '/<\/application>/i <receiver android:name=".UpdateActionReceiver" android:exported="false" />' "$AMAN"
grep -q 'FileProvider' "$AMAN" || sed -i '/<\/application>/i <provider android:name="androidx.core.content.FileProvider" android:authorities="${applicationId}.fileprovider" android:exported="false" android:grantUriPermissions="true"><meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/file_paths" /></provider>' "$AMAN"

# Манифест часов: слушатель принимает любой путь (в том числе /update)
sed -i 's|android:path="/schedule"|android:pathPrefix="/"|' "$WMAN"

# ======================= Ресурсы =======================
mkdir -p "$ARES/xml" "$ARES/drawable" "$WRES/drawable"
cat << 'KT_EOF' > "$ARES/xml/file_paths.xml"
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <external-files-path name="downloads" path="Download/" />
</paths>
KT_EOF

for R in "$ARES" "$WRES"; do
  if [ ! -f "$R/drawable/ic_notif.xml" ]; then
cat << 'KT_EOF' > "$R/drawable/ic_notif.xml"
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF" android:pathData="M12,22c1.1,0 2,-0.9 2,-2h-4c0,1.1 0.89,2 2,2zM18,16v-5c0,-3.07 -1.64,-5.64 -4.5,-6.32V4c0,-0.83 -0.67,-1.5 -1.5,-1.5s-1.5,0.67 -1.5,1.5v0.68C7.64,5.36 6,7.92 6,11v5l-2,2v1h16v-1l-2,-2z" />
</vector>
KT_EOF
  fi
done

# ======================= 3. ТЕЛЕФОН: UpdateChecker.kt =======================
cat << 'KT_EOF' > "$ADIR/UpdateChecker.kt"
package PKG__

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
    private const val REPO = "GH_REPO__"
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
KT_EOF

# ======================= ТЕЛЕФОН: DataSyncService.kt (путь /update) =======================
DS="$ADIR/DataSyncService.kt"
if ! grep -q 'sendUpdate' "$DS"; then
  sed -i '/^    private suspend fun sendTo(ctx: Context, path: String, payload: String): Int = try {$/i\
    const val UPDATE_PATH = "/update"\
\
    /** Информация об обновлении для часов: {"versionCode": N, "versionName": "..."}. */\
    suspend fun sendUpdate(ctx: Context, json: String): Int = sendTo(ctx, UPDATE_PATH, json)\
' "$DS"
fi

# ======================= ТЕЛЕФОН: проверка обновлений при запуске =======================
if ! grep -q 'UpdateEffect()' "$AOS"; then
  sed -i '/^    val drawerState = rememberDrawerState(DrawerValue.Closed)$/a\
    UpdateEffect()' "$AOS"
fi

# ======================= ЧАСЫ: UpdateNotifier.kt =======================
cat << 'KT_EOF' > "$WDIR/UpdateNotifier.kt"
package PKG__

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
KT_EOF

# ======================= ЧАСЫ: DataSyncService.kt (путь /update) =======================
WDS="$WDIR/DataSyncService.kt"
if ! grep -q '"/update"' "$WDS"; then
  sed -i '/"\/file_delete" -> /a\
                "/update" -> UpdateNotifier.show(applicationContext, body)' "$WDS"
fi

# ======================= 4. GitHub Actions workflow =======================
mkdir -p .github/workflows
cat << 'KT_EOF' > .github/workflows/build.yml
name: Build APK

on:
  push:
    branches: [ main ]
    paths-ignore:
      - 'version.json'
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      VERSION_CODE: ${{ github.run_number }}
      VERSION_NAME: "1.${{ github.run_number }}"
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Java 17 (Temurin)
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Gradle (с кэшем)
        uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: '8.9'

      - name: Подготовка (убрать пути Termux)
        run: |
          sed -i '/aapt2FromMavenOverride/d' gradle.properties
          rm -f local.properties

      - name: Android SDK (лицензии и платформа)
        run: |
          yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null || true
          "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "platforms;android-34" "build-tools;34.0.0"

      - name: Keystore из секрета
        env:
          KEYSTORE_BASE64: ${{ secrets.KEYSTORE_BASE64 }}
        run: |
          if [ -z "$KEYSTORE_BASE64" ]; then echo "Нет секрета KEYSTORE_BASE64"; exit 1; fi
          echo "$KEYSTORE_BASE64" | base64 -d > release.keystore

      - name: Сборка assembleRelease
        env:
          KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
        run: |
          if [ -f ./gradlew ]; then
            chmod +x ./gradlew
            ./gradlew assembleRelease --stacktrace
          else
            gradle assembleRelease --stacktrace
          fi

      - name: Артефакт app-release.apk
        uses: actions/upload-artifact@v4
        with:
          name: app-release
          path: app/build/outputs/apk/release/app-release.apk

      - name: Артефакт wear-release.apk
        uses: actions/upload-artifact@v4
        with:
          name: wear-release
          path: wear/build/outputs/apk/release/wear-release.apk

      - name: GitHub Release (прямые ссылки на APK)
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ github.run_number }}
          name: Версия 1.${{ github.run_number }}
          files: |
            app/build/outputs/apk/release/app-release.apk
            wear/build/outputs/apk/release/wear-release.apk

      - name: Обновить version.json
        env:
          VC: ${{ github.run_number }}
          APK_URL: "https://github.com/${{ github.repository }}/releases/download/v${{ github.run_number }}/app-release.apk"
        run: |
          printf '{\n  "versionCode": %s,\n  "versionName": "1.%s",\n  "apkUrl": "%s"\n}\n' "$VC" "$VC" "$APK_URL" > version.json
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add version.json
          git commit -m "version.json: v$VC" || exit 0
          git push
KT_EOF

# ======================= 5. version.json (шаблон) =======================
if [ ! -f version.json ]; then
cat << 'KT_EOF' > version.json
{
  "versionCode": 1,
  "versionName": "1.0",
  "apkUrl": "https://github.com/GH_REPO__/releases/download/v1/app-release.apk"
}
KT_EOF
fi

# ======================= Подстановки =======================
sed -i "s/PKG__/${APKG}/g; s|GH_REPO__|${GH_REPO}|g" "$ADIR/UpdateChecker.kt"
sed -i "s/PKG__/${WPKG}/g" "$WDIR/UpdateNotifier.kt"
sed -i "s|GH_REPO__|${GH_REPO}|g" version.json

# ======================= Проверка патчей =======================
chk() { grep -q "$1" "$2" || echo "!! $3"; }
chk 'signingConfigs'      app/build.gradle.kts  'app/build.gradle.kts: нет signingConfigs'
chk 'signingConfigs'      wear/build.gradle.kts 'wear/build.gradle.kts: нет signingConfigs'
chk 'buildConfig = true'  app/build.gradle.kts  'app: не включён buildConfig (нужна строка buildFeatures { compose = true })'
chk 'buildConfig = true'  wear/build.gradle.kts 'wear: не включён buildConfig (нужна строка buildFeatures { compose = true })'
chk 'VERSION_CODE'        app/build.gradle.kts  'app: versionCode не читается из VERSION_CODE (ожидалась строка versionCode = 1)'
chk 'VERSION_CODE'        wear/build.gradle.kts 'wear: versionCode не читается из VERSION_CODE (ожидалась строка versionCode = 1)'
chk 'FileProvider'        "$AMAN"               'телефон: нет FileProvider в манифесте'
chk 'sendUpdate'          "$DS"                 'телефон: в DataSyncService нет sendUpdate (добавь вручную: suspend fun sendUpdate(ctx: Context, json: String): Int = sendTo(ctx, "/update", json))'
chk 'UpdateEffect()'      "$AOS"                'телефон: не вставлен вызов UpdateEffect() в App() (нужна строка val drawerState = ...)'
chk '"/update"'           "$WDS"                'часы: в DataSyncService нет обработки "/update"'
chk 'pathPrefix'          "$WMAN"               'часы: манифест не принимает путь /update (нужен android:pathPrefix="/")'

# ======================= Инструкция =======================
echo
echo '================ ЧТО ДЕЛАТЬ ДАЛЬШЕ ================'
echo '1) GitHub: репозиторий -> Settings -> Secrets and variables -> Actions -> New repository secret. Добавь 4 секрета:'
echo '     KEYSTORE_BASE64   = текст из keystore.base64.txt (выведен выше, лежит в буфере, если есть termux-api)'
echo '     KEYSTORE_PASSWORD = android'
echo '     KEY_ALIAS         = android'
echo '     KEY_PASSWORD      = android'
echo '2) git add . && git commit -m "Release signing, update checker" && git push'
echo '   (release.keystore и keystore.base64.txt в .gitignore, их не коммитить)'
echo '3) ОДИН РАЗ удали старые приложения на телефоне и часах: подпись сменилась, поверх debug-версии release не встанет.'
echo '   Дальше обновления ставятся поверх.'
echo '4) Репозиторий должен быть публичным: version.json и APK скачиваются без авторизации.'
echo '5) После каждой сборки Actions сам создаёт Release vN и обновляет version.json в main.'
echo '   Перед следующим push делай: git pull --rebase'
echo '6) Сохрани release.keystore в надёжном месте. Потеряешь ключ, и обновления поверх станут невозможны.'
echo '7) Установка обновления на телефоне: уведомление -> загрузка -> уведомление "Обновление загружено" -> установка.'
echo '   При первой установке Android может попросить разрешить установку из этого приложения.'
echo '   Часы получают только уведомление; wear-release.apk ставится отдельно (adb install -r wear-release.apk).'
echo '==================================================='
