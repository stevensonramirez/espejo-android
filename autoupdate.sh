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
git pull --ff-only --quiet && ESPEJO_AUTOUPDATE=1 ./install.sh >>~/Library/Logs/espejo-update.log 2>&1
