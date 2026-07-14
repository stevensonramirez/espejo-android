#!/system/bin/sh
# lidguard — corre EN EL TELÉFONO (lo sube el watcher del Mac a /data/local/tmp).
# Resetea el override de device_state cuando el Mac ya no está, para que el Razr
# vuelva a comportarse según su tapa real (si no, quedaría "creyéndose abierto"
# con la tapa cerrada y el cover muerto).
#
# Detección en dos niveles:
#   1. USB fuera (sysfs, casi instantáneo) -> reset en ~1-2s
#   2. Latido del Mac viejo (>12s)         -> respaldo por si el sysfs no aplica
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
  cmd device_state state reset
  rm -f "$HB"
  exit 0
}

while true; do
  sleep 1
  usb_online || reset_and_exit
  if [ -f "$HB" ]; then
    now=$(date +%s)
    mt=$(stat -c %Y "$HB" 2>/dev/null || echo 0)
    [ $((now - mt)) -gt 12 ] && reset_and_exit
  fi
done
