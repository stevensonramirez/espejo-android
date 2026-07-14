# Espejo Android — Operación

Conectas cualquier Android por USB al Mac y su pantalla aparece sola, con una barra de botones
nativa al lado; al desconectar, todo se cierra solo. En plegables (Razr) funciona incluso con la
tapa cerrada. Repo público: **https://github.com/stevensonramirez/espejo-android** (v1.2.0,
jul-2026). Instalado en: MacBook de Stevenson (`stevenson.ramirez`) y MacBook Pro de la novia.

## 📑 Índice
- [[#1. Arquitectura en una hoja|1 · Arquitectura en una hoja]]
- [[#2. Instalación y actualización|2 · Instalación y actualización]]
- [[#3. Rutas, archivos y logs|3 · Rutas, archivos y logs]]
- [[#4. Gestión del servicio|4 · Gestión del servicio]]
- [[#5. Plegables (Razr): tapa cerrada|5 · Plegables (Razr): tapa cerrada]]
- [[#6. La barra de botones|6 · La barra de botones]]
- [[#7. Troubleshooting|7 · Troubleshooting]]
- [[#8. Quick reference|8 · Quick reference]]
- [[#Appendix · Contexto para agentes de IA|Appendix · Contexto para agentes de IA]]

## 1. Arquitectura en una hoja

```
                          GitHub (espejo-android)
                               ▲            │ git fetch cada 6 h
                        push   │            ▼
   Mac de Stevenson ───────────┘   LaunchAgent com.stevenson.espejo-update
                                   └─ autoupdate.sh → install.sh (solo si hay commits)

   LaunchAgent com.stevenson.scrcpy-auto  (RunAtLoad + KeepAlive)
   └─ ~/bin/scrcpy-autostart.sh  «el watcher»
        ├─ adb wait-for-device → detecta CUALQUIER Android autorizado (sin serial fijo)
        ├─ escribe /tmp/android-mirror-serial (la barra lo lee)
        ├─ plegable? → override de device state + sube lidguard.sh al teléfono
        ├─ lanza scrcpy  (ventana "Android", USB, pantalla física apagada)
        ├─ lanza ~/bin/android-buttons.py  «la barra» (y la revive si muere)
        └─ al desconectar: resetea override, cierra scrcpy y barra
```

- **scrcpy 3.3.4** (Homebrew) hace el espejo; flags: `--turn-screen-off --stay-awake
  --keyboard=uhid --window-width=381 --window-title Android` (altura = proporción del teléfono).
- **La barra** es AppKit/PyObjC nativo: panel HUD translúcido, SF Symbols, no roba el foco, sigue
  a la ventana del espejo pegada al arrastre (event tap de mouse).
- **lidguard.sh** corre EN el teléfono: si el cable se va con la tapa "engañada", revierte el
  override en ~1-2 s para que la pantalla externa reviva.

## 2. Instalación y actualización

**Instalar (una vez):**
```bash
git clone https://github.com/stevensonramirez/espejo-android.git ~/EspejoAndroid
cd ~/EspejoAndroid && ./install.sh
```
Pasos manuales (una sola vez): (1) Depuración USB en el teléfono + "Permitir siempre" en el
diálogo al conectar; (2) aceptar el permiso de Accesibilidad para "Python" en el Mac.

**Actualizar:** no hay que hacer nada — cada 6 h el agent de update revisa GitHub y, si hay
versión nueva, la instala solo (nunca toca nada si no hay cambios). Forzarla ya:
```bash
cd ~/EspejoAndroid && ./update.sh
```

**Publicar una mejora (Stevenson):** ver el workflow del Appendix — editar `~/bin`, copiar al
repo, commit + push; el Mac de la novia lo toma solo en ≤6 h.

## 3. Rutas, archivos y logs

| Qué | Dónde |
|---|---|
| Repo local | `~/EspejoAndroid` (remoto `origin` = GitHub) |
| Scripts vivos (los que corren) | `~/bin/scrcpy-autostart.sh`, `~/bin/android-buttons.py`, `~/bin/lidguard.sh` |
| LaunchAgents | `~/Library/LaunchAgents/com.stevenson.scrcpy-auto.plist` y `com.stevenson.espejo-update.plist` |
| Log del watcher | `~/Library/Logs/scrcpy-auto.log` (+ `.out.log` / `.err.log`) |
| Log de la barra | `/tmp/android-buttons.log` (debe decir `drag-tap: OK`) |
| Log del auto-update | `~/Library/Logs/espejo-update.log` |
| Serial del teléfono conectado | `/tmp/android-mirror-serial` (lo escribe el watcher, lo lee la barra) |
| Modo display (legado, siempre 0) | `/tmp/android-mirror-display` |
| En el teléfono | `/data/local/tmp/lidguard.sh` y latido `/data/local/tmp/scrcpy-heartbeat` |

## 4. Gestión del servicio

```bash
# Reiniciar el watcher (necesario tras editar scrcpy-autostart.sh)
launchctl unload ~/Library/LaunchAgents/com.stevenson.scrcpy-auto.plist
launchctl load   ~/Library/LaunchAgents/com.stevenson.scrcpy-auto.plist

# Reiniciar SOLO la barra (tras editar android-buttons.py) — el watcher la revive en ~2-10 s
pkill -f android-buttons.py

# ¿Está todo vivo?
launchctl list | grep -E "scrcpy-auto|espejo-update"
pgrep -x scrcpy; pgrep -f android-buttons.py
```

## 5. Plegables (Razr): tapa cerrada

Con la tapa cerrada el panel interno no renderiza. El watcher vigila la tapa **física**
(`dumpsys device_state` → `mBaseState`) cada 2 s y al cerrarla aplica
`cmd device_state state <id-OPENED>` → Android "cree" que está abierta y el espejo muestra el
teléfono real completo. Al abrirla: `state reset`. El id de OPENED se detecta dinámicamente
(`cmd device_state print-states`); **si el teléfono no es plegable, todo esto se salta** — cero
conflicto con teléfonos normales.

**Blindaje anti-bolsillo:** `lidguard.sh` (en el teléfono) revisa cada 1 s el USB por sysfs; si el
cable se va (o el latido del Mac envejece >12 s), revierte el override y la pantalla externa
revive en ~1-2 s. Cerrar la tapa puede disparar el bloqueo → se teclea el PIN en el espejo.

## 6. La barra de botones

Panel flotante nativo (AppKit) a la derecha del espejo (izquierda si no cabe). No roba el foco al
hacer clic. Botones: 📌 seguir on/off, zoom ±, captura (→ galería del teléfono + portapapeles del
Mac, con ✓ verde de confirmación), notificaciones, atrás/inicio/recientes/menú, Vol+/Vol−, rotar
(rotación NATIVA por app: `wm user-rotation lock 1` ↔ `free`); abajo, separados: pantalla
completa y apagar pantalla. Arrastrar la barra a mano desactiva el "seguir" (📌 lo reactiva).

**Seguimiento:** un event tap (solo-escucha) de arrastre de mouse re-sincroniza la barra en cada
evento → va a 1-2 cuadros del espejo (límite del compositor de macOS). Respaldo: polling
adaptativo por ID de ventana (0.016 s en movimiento / 0.08 s quieto / 0.3 s sin espejo) que cubre
cambios de Space y movimientos por script. Requiere el permiso de Accesibilidad de "Python".

## 7. Troubleshooting

| Síntoma | Causa | Arreglo |
|---|---|---|
| Conecto el teléfono y no pasa nada | Depuración USB sin autorizar | `adb devices` → si dice `unauthorized`, mirar el teléfono y aceptar con "Permitir siempre" |
| Espejo abre y muere al conectar con tapa cerrada | Override no alcanzó a aplicarse | El watcher ya reintenta 3×; si persiste, revisar `~/Library/Logs/scrcpy-auto.log` |
| Desconecté con tapa cerrada y la pantalla externa quedó muerta | lidguard no corría | Abrir y cerrar la tapa la resetea; o `adb shell cmd device_state state reset` |
| La barra no aparece | Murió y el watcher aún no la revive | Esperar ~10 s; si no, ver `/tmp/android-buttons.log` |
| La barra no sigue al espejo / sin `drag-tap: OK` en el log | Falta Accesibilidad para "Python" | Ajustes del Sistema → Privacidad y seguridad → Accesibilidad → activar Python |
| La barra sigue "a saltos" | El tap murió y quedó solo el polling | `pkill -f android-buttons.py` (renace con tap); confirmar `drag-tap: OK` |
| Apps se ven apeñuzcadas al rotar | Quedó `fixed-to-user-rotation enabled` de pruebas viejas | `adb shell wm fixed-to-user-rotation default` (el botón ⟳ ya lo auto-sana) |
| La novia no recibe una mejora | Auto-update aún no corre (cada 6 h) | `cd ~/EspejoAndroid && ./update.sh`; ver `~/Library/Logs/espejo-update.log` |
| Todo raro tras editar el watcher | El watcher viejo sigue en memoria | `launchctl unload` + `load` del plist (sección 4) |

## 8. Quick reference

```bash
adb devices                                  # ¿teléfono autorizado?
tail -f ~/Library/Logs/scrcpy-auto.log       # qué está haciendo el watcher
cat /tmp/android-buttons.log                 # salud de la barra (drag-tap: OK)
pkill -f android-buttons.py                  # reiniciar barra (renace sola)
cd ~/EspejoAndroid && ./update.sh            # actualizar YA a la última versión
adb shell cmd device_state state reset       # des-engañar la tapa a mano
```

---

## Appendix · Contexto para agentes de IA

### Stack y restricciones
- macOS (MacBook corporativa **sin admin**: todo es por-usuario — Homebrew, LaunchAgents de
  usuario, TCC de Accesibilidad; nada de daemons ni MDM). Python 3.13 de Homebrew + PyObjC
  (`pip install --user --break-system-packages` para NO cambiar el binario y conservar su grant
  de Accesibilidad). scrcpy/adb de Homebrew.
- Genérico: **no hay serial quemado** ni nada específico de un modelo; lo de plegables se
  auto-detecta y se salta en teléfonos normales.

### Mapa de archivos (repo `~/EspejoAndroid`)
| Archivo | Qué hace |
|---|---|
| `bin/scrcpy-autostart.sh` | Watcher: detección de teléfono/tapa, lanza scrcpy y barra, override plegable, teardown |
| `bin/android-buttons.py` | Barra nativa AppKit: botones adb, seguimiento por event tap + polling |
| `bin/lidguard.sh` | Watchdog EN el teléfono: revierte el override si el cable se va |
| `install.sh` | Instalador idempotente (brew, pips, copia a `~/bin`, ambos LaunchAgents) |
| `update.sh` | `git pull --ff-only` + `./install.sh` (manual) |
| `autoupdate.sh` | Lo corre el agent cada 6 h: fetch; si hay commits → pull + install con `ESPEJO_AUTOUPDATE=1` |
| `launchagent/*.plist.template` | Templates con `__HOME__` / `__REPO__` que install.sh materializa |
| `VERSION` | Versión mostrada por el instalador (bump en cada release) |
| `OPERACION.md` | Este documento (copia espejo en Obsidian) |

### Workflow de cambios (¡en este orden!)
1. Editar la **copia viva** en `~/bin/` (el repo NO es lo que corre).
2. Probar: barra → `pkill -f android-buttons.py` (renace en ~2-10 s); watcher →
   `launchctl unload+load` del plist.
3. Sincronizar: `cp ~/bin/<script> ~/EspejoAndroid/bin/` + bump `VERSION`.
4. `git commit` + `git push` → el Mac de la novia se actualiza solo en ≤6 h.
5. Si cambió operación/infra: actualizar este `OPERACION.md` **y** su copia en Obsidian
   (`~/Documents/ClientesSyncMacDT/ProyectosClaude/Espejo Android - Operación.md`).

### Gotchas / cosas que NO hacer
- **Tapa física = `mBaseState`**, NUNCA `mCommittedState` (refleja el propio override).
- lidguard: lanzarlo con `setsid sh ... & sleep 1` (sin el sleep muere con la sesión adb) y
  matarlo con patrón ANCLADO `pkill -f '^sh /data/local/tmp/lidguard'` (sin anclar, la propia
  sesión adb contiene "lidguard" y se mata a sí misma).
- Rotación: NO usar `wm fixed-to-user-rotation enabled` (apeñuzca las apps sin modo horizontal);
  lo correcto es `wm user-rotation lock 1` ↔ `free` + `fixed-to-user-rotation default` al soltar.
- Seguimiento de ventana — **caminos muertos en PyObjC** (no reintentar): `AXObserverCreate`
  (callback C no soportado: "Callable argument is not a PyObjC closure") y
  `NSEvent.addGlobalMonitorForEventsMatchingMask_handler_` (se crea OK pero no entrega eventos en
  esta app accesoria). Lo que SÍ funciona: `CGEventTapCreate` listen-only de
  `kCGEventLeftMouseDragged` + re-enable si llega `kCGEventTapDisabledByTimeout`.
- Al medir lag de seguimiento, convertir px a TIEMPO (desvío ÷ velocidad): un umbral en px
  castiga el ~1 frame inherente del window server y da falsos "sigue lento".
- `install.sh` NO debe recargar el agent de update cuando lo invoca `autoupdate.sh` (se mataría a
  sí mismo): eso lo controla la variable `ESPEJO_AUTOUPDATE=1`.
- Verificaciones en Bash: `pkill` + `pgrep` inmediato da falsos muertos (el watcher tarda hasta
  ~10 s en revivir la barra); y un pipeline que termina en grep/pgrep sin matches sale con código
  144/1 — benigno.
- El diálogo RSA del teléfono es por-Mac: cada máquina nueva necesita su "Permitir siempre".

### Mapa local ↔ remoto
- No hay servidor: "remoto" = GitHub como canal de distribución. Ambos Macs son instalaciones
  idénticas del mismo repo; la de Stevenson es además la de desarrollo (edita `~/bin` y publica).
