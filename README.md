# 📱 Espejo Android

Conecta tu Android por USB al Mac y su pantalla aparece sola, con una barra
de botones al lado (atrás, inicio, volumen, captura, zoom…). Al desconectar,
todo se cierra solo. Sin puertos abiertos ni apps en el teléfono: solo
`scrcpy` + depuración USB.

Funciona con **cualquier Android** con depuración USB autorizada. En
**plegables Motorola Razr**, con la tapa cerrada sigues viendo y usando el
teléfono completo en el Mac (magia del "device state override", con watchdog
en el teléfono para que nada quede raro si desconectas el cable).

## Instalar (una vez)

```bash
git clone <URL-DE-ESTE-REPO> ~/EspejoAndroid
cd ~/EspejoAndroid
./install.sh
```

El instalador te deja indicados los 2 únicos pasos manuales (depuración USB
en el teléfono y el permiso de Accesibilidad en el Mac).

## Actualizar

```bash
cd ~/EspejoAndroid && ./update.sh
```

## Qué instala

| Pieza | Dónde | Qué hace |
|---|---|---|
| `scrcpy-autostart.sh` | `~/bin` | Watcher: detecta conexión/desconexión, tapa del plegable, lanza/cierra todo |
| `android-buttons.py` | `~/bin` | Barra de botones nativa (AppKit) que sigue a la ventana del espejo |
| `lidguard.sh` | se sube al teléfono | Watchdog: revierte el override de tapa si el cable se va |
| LaunchAgent `com.stevenson.scrcpy-auto` | `~/Library/LaunchAgents` | Arranca el watcher al iniciar sesión y lo mantiene vivo |

## Desinstalar

```bash
launchctl unload ~/Library/LaunchAgents/com.stevenson.scrcpy-auto.plist
rm ~/Library/LaunchAgents/com.stevenson.scrcpy-auto.plist \
   ~/bin/scrcpy-autostart.sh ~/bin/android-buttons.py ~/bin/lidguard.sh
```
