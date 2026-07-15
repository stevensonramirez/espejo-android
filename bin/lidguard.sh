#!/system/bin/sh
# lidguard — corre EN EL TELÉFONO (lo sube el watcher del Mac a /data/local/tmp).
# Cuando el Mac ya no está, deshace TODO lo que la sesión de espejo haya
# alterado: el override de tapa (plegables) y el modo tablet (wm size/density)
# — si no, el teléfono quedaría "creyéndose abierto" o con resolución rara.
# Se arma en TODAS las sesiones (cualquier teléfono, no solo plegables).
#
# Detección en dos niveles:
#   1. USB fuera (sysfs, casi instantáneo) -> reset en ~1-2s
#   2. Latido del Mac viejo (>12s)         -> respaldo por si el sysfs no aplica
#
# Modo: $1 = "wifi" -> sesión inalámbrica: NO hay cable, así que el chequeo
# USB se salta y manda solo el latido (si el WiFi se cae, reset en ~12s).
MODE="${1:-usb}"
HB=/data/local/tmp/scrcpy-heartbeat

usb_online() {
  for f in /sys/class/power_supply/usb/online /sys/class/power_supply/pc_port/online; do
    if [ -r "$f" ]; then
      [ "$(cat "$f" 2>/dev/null)" = "1" ] && return 0 || return 1
    fi
  done
  return 0   # ruta desconocida: no opinar (decide el latido)
}

reset_and_exit() {
  cmd device_state state reset 2>/dev/null   # tapa (plegables; no-op si no aplica)
  wm size reset 2>/dev/null                  # modo tablet: volver al tamaño real
  wm density reset 2>/dev/null
  device_config delete launcher enable_taskbar 2>/dev/null   # taskbar de vuelta
  rm -f "$HB"
  exit 0
}

while true; do
  sleep 1
  [ "$MODE" = "wifi" ] || usb_online || reset_and_exit
  if [ -f "$HB" ]; then
    now=$(date +%s)
    mt=$(stat -c %Y "$HB" 2>/dev/null || echo 0)
    [ $((now - mt)) -gt 12 ] && reset_and_exit
  fi
done
