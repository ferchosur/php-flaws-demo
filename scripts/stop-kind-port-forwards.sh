#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/php-flaws-demo-kind-port-forward"
PID_FILE="$STATE_DIR/port-forwards.pids"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No managed lab port-forwards are running."
  exit 0
fi

STOPPED=0
while read -r PID _NS SERVICE PORT _VERSION; do
  [[ -n "${PID:-}" ]] || continue
  CMD="$(ps -p "$PID" -o args= 2>/dev/null || true)"
  if [[ "$CMD" == *"port-forward --address 127.0.0.1 svc/$SERVICE $PORT:8080"* ]]; then
    kill "$PID" 2>/dev/null || true
    STOPPED=$((STOPPED + 1))
  fi
done <"$PID_FILE"
rm -f -- "$PID_FILE"
echo "Stopped $STOPPED managed lab port-forward process(es). Lab Pods and Services remain running."
echo "Logs remain under $STATE_DIR."
