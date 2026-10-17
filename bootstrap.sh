#!/usr/bin/env bash
# Prepara el proyecto Octava en un Mac:
#   1. Verifica Xcode.
#   2. Instala XcodeGen con Homebrew si falta.
#   3. Genera Octava.xcodeproj desde project.yml.
#   4. Inicializa git si la carpeta aún no es un repositorio.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Verificando Xcode"
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "No encontré Xcode. Instálalo desde la App Store, ábrelo una vez y vuelve a ejecutar este script."
  echo "Si ya está instalado, ejecuta: sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi
xcodebuild -version | head -1

echo "==> Verificando XcodeGen"
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Instalando XcodeGen con Homebrew…"
    brew install xcodegen
  else
    echo "Falta XcodeGen y no encontré Homebrew."
    echo "Instala Homebrew (https://brew.sh) y luego: brew install xcodegen"
    exit 1
  fi
fi
xcodegen --version

echo "==> Generando Octava.xcodeproj"
xcodegen generate

if [ ! -d .git ]; then
  echo "==> Inicializando repositorio git"
  git init -q -b main
  git add -A
  git commit -q -m "Fase 0: esqueleto de Octava" || true
fi

echo
echo "Listo. Abre el proyecto con:  open Octava.xcodeproj"
echo "O compila desde la terminal:  xcodebuild -project Octava.xcodeproj -scheme Octava -configuration Debug build"
