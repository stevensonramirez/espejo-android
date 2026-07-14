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
SCRCPY_FLAGS=(--turn-screen-off --stay-awake --keyboard=uhid
              --window-width=381 --window-title "Android")

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
  "$ADB" -s "$SER" shell "touch $HB; pkill -f '^sh /data/local/tmp/lidguard' 2>/dev/null; setsid sh /data/local/tmp/lidguard.sh </dev/null >/dev/null 2>&1 & sleep 1" 2>/dev/null
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

log "watcher iniciado (cualquier Android autorizado)"

while true; do
  "$ADB" wait-for-device
  SER=$(first_device)
  [ -z "$SER" ] && { sleep 1; continue; }
  echo "$SER" >"$SERIAL_FILE"
  echo 0 >"$MODE_FILE"
  OPEN_ID=$(resolve_open_id)
  log "conectado $SER (OPENED id: '${OPEN_ID:-no plegable}') -> espejo + barra"
  start_bar

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
    scrcpy -s "$SER" "${SCRCPY_FLAGS[@]}" >>"$LOG" 2>&1 &
    SCRCPY_PID=$!

    while kill -0 "$SCRCPY_PID" 2>/dev/null && present; do
      # revivir la barra si murió a mitad de sesión
      pgrep -f android-buttons.py >/dev/null 2>&1 || start_bar
      if [ -n "$OPEN_ID" ]; then
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
  kill -9 "$SCRCPY_PID" 2>/dev/null
  stop_bar
  echo 0 >"$MODE_FILE"
  : >"$SERIAL_FILE"
  while present; do sleep 1; done
  log "desconectado -> esperando próxima conexión"
  sleep 1
done
