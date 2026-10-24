#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT="${KUBE_CONTEXT:-kind-php-flaws-demo}"
STATE_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/php-flaws-demo-kind-port-forward"
PID_FILE="$STATE_DIR/port-forwards.pids"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
umask 077

FORWARDS=(
  'lab-cve-109619 vuln-php-apache-target 8081 8.4.26'
  'lab-php2shell php2shell-php-apache-target 8083 8.4.26'
)

if [[ -f "$PID_FILE" ]]; then
  ACTIVE=0
  while read -r PID NS SERVICE PORT VERSION; do
    [[ -n "${PID:-}" ]] || continue
    CMD="$(ps -p "$PID" -o args= 2>/dev/null || true)"
    if [[ "$CMD" == *"port-forward --address 127.0.0.1 svc/$SERVICE $PORT:8080"* ]]; then
      ACTIVE=$((ACTIVE + 1))
    fi
  done <"$PID_FILE"
  if [[ "$ACTIVE" == 3 ]]; then
    echo "All lab port-forwards are already running."
    exit 0
  fi
  echo "A partial/stale port-forward set exists. Run scripts/stop-kind-port-forwards.sh, then start again." >&2
  exit 1
fi

[[ "$(kubectl config current-context)" == "$CONTEXT" ]] || {
  echo "FAIL current kubectl context is not $CONTEXT" >&2
  exit 1
}

kubectl --context "$CONTEXT" -n lab-cve-109619 rollout status deployment/vuln-php-apache-target --timeout=30s >/dev/null
kubectl --context "$CONTEXT" -n lab-php2shell rollout status deployment/php2shell-php-apache-target --timeout=30s >/dev/null

for ITEM in "${FORWARDS[@]}"; do
  read -r NS SERVICE PORT VERSION <<<"$ITEM"
  # Detach from this launcher so closing its shell does not kill the forwards.
  nohup setsid kubectl --context "$CONTEXT" -n "$NS" port-forward --address 127.0.0.1 "svc/$SERVICE" "$PORT:8080" \
    >"$STATE_DIR/$SERVICE.log" 2>&1 </dev/null &
  PID="$!"
  printf '%s %s %s %s %s\n' "$PID" "$NS" "$SERVICE" "$PORT" "$VERSION" >>"$PID_FILE"
done

for ITEM in "${FORWARDS[@]}"; do
  read -r _NS SERVICE PORT VERSION <<<"$ITEM"
  READY=0
  for _ in {1..20}; do
    if curl --noproxy '*' --fail --silent "http://127.0.0.1:$PORT/healthz.php" >/dev/null 2>&1; then
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
    "$ROOT/scripts/stop-kind-port-forwards.sh" || true
    exit 1
  fi
  python3 "$ROOT/scripts/check_runtime.py" "http://127.0.0.1:$PORT" "$VERSION" apache2handler
done

echo "Started all three forwards in the background; no terminal needs to stay open."
echo "Vulnerable 8.4.26: http://localhost:8081/"
echo "PHP2Shell ref:     http://localhost:8083/"
echo "Stop them with:    $ROOT/scripts/stop-kind-port-forwards.sh"
