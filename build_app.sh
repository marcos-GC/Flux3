#!/bin/bash
# Compila FLUX Studio y monta "FLUX Studio.app" en ~/Applications.
# Uso:  ./build_app.sh            (compila, instala y abre la app)
#       ./build_app.sh --no-open  (compila e instala, sin abrir)
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
    echo "❌ No encuentro Swift. Instala Xcode desde el App Store (o ejecuta: xcode-select --install) y vuelve a intentarlo."
    exit 1
fi

APP_NAME="FLUX Studio"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP="$INSTALL_DIR/$APP_NAME.app"
VERSION="$(git describe --tags --always 2>/dev/null || echo 0.1)"

echo "▶︎ Compilando (puede tardar un par de minutos la primera vez)…"
swift build -c release --product FluxStudio
BIN="$(swift build -c release --product FluxStudio --show-bin-path)/FluxStudio"

echo "▶︎ Montando $APP"
mkdir -p "$INSTALL_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FluxStudio"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>com.grupocosmic.fluxstudio</string>
    <key>CFBundleExecutable</key><string>FluxStudio</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>es</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Firma local ("ad hoc"): suficiente para usarla en tu propio Mac.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "⚠︎ No se pudo firmar (no es grave)."

echo "✅ Listo: $APP"
if [ "${1:-}" != "--no-open" ]; then
    open "$APP"
fi
