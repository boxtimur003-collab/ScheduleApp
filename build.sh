#!/data/data/com.termux/files/usr/bin/bash
cd "$(dirname "$0")"
gradle assembleDebug --no-daemon "$@" || { echo "Сборка не удалась"; exit 1; }
OUT="$HOME/ScheduleApks"; mkdir -p "$OUT"
cp app/build/outputs/apk/debug/app-debug.apk "$OUT/"
cp wear/build/outputs/apk/debug/wear-debug.apk "$OUT/"
if [ -d "$HOME/storage/downloads" ]; then
  mkdir -p "$HOME/storage/downloads/ScheduleApks"
  cp "$OUT"/*.apk "$HOME/storage/downloads/ScheduleApks/"
fi
echo "Готово: $OUT"
