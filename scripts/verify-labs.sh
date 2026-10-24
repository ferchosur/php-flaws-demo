#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
KUBE_CONTEXT="${KUBE_CONTEXT:-kind-php-flaws-demo}"
KUBE_NAMESPACE="${KUBE_NAMESPACE:-php-flaws-demo}"
B_COMPOSE="$ROOT/labs/cve-2026-109619/docker-compose.yml"
C_COMPOSE="$ROOT/labs/php2shell-reference/docker-compose.yml"
B_PROJECT=php-flaws-demo-cve619
C_PROJECT=php-flaws-demo-php2shell-reference
cleanup() {
  docker compose -p "$B_PROJECT" -f "$B_COMPOSE" down --remove-orphans >/dev/null 2>&1 || true
  docker compose -p "$C_PROJECT" -f "$C_COMPOSE" down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "== Existing Kind environment (read-only) =="
kubectl --context "$KUBE_CONTEXT" -n "$KUBE_NAMESPACE" rollout status deployment/php-flaws-demo --timeout=30s
POD="$(kubectl --context "$KUBE_CONTEXT" -n "$KUBE_NAMESPACE" get pods -l app=php-flaws-demo -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$POD" ]] || { echo "FAIL application pod not found"; exit 1; }
[[ "$(kubectl --context "$KUBE_CONTEXT" -n "$KUBE_NAMESPACE" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}')" == true ]] || { echo "FAIL existing pod not Ready"; exit 1; }
[[ "$(kubectl --context "$KUBE_CONTEXT" -n "$KUBE_NAMESPACE" get deployment php-flaws-demo -o jsonpath='{.spec.template.spec.containers[0].image}')" == php-flaws-demo:local ]] || { echo "FAIL existing image reference changed"; exit 1; }
IMAGE_ID="$(docker image inspect php-flaws-demo:local --format '{{.Id}}')"
RUNNING_ID="$(kubectl --context "$KUBE_CONTEXT" -n "$KUBE_NAMESPACE" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].imageID}')"
[[ "${RUNNING_ID##*@}" == "$IMAGE_ID" || "${RUNNING_ID#docker://}" == "$IMAGE_ID" ]] || { echo "FAIL deployed image ID differs from local image"; exit 1; }
PHP_VERSION="$(kubectl --context "$KUBE_CONTEXT" -n "$KUBE_NAMESPACE" exec "$POD" -- php -r 'echo PHP_VERSION;')"
[[ "$PHP_VERSION" == 8.5.11 ]] || { echo "FAIL original Kind PHP version: $PHP_VERSION"; exit 1; }
[[ "$(kubectl --context "$KUBE_CONTEXT" -n "$KUBE_NAMESPACE" exec "$POD" -- php -r 'echo PHP_SAPI;')" == cli ]] || { echo "FAIL original server SAPI is not CLI"; exit 1; }
[[ "$(curl --noproxy '*' --fail --silent --show-error -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/healthz)" == 200 ]] || { echo "FAIL original Kind HTTP health"; exit 1; }
echo "PASS original Kind pod, image ID, PHP 8.5.11 CLI server and localhost health remain available"

echo "== Static Compose/isolation checks =="
python3 "$ROOT/scripts/validate_compose.py" cve619
python3 "$ROOT/scripts/validate_compose.py" php2shell-reference

echo "== Start isolated non-exploit targets =="
docker compose -p "$B_PROJECT" -f "$B_COMPOSE" up --build --detach --wait
docker compose -p "$C_PROJECT" -f "$C_COMPOSE" up --build --detach --wait
python3 "$ROOT/scripts/check_runtime.py" http://127.0.0.1:18088 8.4.26 apache2handler
python3 "$ROOT/scripts/check_runtime.py" http://127.0.0.1:18098 8.4.26 apache2handler
[[ "$(docker network inspect php-flaws-demo-cve619-net --format '{{index .Options "com.docker.network.bridge.enable_ip_masquerade"}}')" == false ]] || { echo "FAIL B bridge egress masquerading is enabled"; exit 1; }
[[ "$(docker network inspect php-flaws-demo-php2shell-net --format '{{index .Options "com.docker.network.bridge.enable_ip_masquerade"}}')" == false ]] || { echo "FAIL C bridge egress masquerading is enabled"; exit 1; }
[[ "$(docker network inspect php-flaws-demo-cve619-net --format '{{index .Options "com.docker.network.bridge.enable_icc"}}')" == false ]] || { echo "FAIL B inter-container connectivity is enabled"; exit 1; }
[[ "$(docker network inspect php-flaws-demo-php2shell-net --format '{{index .Options "com.docker.network.bridge.enable_icc"}}')" == false ]] || { echo "FAIL C inter-container connectivity is enabled"; exit 1; }
[[ "$(docker network inspect php-flaws-demo-cve619-net --format '{{.Id}}')" != "$(docker network inspect php-flaws-demo-php2shell-net --format '{{.Id}}')" ]] || { echo "FAIL B and C share a network"; exit 1; }
echo "PASS B and C targets are healthy, versioned, loopback-only, non-root, and network-isolated"
echo "No PoC or exploit request was executed."
