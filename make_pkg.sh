#!/bin/bash
# Crea el instalador "Instalar FLUX Studio.pkg" en la carpeta dist/.
# Es el instalador clásico de Mac: doble clic → Continuar → Instalar.
# Pone «FLUX Studio» en /Applications (cierra y sustituye la versión anterior si la hay).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-0.1.$(git rev-list --count HEAD 2>/dev/null || echo 0)}"
WORK="$(mktemp -d)"
ROOT="$WORK/root"
SCRIPTS="$WORK/scripts"
RES="$WORK/resources"
mkdir -p "$ROOT" "$SCRIPTS" "$RES" dist

# 1. Compilar la app dentro de la carpeta que se instalará.
INSTALL_DIR="$ROOT" VERSION="$VERSION" ./build_app.sh --no-open

# 2. Scripts que ejecuta el instalador.
cat > "$SCRIPTS/preinstall" <<'SH'
#!/bin/bash
# Cierra FLUX Studio si está abierta y quita la versión anterior.
pkill -x FluxStudio 2>/dev/null || true
rm -rf "/Applications/FLUX Studio.app"
exit 0
SH
cat > "$SCRIPTS/postinstall" <<'SH'
#!/bin/bash
# Por si acaso, se quita la marca de cuarentena para que la app abra sin avisos.
xattr -dr com.apple.quarantine "/Applications/FLUX Studio.app" 2>/dev/null || true
exit 0
SH
chmod +x "$SCRIPTS/preinstall" "$SCRIPTS/postinstall"

# 3. Paquete de la app. "No reubicable": se instala siempre en /Applications,
#    aunque haya otra copia de la app en otra carpeta.
pkgbuild --analyze --root "$ROOT" "$WORK/componentes.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/componentes.plist"
pkgbuild --root "$ROOT" \
    --component-plist "$WORK/componentes.plist" \
    --install-location /Applications \
    --scripts "$SCRIPTS" \
    --identifier com.grupocosmic.fluxstudio.pkg \
    --version "$VERSION" \
    "$RES/FluxStudio-app.pkg" >/dev/null

# 4. Instalador con textos de bienvenida y final en español.
cp Resources/instalador/*.html "$RES/"
cat > "$WORK/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>FLUX Studio</title>
    <welcome file="bienvenida.html" mime-type="text/html"/>
    <conclusion file="final.html" mime-type="text/html"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <volume-check>
        <allowed-os-versions><os-version min="14.0"/></allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="app"/>
    </choices-outline>
    <choice id="app" title="FLUX Studio" visible="false">
        <pkg-ref id="com.grupocosmic.fluxstudio.pkg"/>
    </choice>
    <pkg-ref id="com.grupocosmic.fluxstudio.pkg" version="$VERSION" onConclusion="none">FluxStudio-app.pkg</pkg-ref>
</installer-gui-script>
XML

OUT="dist/Instalar FLUX Studio.pkg"
rm -f "$OUT"
productbuild --distribution "$WORK/distribution.xml" \
    --resources "$RES" \
    --package-path "$RES" \
    "$OUT" >/dev/null
rm -rf "$WORK"
echo "✅ Instalador creado: $OUT"
