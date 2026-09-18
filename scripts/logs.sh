#!/bin/bash
# Starea MediaFlow Monitor pe stația locală (Regula 39), într-un singur loc: procesul,
# fișierul de log al aplicației și unified log-ul ei (subsistemul com.gdc.mediaflowmonitor).
#
# Utilizare:
#   scripts/logs.sh            instantaneu: proces + ultimele evenimente (15 min)
#   scripts/logs.sh 60         la fel, pe ultimele 60 de minute
#   scripts/logs.sh --follow   urmărire live a fișierului de log
set -uo pipefail

LOG_FILE="$HOME/Library/Logs/MediaFlowMonitor.log"
SUBSYSTEM="com.gdc.mediaflowmonitor"

if [ "${1:-}" = "--follow" ]; then
  echo "→ Urmăresc ${LOG_FILE} (Ctrl+C pentru oprire)…"
  touch "$LOG_FILE"
  exec tail -n 20 -F "$LOG_FILE"
fi

MINUTES="${1:-15}"

echo "=== Proces"
pgrep -lf "MediaFlowMonitor.app/Contents/MacOS" | sed 's/^/  /' || echo "  aplicația NU rulează"

echo "=== ${LOG_FILE} — ultimele 40 de linii"
if [ -f "$LOG_FILE" ]; then
  tail -n 40 "$LOG_FILE" | sed 's/^/  /'
else
  echo "  nu există încă (se creează la primul eveniment al unei versiuni ≥ 1.10.1)"
fi

echo "=== Unified log (${SUBSYSTEM}) — ultimele ${MINUTES} min"
/usr/bin/log show --last "${MINUTES}m" --style compact --predicate "subsystem == \"${SUBSYSTEM}\"" 2>/dev/null \
  | grep -v "^Timestamp" | tail -n 30 | sed 's/^/  /'

echo
echo "Live: scripts/logs.sh --follow · detaliat: defaults write ${SUBSYSTEM} MediaFlowMonitor.verboseLog -bool true"
