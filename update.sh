#!/bin/bash
# Actualiza Espejo Android a la última versión del repo y re-instala.
set -e
cd "$(dirname "$0")"
echo "==> Bajando la última versión…"
git pull --ff-only
./install.sh
