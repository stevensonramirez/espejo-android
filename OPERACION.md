# Espejo Android — Operación

Conectas cualquier Android por USB al Mac y su pantalla aparece sola, con una barra de botones
nativa al lado; al desconectar, todo se cierra solo. En plegables (Razr) funciona incluso con la
tapa cerrada. Además: **modo WiFi bajo demanda** desde un icono 📱 en la barra de menús (el USB
sigue siendo automático). Repo público: **https://github.com/stevensonramirez/espejo-android**
(v1.7.0, jul-2026). Instalado en: MacBook de Stevenson (`stevenson.ramirez`) y MacBook Pro de la
novia.

## 📑 Índice
- [[#1. Arquitectura en una hoja|1 · Arquitectura en una hoja]]
- [[#2. Instalación y actualización|2 · Instalación y actualización]]
- [[#3. Rutas, archivos y logs|3 · Rutas, archivos y logs]]
- [[#4. Gestión del servicio|4 · Gestión del servicio]]
- [[#5. Plegables (Razr): tapa cerrada|5 · Plegables (Razr): tapa cerrada]]
- [[#6. La barra de botones|6 · La barra de botones]]
- [[#7. Modo WiFi (bajo demanda)|7 · Modo WiFi (bajo demanda)]]
- [[#8. Troubleshooting|8 · Troubleshooting]]
- [[#9. Quick reference|9 · Quick reference]]
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
        ├─ adb wait-for-device → detecta CUALQUIER Android autorizado (USB o WiFi)
        ├─ USB: arma el modo WiFi (adb tcpip 5555, 1 vez por reinicio del
        │       teléfono) y memoriza su IP en ~/.espejo-wifi
        ├─ escribe /tmp/android-mirror-serial (la barra lo lee)
        ├─ plegable? → override de device state + sube lidguard.sh al teléfono
        ├─ lanza scrcpy  (USB: modo TABLET apaisado por defecto; pantalla física apagada)
        ├─ lanza ~/bin/android-buttons.py  «la barra» (y la revive si muere)
        └─ al desconectar: resetea override, cierra scrcpy y barra

   LaunchAgent com.stevenson.espejo-menubar  (siempre vivo)
   └─ ~/bin/android-menubar.py  «icono 📱 en la barra de menús»
        └─ clic "Conectar por WiFi" → adb connect a la IP memorizada
           (con redescubrimiento mDNS si cambió) → el watcher hace el resto
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
| Scripts vivos (los que corren) | `~/bin/scrcpy-autostart.sh`, `~/bin/android-buttons.py`, `~/bin/lidguard.sh`, `~/bin/android-menubar.py` |
| LaunchAgents | `~/Library/LaunchAgents/com.stevenson.scrcpy-auto.plist`, `com.stevenson.espejo-update.plist` y `com.stevenson.espejo-menubar.plist` |
| Teléfono memorizado para WiFi | `~/.espejo-wifi` ("IP SERIAL", lo escribe el watcher en cada sesión USB) |
| Log del icono de menús | `/tmp/android-menubar.log` |
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
Mac, con ✓ verde de confirmación), notificaciones, ajustes rápidos, buscar (también con ⌘F si el espejo está al frente), atrás/inicio/recientes, Vol+/Vol−, rotar
(rotación NATIVA por app: `wm user-rotation lock 1` ↔ `free`); abajo, separados: pantalla
completa, **modo tablet** y apagar pantalla. Arrastrar la barra a mano desactiva el "seguir"
(📌 lo reactiva).

**Modo tablet 📋 — DEFAULT en USB:** al conectar por cable, el watcher pone el display REAL del
teléfono en **2560×1600 @ 240dpi APAISADO** (`wm size` + `wm density`) y abre la ventana grande
(1150 px) — el MISMO teléfono (tu launcher, tus apps, tus notificaciones) pero con lienzo
horizontal y densidad de tablet (sw ≈ 1066dp → layout de tablet). El botón 📋 de la barra lo
QUITA (vuelve al modo teléfono vertical normal, ventana chica) o lo vuelve a poner; el botón
lee el estado real del teléfono ("Override size") al arrancar, así que siempre está en sincronía.
En cada cambio se reinicia el launcher (sin eso el dock de Moto queda roto/imclicable tras
cambiar la densidad). **Por WiFi la sesión es modo normal** y el botón avisa y no hace nada
(encodear 4× más píxeles satura el WiFi). **Blindaje:** lidguard resetea `wm size/density` si
el cable se va, y el watcher lo resetea en el teardown — el teléfono nunca queda con resolución
rara en la mano. (Enfoque descartado: display virtual `--new-display` — solo mostraba el
launcher secundario limitado, sin forma práctica de abrir cualquier app.)

**Cómo quedó armado el modo tablet (v1.9.0):** horizontal FIJO (`wm user-rotation lock 0` — en
este lienzo lo natural es horizontal y el sensor lo mandaba a vertical), **navegación de 3
botones** durante el modo (con gestos, el taskbar era un pill flotante roto que tapaba los
campos de texto; fijo abajo renderiza bien y no tapa nada), y las preferencias reales del
usuario (auto-rotate, orientación, modo de navegación) se guardan una vez en el teléfono
(`/data/local/tmp/scrcpy-prefs`) y se restauran al salir del modo, en el teardown y en
lidguard. El botón ⟳ es consciente del modo: en tablet alterna horizontal↔vertical; en modo
normal, horizontal↔libre. Limitación conocida: los ajustes rápidos renderizan a medias (bug de
Moto con el resize en caliente; el botón 🔔 de notificaciones funciona completo). Ojo:
entrar/salir del modo tablet puede disparar el candado → teclear el PIN en el espejo. Ventana
por defecto del modo tablet: 1389×901 (ajustable en `TABLET_WIN` de la barra y `WIDTH` del
watcher).

**Seguimiento:** un event tap (solo-escucha) de arrastre de mouse re-sincroniza la barra en cada
evento → va a 1-2 cuadros del espejo (límite del compositor de macOS). Respaldo: polling
adaptativo por ID de ventana (0.016 s en movimiento / 0.08 s quieto / 0.3 s sin espejo) que cubre
cambios de Space y movimientos por script. Requiere el permiso de Accesibilidad de "Python".

## 7. Modo WiFi (bajo demanda)

El USB no cambia: cable = espejo automático, siempre. El WiFi es **adicional y manual**:

1. **Se arma solo:** cada vez que conectas el teléfono por cable, el watcher habilita
   `adb tcpip 5555` (solo si hace falta — una vez por reinicio del teléfono, porque reinicia el
   adbd y cuesta ~3 s) y memoriza la IP en `~/.espejo-wifi`.
2. **Se usa con un clic:** icono 📱 en la barra de menús → "Conectar espejo por WiFi". El menú
   también muestra el estado (USB / WiFi / sin conexión) y "Desconectar" cuando aplica.
3. El `adb connect` hace aparecer el device y **el watcher hace todo lo demás** (espejo, barra,
   tapa) exactamente igual que por USB. Si la IP cambió, se redescubre por mDNS y se re-memoriza.

**Límites conocidos:** misma red WiFi (en redes corporativas los equipos suelen estar aislados);
tras reiniciar el teléfono hay que pasar por cable una vez; sin cable el teléfono no carga y
gasta batería; en sesión WiFi el lidguard corre en modo `wifi` (sin señal de cable: si la red se
cae con la tapa engañada, el reset llega por latido en ~12 s; el botón "Desconectar" del menú
resetea la tapa ANTES de cortar, así el cover revive al instante).

## 8. Troubleshooting

| Síntoma | Causa | Arreglo |
|---|---|---|
| Conecto el teléfono y no pasa nada | Depuración USB sin autorizar | `adb devices` → si dice `unauthorized`, mirar el teléfono y aceptar con "Permitir siempre" |
| Espejo abre y muere al conectar con tapa cerrada | Override no alcanzó a aplicarse | El watcher ya reintenta 3×; si persiste, revisar `~/Library/Logs/scrcpy-auto.log` |
| Desconecté con tapa cerrada y la pantalla externa quedó muerta | lidguard no corría | Abrir y cerrar la tapa la resetea; o `adb shell cmd device_state state reset` |
| La barra no aparece | Murió y el watcher aún no la revive | Esperar ~10 s; si no, ver `/tmp/android-buttons.log` |
| La barra no sigue al espejo / sin `drag-tap: OK` en el log | Falta Accesibilidad para "Python" | Ajustes del Sistema → Privacidad y seguridad → Accesibilidad → activar Python |
| La barra sigue "a saltos" | El tap murió y quedó solo el polling | `pkill -f android-buttons.py` (renace con tap); confirmar `drag-tap: OK` |
| Apps se ven apeñuzcadas al rotar | Quedó `fixed-to-user-rotation enabled` de pruebas viejas | `adb shell wm fixed-to-user-rotation default` (el botón ⟳ ya lo auto-sana) |
| El teléfono quedó con resolución rara en la mano | Modo tablet no se deshizo (falla múltiple) | `adb shell "wm size reset; wm density reset"` (lidguard y el watcher lo hacen solos normalmente) |
| La novia no recibe una mejora | Auto-update aún no corre (cada 6 h) | `cd ~/EspejoAndroid && ./update.sh`; ver `~/Library/Logs/espejo-update.log` |
| Todo raro tras editar el watcher | El watcher viejo sigue en memoria | `launchctl unload` + `load` del plist (sección 4) |
| "Conectar por WiFi" no encuentra el teléfono | Otra red / IP nueva / teléfono reiniciado | Mismo WiFi ambos; si reinició, conectar por cable una vez (re-arma solo) |
| No aparece el icono 📱 en la barra de menús | El agent del menú no corre | `launchctl load ~/Library/LaunchAgents/com.stevenson.espejo-menubar.plist`; ver `/tmp/android-menubar.log` |

## 9. Quick reference

```bash
adb devices                                  # ¿teléfono autorizado?
tail -f ~/Library/Logs/scrcpy-auto.log       # qué está haciendo el watcher
cat /tmp/android-buttons.log                 # salud de la barra (drag-tap: OK)
pkill -f android-buttons.py                  # reiniciar barra (renace sola)
cd ~/EspejoAndroid && ./update.sh            # actualizar YA a la última versión
adb shell cmd device_state state reset       # des-engañar la tapa a mano
cat ~/.espejo-wifi                           # IP memorizada para el modo WiFi
adb connect $(awk '{print $1}' ~/.espejo-wifi):5555   # conexión WiFi a mano
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
| `bin/lidguard.sh` | Watchdog EN el teléfono: revierte override de tapa Y modo tablet si el cable se va (arg `wifi` = solo latido); se arma en TODAS las sesiones |
| `bin/android-menubar.py` | Icono de barra de menús: conectar/desconectar espejo por WiFi (`adb connect` a `~/.espejo-wifi` + fallback mDNS) |
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
- WiFi: `adb tcpip 5555` REINICIA el adbd (el device desaparece ~3 s) → el watcher solo lo hace
  si `getprop service.adb.tcp.port` ≠ 5555 y siempre ANTES de lanzar scrcpy. Un serial con `:`
  (`ip:puerto`) = sesión WiFi → lidguard va en modo `wifi` (sin chequeo de cable). El "Desconectar"
  del menú debe resetear el device_state ANTES del `adb disconnect` (sin cable no hay sysfs y el
  latido tarda ~12 s).
- Los NSMenuItem con enabled manual requieren `menu.setAutoenablesItems_(False)` (si no, AppKit
  los pisa).

### Mapa local ↔ remoto
- No hay servidor: "remoto" = GitHub como canal de distribución. Ambos Macs son instalaciones
  idénticas del mismo repo; la de Stevenson es además la de desarrollo (edita `~/bin` y publica).
