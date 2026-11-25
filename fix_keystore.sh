#!/data/data/com.termux/files/usr/bin/bash
# Что делает скрипт:
#  - удаляет release.keystore и keystore.base64.txt из папки проекта (если есть);
#  - перезаписывает .github/workflows/build.yml: keystore берётся из кэша Actions, а при его
#    отсутствии генерируется через keytool (alias/пароли: android) и сразу сохраняется в кэш.
#    Секреты KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD больше не нужны.
#  Остальное (UpdateChecker, version.json, GitHub Release) не меняется.
set +H
cd "${1:-$HOME/ScheduleApp}" || { echo 'Папка проекта не найдена'; exit 1; }

# ---------- удалить файлы ключа из Termux ----------
for f in release.keystore keystore.base64.txt; do
  if [ -f "$f" ]; then
    rm -f "$f"
    echo "Удалён $f"
  fi
done

# ---------- workflow ----------
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

# Сборки идут строго по очереди: иначе две параллельные сборки без кэша создали бы разные ключи
concurrency:
  group: build-release
  cancel-in-progress: false

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

      - name: Keystore из кэша
        id: ks
        uses: actions/cache/restore@v4
        with:
          path: release.keystore
          key: release-keystore-v1

      - name: Генерация keystore (в кэше его нет)
        if: steps.ks.outputs.cache-hit != 'true'
        run: |
          keytool -genkeypair -keystore release.keystore -storetype PKCS12 \
            -alias android -keyalg RSA -keysize 2048 -validity 10000 \
            -storepass android -keypass android \
            -dname 'CN=Schedule, OU=App, O=Schedule, C=RU'

      - name: Сохранить keystore в кэш
        if: steps.ks.outputs.cache-hit != 'true'
        uses: actions/cache/save@v4
        with:
          path: release.keystore
          key: release-keystore-v1

      - name: Проверка keystore
        run: |
          keytool -list -keystore release.keystore -storepass android -alias android > /dev/null

      - name: Сборка assembleRelease
        env:
          KEYSTORE_FILE: release.keystore
          KEYSTORE_PASSWORD: android
          KEY_ALIAS: android
          KEY_PASSWORD: android
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

echo
echo 'Готово: .github/workflows/build.yml обновлён.'
echo '1) Секреты KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD больше не нужны, их можно удалить из GitHub.'
echo '2) git add . && git commit -m "Keystore in Actions cache" && git push'
echo '3) Первая сборка сгенерирует ключ (шаг "Генерация keystore") и сохранит его в кэш. Старые приложения на телефоне и часах'
echo '   удали один раз: подпись сменилась.'
echo '4) Если в логе очередной сборки снова выполняется шаг "Генерация keystore", кэш был потерян и ключ новый.'
echo '   Тогда обновление поверх не встанет, приложение придётся удалить. Не допускай перерывов между сборками дольше срока'
echo '   хранения кэша или увеличь этот срок в настройках Actions репозитория.'
