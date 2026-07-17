#!/bin/bash
# Auto-actualización silenciosa de Espejo Android.
# La corre un LaunchAgent cada 6 horas — y el watcher la dispara también al
# conectar el teléfono (launchctl kickstart) si detecta versión nueva.
# Si hay versión nueva en el repo,
# la baja y re-instala. Si no hay cambios (o no hay internet), no toca nada,
# así nunca interrumpe una sesión de espejo en uso.
cd "$(dirname "$0")" || exit 0

git fetch --quiet origin 2>/dev/null || exit 0   # sin red = nada que hacer
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse @{u} 2>/dev/null) || exit 0
[ "$LOCAL" = "$REMOTE" ] && exit 0               # ya está al día

echo "$(date '+%F %T') actualizando $LOCAL -> $REMOTE" >>~/Library/Logs/espejo-update.log
if git pull --ff-only --quiet; then
  ESPEJO_AUTOUPDATE=1 ./install.sh >>~/Library/Logs/espejo-update.log 2>&1
else
  # Nunca fallar en silencio (pasó: un clon quedó semanas en v1.1.0 por un
  # falso "cambio local" de permisos). Dejar rastro y avisar en pantalla.
  {
    echo "$(date '+%F %T') PULL FALLÓ — probable cambio local; git status:"
    git status --porcelain
  } >>~/Library/Logs/espejo-update.log 2>&1
  osascript -e 'display notification "No pude actualizar: hay cambios locales en el repo. Arreglo: cd ~/EspejoAndroid && git checkout -- . && ./update.sh" with title "Espejo Android"' 2>/dev/null
fi
