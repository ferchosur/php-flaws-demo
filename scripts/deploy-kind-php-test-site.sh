#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT="${KUBE_CONTEXT:-kind-php-flaws-demo}"
CLUSTER="${KIND_CLUSTER:-php-flaws-demo}"
IMAGE=php-flaws-demo/php-test-site:8.3.26

[[ "$(kubectl config current-context)" == "$CONTEXT" ]] || {
  echo "FAIL current kubectl context is not $CONTEXT" >&2
  exit 1
}
kind get clusters | grep -Fxq "$CLUSTER" || {
  echo "FAIL Kind cluster $CLUSTER does not exist; this script never creates it" >&2
  exit 1
}
"$ROOT/scripts/healthcheck.sh" kind >/dev/null

echo "== Build the PHP 8.3.26 scanner target =="
docker compose -f "$ROOT/labs/php-test-site/docker-compose.yml" build
echo "== Load the D image into the existing Kind node =="
kind load docker-image --name "$CLUSTER" "$IMAGE"
echo "== Apply resources only to lab-php-test-site =="
kubectl --context "$CONTEXT" apply -f "$ROOT/k8s/labs/php-test-site/namespace.yaml"
kubectl --context "$CONTEXT" apply -k "$ROOT/k8s/labs/php-test-site"
kubectl --context "$CONTEXT" -n lab-php-test-site rollout restart deployment/php-test-site
kubectl --context "$CONTEXT" -n lab-php-test-site rollout status deployment/php-test-site --timeout=180s

echo "== Verify the deployed page and PHP version =="
kubectl --context "$CONTEXT" -n lab-php-test-site port-forward --address 127.0.0.1 service/php-test-site 28082:8080 >/dev/null 2>&1 &
PF_PID="$!"
cleanup() { kill "$PF_PID" 2>/dev/null || true; }
trap cleanup EXIT
READY=0
for _ in {1..30}; do
  if curl --noproxy '*' --fail --silent http://127.0.0.1:28082/ >/dev/null 2>&1; then READY=1; break; fi
  sleep 1
done
[[ "$READY" == 1 ]] || { echo "FAIL lab D HTTP endpoint did not become ready" >&2; exit 1; }
python3 "$ROOT/scripts/check_php_test_site.py" http://127.0.0.1:28082 8.3.26
"$ROOT/scripts/start-kind-port-forwards.sh" php-test-site
