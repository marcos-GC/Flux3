#!/bin/bash
# Crea el instalador "FLUX-Studio.dmg" en la carpeta dist/.
# Al abrirlo, el usuario arrastra FLUX Studio a la carpeta Aplicaciones.
set -euo pipefail
cd "$(dirname "$0")"

STAGE="$(mktemp -d)/FLUX Studio"
mkdir -p "$STAGE" dist
INSTALL_DIR="$STAGE" ./build_app.sh --no-open

ln -s /Applications "$STAGE/Aplicaciones"
cat > "$STAGE/LÉEME - Cómo instalar.txt" <<'TXT'
CÓMO INSTALAR FLUX STUDIO

1. Arrastra «FLUX Studio» encima de la carpeta «Aplicaciones».
2. Abre la carpeta Aplicaciones y haz doble clic en FLUX Studio.

SI macOS DICE QUE NO PUEDE ABRIRLA
La app no está firmada con un certificado de pago de Apple, así que
la primera vez macOS la bloquea. Para permitirla (solo una vez):

  1. Cierra el aviso (pulsa «Listo» o «Aceptar»).
  2. Abre  Ajustes del Sistema → Privacidad y seguridad.
  3. Baja hasta el final: verás «Se ha bloqueado FLUX Studio…».
     Pulsa «Abrir igualmente» y confirma con tu contraseña o Touch ID.

A partir de ahí se abre normalmente.

PRIMEROS PASOS
Ve a Ajustes (rueda dentada abajo a la izquierda), pega tu API key de
Black Forest Labs y pulsa «Guardar en el Llavero».
TXT

rm -f dist/FLUX-Studio.dmg
hdiutil create -volname "FLUX Studio" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ dist/FLUX-Studio.dmg >/dev/null
echo "✅ Instalador creado: dist/FLUX-Studio.dmg"
