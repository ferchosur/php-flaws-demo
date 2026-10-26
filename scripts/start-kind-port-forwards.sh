#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT="${KUBE_CONTEXT:-kind-php-flaws-demo}"
STATE_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/php-flaws-demo-kind-port-forward"
PID_FILE="$STATE_DIR/port-forwards.pids"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
umask 077

ALL_FORWARDS=(
  'lab-cve-109619 vuln-php-apache-target 8081 8.4.26'
  'lab-php2shell php2shell-php-apache-target 8083 8.4.26'
  'lab-php-test-site php-test-site 8082 8.3.26'
)
if [[ "${1:-all}" == php-test-site ]]; then
  FORWARDS=('lab-php-test-site php-test-site 8082 8.3.26')
elif [[ "${1:-all}" == all ]]; then
  FORWARDS=("${ALL_FORWARDS[@]}")
else
  echo "Usage: $0 [all|php-test-site]" >&2
  exit 2
fi

ACTIVE_FORWARDS=()
if [[ -f "$PID_FILE" ]]; then
  while read -r PID NS SERVICE PORT VERSION; do
    [[ -n "${PID:-}" ]] || continue
    CMD="$(ps -p "$PID" -o args= 2>/dev/null || true)"
    if [[ "$CMD" == *"port-forward --address 127.0.0.1 svc/$SERVICE $PORT:8080"* ]]; then
      ACTIVE_FORWARDS+=("$PID $NS $SERVICE $PORT $VERSION")
    fi
  done <"$PID_FILE"
fi

# Discard stale PID records, while preserving managed forwards that are still
# serving other labs when this script is asked to start just one environment.
: >"$PID_FILE"
for ENTRY in "${ACTIVE_FORWARDS[@]}"; do
  printf '%s\n' "$ENTRY" >>"$PID_FILE"
done

is_active() {
  local wanted_ns="$1" wanted_service="$2" wanted_port="$3"
  for ENTRY in "${ACTIVE_FORWARDS[@]}"; do
    local entry_pid entry_ns entry_service entry_port entry_version
    read -r entry_pid entry_ns entry_service entry_port entry_version <<<"$ENTRY"
    [[ "$entry_ns" == "$wanted_ns" && "$entry_service" == "$wanted_service" && "$entry_port" == "$wanted_port" ]] && return 0
  done
  return 1
}

REQUESTED_ACTIVE=0
NEW_PIDS=()
for ITEM in "${FORWARDS[@]}"; do
  read -r NS SERVICE PORT _VERSION <<<"$ITEM"
  if is_active "$NS" "$SERVICE" "$PORT"; then REQUESTED_ACTIVE=$((REQUESTED_ACTIVE + 1)); fi
done
if [[ "$REQUESTED_ACTIVE" == "${#FORWARDS[@]}" ]]; then
  echo "All requested lab port-forwards are already running."
  exit 0
fi

[[ "$(kubectl config current-context)" == "$CONTEXT" ]] || {
  echo "FAIL current kubectl context is not $CONTEXT" >&2
  exit 1
}

for ITEM in "${FORWARDS[@]}"; do
  read -r NS SERVICE PORT VERSION <<<"$ITEM"
  if is_active "$NS" "$SERVICE" "$PORT"; then continue; fi
  kubectl --context "$CONTEXT" -n "$NS" rollout status "deployment/$SERVICE" --timeout=30s >/dev/null
  # Detach from this launcher so closing its shell does not kill the forwards.
  nohup setsid kubectl --context "$CONTEXT" -n "$NS" port-forward --address 127.0.0.1 "svc/$SERVICE" "$PORT:8080" \
    >"$STATE_DIR/$SERVICE.log" 2>&1 </dev/null &
  PID="$!"
  printf '%s %s %s %s %s\n' "$PID" "$NS" "$SERVICE" "$PORT" "$VERSION" >>"$PID_FILE"
  ACTIVE_FORWARDS+=("$PID $NS $SERVICE $PORT $VERSION")
  NEW_PIDS+=("$PID")
done

cleanup_new_forwards() {
  local PID TEMP_PID_FILE SKIP NEW_PID
  for NEW_PID in "${NEW_PIDS[@]}"; do kill "$NEW_PID" 2>/dev/null || true; done
  TEMP_PID_FILE="$STATE_DIR/port-forwards.pids.tmp"
  : >"$TEMP_PID_FILE"
  while read -r PID NS SERVICE PORT VERSION; do
    [[ -n "${PID:-}" ]] || continue
    SKIP=0
    for NEW_PID in "${NEW_PIDS[@]}"; do [[ "$PID" == "$NEW_PID" ]] && SKIP=1; done
    [[ "$SKIP" == 1 ]] || printf '%s %s %s %s %s\n' "$PID" "$NS" "$SERVICE" "$PORT" "$VERSION" >>"$TEMP_PID_FILE"
  done <"$PID_FILE"
  mv -- "$TEMP_PID_FILE" "$PID_FILE"
}

for ITEM in "${FORWARDS[@]}"; do
  read -r _NS SERVICE PORT VERSION <<<"$ITEM"
  READY=0
  for _ in {1..20}; do
    HEALTH_PATH=/healthz.php
    [[ "$SERVICE" == php-test-site ]] && HEALTH_PATH=/
    if curl --noproxy '*' --fail --silent "http://127.0.0.1:$PORT$HEALTH_PATH" >/dev/null 2>&1; then
      READY=1
      break
    fi
    PID="$(awk -v service="$SERVICE" '$3 == service {print $1}' "$PID_FILE")"
    if ! kill -0 "$PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  if [[ "$READY" != 1 ]]; then
    echo "FAIL port-forward $SERVICE did not become healthy; see $STATE_DIR/$SERVICE.log" >&2
    cleanup_new_forwards
    exit 1
  fi
  if [[ "$SERVICE" == php-test-site ]]; then
    python3 "$ROOT/scripts/check_php_test_site.py" "http://127.0.0.1:$PORT" "$VERSION" || { cleanup_new_forwards; exit 1; }
  else
    python3 "$ROOT/scripts/check_runtime.py" "http://127.0.0.1:$PORT" "$VERSION" apache2handler || { cleanup_new_forwards; exit 1; }
  fi
done

echo "Started the requested lab forwards in the background; no terminal needs to stay open."
for ITEM in "${FORWARDS[@]}"; do
  read -r _NS SERVICE PORT _VERSION <<<"$ITEM"
  case "$SERVICE" in
    vuln-php-apache-target) echo "Vulnerable 8.4.26: http://localhost:$PORT/" ;;
    php-test-site) echo "PHP scanner site:  http://localhost:$PORT/" ;;
    php2shell-php-apache-target) echo "PHP2Shell ref:     http://localhost:$PORT/" ;;
  esac
done
echo "Stop them with:    $ROOT/scripts/stop-kind-port-forwards.sh"
