#!/bin/bash
# Compila Octava en modo Release y la instala en /Applications (o la actualiza).
# Se puede abrir con doble clic. Tus datos (biblioteca, escuchas, listas, ajustes, sesión de Last.fm)
# no se tocan: viven en el contenedor de la app, no dentro de ella.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

DEST="/Applications/Octava.app"
BUILT="build/DerivedData/Build/Products/Release/Octava.app"

echo "==> Generando el proyecto"
xcodegen generate

echo "==> Compilando Octava (Release)"
xcodebuild -project Octava.xcodeproj -scheme Octava -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build | grep -E "error:|warning: .*Octava/|BUILD" || true
[ -d "$BUILT" ] || { echo "No se encontró la app compilada en $BUILT"; exit 1; }

echo "==> Cerrando Octava si está abierta"
pkill -x Octava 2>/dev/null && sleep 1 || true

echo "==> Instalando en $DEST"
rm -rf "$DEST"
ditto "$BUILT" "$DEST"
codesign --verify --deep "$DEST" && echo "Firma local verificada."

echo "==> Abriendo Octava"
open "$DEST"
echo "Listo: Octava instalada en /Applications."
