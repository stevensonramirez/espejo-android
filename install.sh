#!/bin/bash
#
# Instalador de Espejo Android — conecta tu Android por USB y su pantalla
# aparece sola en el Mac, con barra de botones. Idempotente: correrlo otra
# vez actualiza todo (lo usa también update.sh).
#
#   ./install.sh
#
set -e
cd "$(dirname "$0")"

BOLD=$(tput bold 2>/dev/null || true); NORM=$(tput sgr0 2>/dev/null || true)
say() { echo "${BOLD}==> $*${NORM}"; }

# 1. Homebrew ------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/brew ]; then
  say "Instalando Homebrew (te pedirá tu contraseña)…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

# 2. Dependencias --------------------------------------------------------
say "Instalando scrcpy, adb y Python…"
brew list scrcpy >/dev/null 2>&1 || brew install scrcpy
brew list android-platform-tools >/dev/null 2>&1 || brew install android-platform-tools
brew list python@3.13 >/dev/null 2>&1 || brew install python@3.13

say "Instalando módulos de Python (PyObjC, solo para tu usuario)…"
/opt/homebrew/bin/python3.13 -m pip install --user --break-system-packages -q \
  pyobjc-framework-Cocoa pyobjc-framework-Quartz pyobjc-framework-ApplicationServices

# 3. Scripts -------------------------------------------------------------
say "Copiando scripts a ~/bin…"
mkdir -p "$HOME/bin"
cp bin/scrcpy-autostart.sh bin/android-buttons.py bin/lidguard.sh \
   bin/android-menubar.py "$HOME/bin/"
chmod +x "$HOME/bin/scrcpy-autostart.sh" "$HOME/bin/android-buttons.py" \
         "$HOME/bin/android-menubar.py"

# 4. LaunchAgent ---------------------------------------------------------
say "Instalando el servicio de arranque automático…"
PLIST="$HOME/Library/LaunchAgents/com.stevenson.scrcpy-auto.plist"
mkdir -p "$HOME/Library/LaunchAgents"
sed "s|__HOME__|$HOME|g" launchagent/com.stevenson.scrcpy-auto.plist.template >"$PLIST"
launchctl unload "$PLIST" 2>/dev/null || true
pkill -x scrcpy 2>/dev/null || true
pkill -f android-buttons.py 2>/dev/null || true
launchctl load "$PLIST"

# 4a. Icono de barra de menús (conexión WiFi bajo demanda)
say "Instalando el icono de barra de menús (espejo por WiFi)…"
MBAR="$HOME/Library/LaunchAgents/com.stevenson.espejo-menubar.plist"
sed "s|__HOME__|$HOME|g" launchagent/com.stevenson.espejo-menubar.plist.template >"$MBAR"
launchctl unload "$MBAR" 2>/dev/null || true
pkill -f android-menubar.py 2>/dev/null || true
launchctl load "$MBAR"

# 4b. Auto-actualización (git pull cada 6 h; no toca nada si no hay cambios)
say "Instalando la auto-actualización…"
chmod +x autoupdate.sh update.sh install.sh
UPD="$HOME/Library/LaunchAgents/com.stevenson.espejo-update.plist"
sed -e "s|__HOME__|$HOME|g" -e "s|__REPO__|$PWD|g" \
  launchagent/com.stevenson.espejo-update.plist.template >"$UPD.new"
# No recargar el agent de update desde sí mismo (se mataría a mitad de update)
if ! cmp -s "$UPD.new" "$UPD" 2>/dev/null; then
  mv "$UPD.new" "$UPD"
  if [ -z "$ESPEJO_AUTOUPDATE" ]; then
    launchctl unload "$UPD" 2>/dev/null || true
    launchctl load "$UPD"
  fi
else
  rm -f "$UPD.new"
fi

# 5. Listo ---------------------------------------------------------------
cat <<EOF

${BOLD}✅ Instalado (versión $(cat VERSION)).${NORM}

Faltan solo 2 pasos manuales, una única vez:

  1. EN EL TELÉFONO: activa "Depuración por USB"
     (Ajustes > Acerca del teléfono > toca 7 veces "Número de compilación";
      luego Ajustes > Sistema > Opciones de desarrollador > Depuración USB).
     Al conectarlo al Mac saldrá un diálogo: marca "Permitir siempre" y acepta.

  2. EN EL MAC: cuando aparezca el aviso de Accesibilidad para "Python",
     acéptalo en Ajustes del Sistema > Privacidad y seguridad > Accesibilidad
     (sale solo la primera vez que se abre la barra de botones).

Conecta el teléfono por USB y la pantalla aparecerá sola. 📱✨
Para actualizar a la última versión:  ./update.sh
EOF
