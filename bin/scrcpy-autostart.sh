#!/bin/bash
#
# scrcpy-autostart — al conectar CUALQUIER Android autorizado abre el espejo
# (scrcpy) + la barra de botones, y cierra ambos al desconectar. Lo lanza el
# LaunchAgent com.stevenson.scrcpy-auto y queda esperando en segundo plano.
#
# Teléfono nuevo: basta habilitarle "Depuración por USB" — al conectarlo,
# Android muestra el diálogo de autorización (marcar "Permitir siempre") y
# desde ahí todo es automático. No hay serial quemado: se resuelve en cada
# conexión y se publica en /tmp/android-mirror-serial para la barra.
#
# Plegables (Razr): con la tapa CERRADA se fuerza el device state a OPENED
# (id detectado dinámicamente con `cmd device_state print-states`) para que el
# display interno siga renderizando y el espejo muestre el TELÉFONO REAL a
# tamaño completo. Al abrir la tapa se resetea el override. En teléfonos no
# plegables nada de esto se activa. Blindaje: si el cable se va con el
# override activo, lidguard.sh (watchdog EN el teléfono) lo resetea solo.

export PATH="/opt/homebrew/bin:$PATH"
export ADB="/opt/homebrew/bin/adb"
PY="/opt/homebrew/bin/python3.13"
BAR="$HOME/bin/android-buttons.py"
GUARD="$HOME/bin/lidguard.sh"

SERIAL_FILE="/tmp/android-mirror-serial"   # serial activo (lo lee la barra)
MODE_FILE="/tmp/android-mirror-display"    # 0 = display real (compat barra)
HB=/data/local/tmp/scrcpy-heartbeat        # latido en el teléfono (lidguard)

# Flags de scrcpy:
#   --turn-screen-off : apaga la pantalla física del teléfono mientras espejas
#   --stay-awake      : evita que el teléfono se duerma mientras está conectado
#   --keyboard=uhid   : teclado físico simulado -> NO sale el teclado en pantalla
#   --window-width    : ancho por defecto (la altura la calcula scrcpy)
# (el ancho de ventana se decide por sesión: 1389 en modo tablet USB, 381 normal)
SCRCPY_FLAGS=(--turn-screen-off --stay-awake --keyboard=uhid
              --window-title "Android")

LOG=~/Library/Logs/scrcpy-auto.log
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"; }

first_device() { "$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}'; }
present()      { "$ADB" devices | grep -q "^${SER}[[:space:]]\{1,\}device"; }

# tapa FÍSICA cerrada (mBaseState; mCommittedState refleja el override, no sirve)
base_closed() {
  "$ADB" -s "$SER" shell dumpsys device_state 2>/dev/null | head -6 \
    | grep -q "mBaseState=.*name='CLOSED"
}

# id del estado OPENED de ESTE teléfono (plegables; vacío si no aplica)
resolve_open_id() {
  "$ADB" -s "$SER" shell cmd device_state print-states 2>/dev/null \
    | sed -n "s/.*identifier=\([0-9][0-9]*\), name='OPENED'.*/\1/p" | head -1
}

# start_bar: mata cualquier barra suelta y abre exactamente una.
# stop_bar:  mata TODAS las instancias de la barra (no solo la rastreada).
start_bar() { pkill -f android-buttons.py 2>/dev/null; "$PY" "$BAR" >/tmp/android-buttons.log 2>&1 & }
stop_bar()  { pkill -f android-buttons.py 2>/dev/null; }

arm_lidguard() {
  "$ADB" -s "$SER" push "$GUARD" /data/local/tmp/lidguard.sh >/dev/null 2>&1
  # pkill ANCLADO (^sh ...) para no matar la propia sesión adb (su cmdline
  # también contiene "lidguard"). El "sleep 1" da tiempo a que setsid
  # re-parente el proceso a init (si no, muere con la sesión adb).
  local LGMODE="usb"; [ "$WIFI" = 1 ] && LGMODE="wifi"
  "$ADB" -s "$SER" shell "touch $HB; pkill -f '^sh /data/local/tmp/lidguard' 2>/dev/null; setsid sh /data/local/tmp/lidguard.sh $LGMODE </dev/null >/dev/null 2>&1 & sleep 1" 2>/dev/null
}

apply_override() {
  "$ADB" -s "$SER" shell cmd device_state state "$OPEN_ID" >/dev/null 2>&1
  arm_lidguard
  OVERRIDE=1
}

reset_override() {
  "$ADB" -s "$SER" shell cmd device_state state reset >/dev/null 2>&1
  OVERRIDE=0
}

# Al conectar el teléfono: ¿hay versión nueva en el repo? Si sí, disparar el
# agent de auto-update (job INDEPENDIENTE: si el update corriera aquí como
# hijo, el `launchctl unload` del instalador lo mataría a mitad de camino) y
# esperar a que el instalador reinicie este watcher — la sesión arranca ya
# con la versión nueva. Sin red o sin novedades: sigue normal en ~1 s.
maybe_update() {
  local repo remote waited pulled FP WD
  repo=$(sed -n 's/^REPO=//p' "$HOME/.espejo-config" 2>/dev/null | head -1)
  [ -n "$repo" ] && [ -d "$repo/.git" ] || return 0
  git -C "$repo" fetch --quiet origin 2>/dev/null & FP=$!
  ( sleep 10; kill "$FP" 2>/dev/null ) 2>/dev/null & WD=$!   # tope 10 s (portales cautivos)
  wait "$FP" 2>/dev/null || { kill "$WD" 2>/dev/null; return 0; }
  kill "$WD" 2>/dev/null
  remote=$(git -C "$repo" rev-parse '@{u}' 2>/dev/null) || return 0
  [ "$(git -C "$repo" rev-parse @)" = "$remote" ] && return 0
  # si ESTA misma versión ya se intentó y falló (p. ej. pull abortado por
  # cambios locales), no reintentar: evita esperar 90 s en cada conexión
  if [ "$(cat /tmp/espejo-update-attempt 2>/dev/null)" = "$remote" ]; then
    log "update a ${remote:0:7} ya falló antes -> sigo sin reintentar"
    return 0
  fi
  echo "$remote" >/tmp/espejo-update-attempt
  log "versión nueva detectada -> actualizando antes de abrir el espejo"
  launchctl kickstart "gui/$(id -u)/com.stevenson.espejo-update" 2>/dev/null || return 0
  waited=0; pulled=0
  while [ $waited -lt 90 ]; do   # el instalador nos matará (unload+load) al terminar
    sleep 2; waited=$((waited+2))
    if [ $pulled = 0 ] && [ "$(git -C "$repo" rev-parse @ 2>/dev/null)" = "$remote" ]; then
      pulled=1; waited=60        # pull listo: máx ~30 s más para el reinicio
    fi
  done
  log "la actualización no reinició el watcher -> sigo con la versión actual"
}

log "watcher iniciado (cualquier Android autorizado)"

while true; do
  "$ADB" wait-for-device
  SER=$(first_device)
  [ -z "$SER" ] && { sleep 1; continue; }
  # ¿Conexión WiFi (serial ip:puerto) o USB?
  WIFI=0; case "$SER" in *:*) WIFI=1 ;; esac

  # chequear si hay versión nueva ANTES de montar nada (si la hay, el
  # instalador reinicia el watcher y la sesión abre ya actualizada)
  maybe_update
  present || continue   # ¿se fue el teléfono durante el chequeo/espera?

  if [ "$WIFI" = 0 ]; then
    # USB: armar el modo WiFi para el futuro (una sola vez por reinicio del
    # teléfono — `adb tcpip` reinicia el adbd, así que solo si hace falta y
    # ANTES de lanzar nada) y memorizar la IP para el menú de barra.
    if [ "$("$ADB" -s "$SER" shell getprop service.adb.tcp.port 2>/dev/null | tr -d '\r')" != "5555" ]; then
      log "armando modo WiFi (adb tcpip 5555, reinicia adbd)"
      "$ADB" -s "$SER" tcpip 5555 >/dev/null 2>&1
      sleep 3
      "$ADB" wait-for-device 2>/dev/null
      SER=$(first_device)
      [ -z "$SER" ] && { sleep 1; continue; }
    fi
    IP=$("$ADB" -s "$SER" shell ip -4 addr show wlan0 2>/dev/null \
           | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1)
    [ -n "$IP" ] && echo "$IP $SER" >"$HOME/.espejo-wifi"
  fi

  # Modo TABLET por defecto en USB (apaisado 2560x1600 @240; el botón 📋 de la
  # barra lo quita/pone). Reiniciar el launcher: sin eso el dock queda roto
  # tras el cambio de densidad. En WiFi: modo normal (más píxeles = lento).
  # Modo tablet por defecto SOLO si este Mac lo tiene activado (check en el
  # menú del icono 📱 -> ~/.espejo-config). Sin eso: modo normal (el botón 📋
  # de la barra siempre puede activarlo por sesión).
  WIDTH=381
  if [ "$WIFI" = 0 ] && grep -qs '^TABLET_DEFAULT=1' "$HOME/.espejo-config"; then
    # Modo tablet: guardar las preferencias reales del usuario (rotación y
    # modo de navegación) UNA vez, y aplicar: lienzo apaisado FIJO (lock 0 =
    # horizontal, porque el lienzo 2560x1600 hace que "natural" sea
    # horizontal y el sensor lo mandaba a vertical), navegación de 3 botones
    # (con gestos, el taskbar flotante tapaba los textbox; fijo abajo no).
    # matar un lidguard viejo ANTES del setup (si el watcher murió sin
    # teardown, el lidguard huérfano podría "restaurar" a mitad del setup)
    "$ADB" -s "$SER" shell "touch $HB; pkill -f '^sh /data/local/tmp/lidguard' 2>/dev/null" >/dev/null 2>&1
    # prefs del usuario: guardarlas SOLO desde un estado prístino (sin
    # override) — si no, una sesión reciclada guardaría el estado ya
    # modificado como si fuera el original
    "$ADB" -s "$SER" shell 'PREF=/data/local/tmp/scrcpy-prefs
if [ ! -f "$PREF" ] && ! wm size | grep -q Override; then
  A=$(settings get system accelerometer_rotation)
  U=$(settings get system user_rotation)
  N=$(cmd overlay list 2>/dev/null | grep "^\[x\] com.android.internal.systemui.navbar" | head -1 | cut -d" " -f2)
  echo "$A $U $N" > "$PREF"
fi
device_config put launcher enable_taskbar false
wm size 2560x1600
wm density 240
wm user-rotation lock 0
cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.threebutton' >/dev/null 2>&1
    LPKG=$("$ADB" -s "$SER" shell cmd shortcut get-default-launcher 2>/dev/null \
             | sed -n 's/.*{\([^/}]*\)\/.*/\1/p' | head -1)
    [ -n "$LPKG" ] && "$ADB" -s "$SER" shell "am force-stop $LPKG; input keyevent 3" >/dev/null 2>&1
    WIDTH=1389
    log "modo tablet por defecto (USB): 2560x1600@240 horizontal, 3 botones, launcher $LPKG reiniciado"
  fi

  echo "$SER" >"$SERIAL_FILE"
  echo 0 >"$MODE_FILE"
  OPEN_ID=$(resolve_open_id)
  log "conectado $SER (wifi=$WIFI, OPENED id: '${OPEN_ID:-no plegable}') -> espejo + barra"
  start_bar

  # lidguard SIEMPRE (cualquier teléfono): deshace tapa/modo tablet si el
  # cable (o el WiFi) se va a mitad de sesión.
  arm_lidguard

  OVERRIDE=0
  # Si el teléfono llega con la tapa YA cerrada, aplicar el override ANTES de
  # lanzar scrcpy (si no, scrcpy ve el display apagado y muere al arrancar).
  if [ -n "$OPEN_ID" ] && base_closed; then
    apply_override
    log "conectado con tapa cerrada -> override OPENED antes de lanzar el espejo"
    sleep 2   # dar tiempo a que el display interno se active
  fi

  ATTEMPTS=0
  while present; do
    START_TS=$(date +%s)
    scrcpy -s "$SER" "${SCRCPY_FLAGS[@]}" --window-width="$WIDTH" >>"$LOG" 2>&1 &
    SCRCPY_PID=$!

    while kill -0 "$SCRCPY_PID" 2>/dev/null && present; do
      # revivir la barra si murió a mitad de sesión
      pgrep -f android-buttons.py >/dev/null 2>&1 || start_bar
      if [ -z "$OPEN_ID" ]; then
        # no plegable: solo el latido (lo consume lidguard)
        "$ADB" -s "$SER" shell "touch $HB" >/dev/null 2>&1
      else
        # un viaje adb por tick: latido + estado de la tapa FÍSICA
        info=$("$ADB" -s "$SER" shell "touch $HB; dumpsys device_state 2>/dev/null" 2>/dev/null | head -6)
        if echo "$info" | grep -q "mBaseState=.*name='CLOSED"; then
          if [ "$OVERRIDE" = 0 ]; then
            apply_override
            log "tapa cerrada -> override OPENED (espejo sigue con el display real)"
          fi
        else
          if [ "$OVERRIDE" = 1 ]; then
            reset_override
            log "tapa abierta -> override reseteado"
          fi
        fi
      fi
      sleep 2
    done
    wait "$SCRCPY_PID" 2>/dev/null

    present || break
    # scrcpy murió con el teléfono aún conectado: si fue nada más arrancar
    # (p. ej. display aún dormido), reintentar; si llevaba rato, fue cierre manual.
    ELAPSED=$(( $(date +%s) - START_TS ))
    if [ "$ELAPSED" -lt 15 ] && [ "$ATTEMPTS" -lt 3 ]; then
      ATTEMPTS=$((ATTEMPTS + 1))
      log "scrcpy murió a los ${ELAPSED}s, reintento $ATTEMPTS/3"
      sleep 2
    else
      break   # cierre manual de la ventana -> esperar desconexión
    fi
  done

  # espejo cerrado (ventana cerrada a mano o teléfono desconectado) -> apagar todo
  if [ "$OVERRIDE" = 1 ] && present; then
    reset_override
    log "override reseteado al cerrar"
  fi
  # deshacer el modo tablet si quedó puesto y el teléfono sigue ahí
  # (si ya se fue, lo deshace lidguard en el propio teléfono):
  # tamaño/densidad, taskbar, y restaurar rotación + navegación del usuario
  present && "$ADB" -s "$SER" shell 'wm size reset
wm density reset
device_config delete launcher enable_taskbar
PREF=/data/local/tmp/scrcpy-prefs
if [ -f "$PREF" ]; then
  read A U N < "$PREF"
  [ -n "$N" ] && cmd overlay enable-exclusive --category "$N"
  if [ "$A" = "1" ]; then wm user-rotation free; else wm user-rotation lock "${U:-0}"; fi
  rm -f "$PREF"
fi' >/dev/null 2>&1
  kill -9 "$SCRCPY_PID" 2>/dev/null
  stop_bar
  echo 0 >"$MODE_FILE"
  : >"$SERIAL_FILE"
  while present; do sleep 1; done
  log "desconectado -> esperando próxima conexión"
  sleep 1
done
