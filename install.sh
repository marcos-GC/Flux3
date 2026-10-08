#!/bin/bash
# Instalador en un paso: descarga la última versión de FLUX Studio y la pone en Aplicaciones.
# Uso (en Terminal):
#   curl -fsSL https://raw.githubusercontent.com/marcos-GC/Flux3/claude/flux-studio-macos-app-afvdnk/install.sh | bash
set -euo pipefail

URL="https://github.com/marcos-GC/Flux3/releases/download/ultima/FLUX-Studio.dmg"
TMP="$(mktemp -d)"
DMG="$TMP/FLUX-Studio.dmg"
MOUNT="$TMP/volumen"

echo "▶︎ Descargando FLUX Studio…"
curl -fL --progress-bar "$URL" -o "$DMG"

echo "▶︎ Instalando…"
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MOUNT"
trap 'hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x FluxStudio 2>/dev/null || true
rm -rf "$DEST/FLUX Studio.app"
ditto "$MOUNT/FLUX Studio.app" "$DEST/FLUX Studio.app"
# Descargado con curl no lleva marca de cuarentena; por si acaso, se quita.
xattr -dr com.apple.quarantine "$DEST/FLUX Studio.app" 2>/dev/null || true

echo "✅ FLUX Studio instalada en $DEST. Abriéndola…"
open "$DEST/FLUX Studio.app"
