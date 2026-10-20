#!/bin/bash
# Ejecutor de compilación para trabajar con Claude a distancia.
# Se abre con doble clic. Queda esperando: cada vez que aparece build-logs/request,
# ejecuta el comando pedido (bootstrap | generate | build | test | all | env | gitstatus | gitcommit | run | kill | sample | script)
# y deja la salida en build-logs/.
# Se cierra solo tras 24 horas sin pedidos, o al crear build-logs/stop.
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
LOGS="$ROOT/build-logs"
mkdir -p "$LOGS"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
echo "Octava · ejecutor de compilación activo en $ROOT"
echo "Esperando pedidos… (cierra esta ventana para detenerlo)"
echo "ready $(date +%s)" > "$LOGS/runner-status"
idle=0
while true; do
  if [ -f "$LOGS/stop" ]; then rm -f "$LOGS/stop"; echo "stopped" > "$LOGS/runner-status"; exit 0; fi
  if [ -f "$LOGS/request" ]; then
    CMD="$(cat "$LOGS/request" | tr -d '[:space:]')"
    rm -f "$LOGS/request"
    idle=0
    echo "busy $CMD $(date +%s)" > "$LOGS/runner-status"
    echo "==> $(date '+%H:%M:%S') ejecutando: $CMD"
    {
      echo "### comando: $CMD  ($(date))"
      case "$CMD" in
        bootstrap) bash ./bootstrap.sh ;;
        generate)  xcodegen generate ;;
        build)     xcodebuild -project Octava.xcodeproj -scheme Octava -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build ;;
        test)      xcodebuild -project Octava.xcodeproj -scheme Octava -destination 'platform=macOS' -derivedDataPath build/DerivedData test ;;
        all)       xcodegen generate && xcodebuild -project Octava.xcodeproj -scheme Octava -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build && xcodebuild -project Octava.xcodeproj -scheme Octava -destination 'platform=macOS' -derivedDataPath build/DerivedData test ;;
        env)       sw_vers; xcodebuild -version; xcode-select -p; which brew xcodegen git; swift --version ;;
        gitcommit) git add -A && git commit -m "$(cat "$LOGS/commit-message" 2>/dev/null || echo 'Actualiza Octava')" ;;
        gitstatus) git status; git log --oneline -5 ;;
        run)       pkill -x Octava; sleep 1
                   APP="$ROOT/build/DerivedData/Build/Products/Debug/Octava.app/Contents/MacOS/Octava"
                   nohup "$APP" > "$LOGS/app.log" 2>&1 &
                   echo "app lanzada (pid $!), salida en build-logs/app.log" ;;
        kill)      pkill -x Octava; echo "app cerrada" ;;
        sample)    sample Octava 3 -mayDie 2>&1 | head -150 ;;
        script)    bash "$LOGS/script.sh" ;;
        *) echo "comando desconocido: $CMD" ;;
      esac
      echo "### exit: $?"
    } > "$LOGS/latest.log" 2>&1
    echo "done $CMD $(date +%s) $(tail -1 "$LOGS/latest.log")" > "$LOGS/runner-status"
    echo "    terminado: $(tail -1 "$LOGS/latest.log")"
  fi
  sleep 2
  idle=$((idle+2))
  if [ $idle -ge 86400 ]; then echo "stopped (idle)" > "$LOGS/runner-status"; exit 0; fi
done
