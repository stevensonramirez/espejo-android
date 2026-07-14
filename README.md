# 📱 Espejo Android

Conecta tu Android por USB al Mac y su pantalla aparece sola, con una barra
de botones al lado (atrás, inicio, volumen, captura, zoom…). Al desconectar,
todo se cierra solo. Sin puertos abiertos ni apps en el teléfono: solo
`scrcpy` + depuración USB.

Funciona con **cualquier Android** con depuración USB autorizada. Además hay
**modo WiFi bajo demanda**: un icono 📱 en la barra de menús del Mac permite
abrir el espejo sin cable (misma red WiFi; el teléfono se memoriza solo cada
vez que lo conectas por cable). En
**plegables Motorola Razr**, con la tapa cerrada sigues viendo y usando el
teléfono completo en el Mac (magia del "device state override", con watchdog
en el teléfono para que nada quede raro si desconectas el cable).

## Instalar (una vez)

```bash
git clone https://github.com/stevensonramirez/espejo-android.git ~/EspejoAndroid
cd ~/EspejoAndroid
./install.sh
```

El instalador te deja indicados los 2 únicos pasos manuales (depuración USB
en el teléfono y el permiso de Accesibilidad en el Mac).

## Actualizar

**No hay que hacer nada:** cada 6 horas se revisa el repo y, si hay versión
nueva, se instala sola (log en `~/Library/Logs/espejo-update.log`). Para
forzarla ya mismo:

```bash
cd ~/EspejoAndroid && ./update.sh
```

## Qué instala

| Pieza | Dónde | Qué hace |
|---|---|---|
| `scrcpy-autostart.sh` | `~/bin` | Watcher: detecta conexión/desconexión, tapa del plegable, lanza/cierra todo |
| `android-buttons.py` | `~/bin` | Barra de botones nativa (AppKit) que sigue a la ventana del espejo |
| `android-menubar.py` | `~/bin` | Icono de barra de menús: conectar/desconectar el espejo por WiFi |
| `lidguard.sh` | se sube al teléfono | Watchdog: revierte el override de tapa si el cable se va |
| LaunchAgent `com.stevenson.scrcpy-auto` | `~/Library/LaunchAgents` | Arranca el watcher al iniciar sesión y lo mantiene vivo |
| LaunchAgent `com.stevenson.espejo-update` | `~/Library/LaunchAgents` | Auto-actualiza desde el repo cada 6 horas |

## Desinstalar

```bash
launchctl unload ~/Library/LaunchAgents/com.stevenson.scrcpy-auto.plist \
                 ~/Library/LaunchAgents/com.stevenson.espejo-update.plist \
                 ~/Library/LaunchAgents/com.stevenson.espejo-menubar.plist
rm ~/Library/LaunchAgents/com.stevenson.scrcpy-auto.plist \
   ~/Library/LaunchAgents/com.stevenson.espejo-update.plist \
   ~/Library/LaunchAgents/com.stevenson.espejo-menubar.plist \
   ~/bin/scrcpy-autostart.sh ~/bin/android-buttons.py ~/bin/lidguard.sh \
   ~/bin/android-menubar.py ~/.espejo-wifi
```
