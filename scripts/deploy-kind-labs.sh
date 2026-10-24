#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT="${KUBE_CONTEXT:-kind-php-flaws-demo}"
CLUSTER="${KIND_CLUSTER:-php-flaws-demo}"

[[ "$(kubectl config current-context)" == "$CONTEXT" ]] || {
  echo "FAIL current kubectl context is not $CONTEXT" >&2
  exit 1
}
kind get clusters | grep -Fxq "$CLUSTER" || {
  echo "FAIL Kind cluster $CLUSTER does not exist; this script never creates it" >&2
  exit 1
}
"$ROOT/scripts/healthcheck.sh" kind >/dev/null

IMAGES=(
  php-flaws-demo/cve-109619-vuln:8.4.26
  php-flaws-demo/php2shell-reference:8.4.26
)
for IMAGE in "${IMAGES[@]}"; do
  docker image inspect "$IMAGE" >/dev/null || {
    echo "FAIL missing local image $IMAGE; build it using the existing Compose lab first" >&2
    exit 1
  }
done

echo "== Load the already-built images into the existing Kind node =="
kind load docker-image --name "$CLUSTER" "${IMAGES[@]}"
echo "== Create the new namespaces and workloads only =="
kubectl --context "$CONTEXT" apply -f "$ROOT/k8s/labs/00-namespaces.yaml"
kubectl --context "$CONTEXT" apply -k "$ROOT/k8s/labs/cve-109619/vulnerable"
kubectl --context "$CONTEXT" apply -f "$ROOT/k8s/labs/cve-109619/vulnerable/service.yaml"
kubectl --context "$CONTEXT" apply -k "$ROOT/k8s/labs/php2shell-reference"
kubectl --context "$CONTEXT" apply -f "$ROOT/k8s/labs/php2shell-reference/service.yaml"

# Local tags may now refer to rebuilt images while existing pods still use the
# previous image ID. Restart only lab Deployments whose loaded image changed.
restart_if_image_changed() {
  local namespace="$1" deployment="$2" version="$3" image="$4"
  local pod expected running
  pod="$(kubectl --context "$CONTEXT" -n "$namespace" get pods -l "lab.php-flaws-demo/php-version=$version" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "$pod" ]] || return 0
  expected="$(docker image inspect "$image" --format '{{.Id}}')"
  running="$(kubectl --context "$CONTEXT" -n "$namespace" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].imageID}' 2>/dev/null || true)"
  if [[ "${running##*@}" != "$expected" ]]; then
    echo "== Refresh $namespace/$deployment to the rebuilt local image =="
    kubectl --context "$CONTEXT" -n "$namespace" rollout restart "deployment/$deployment"
  fi
}
restart_if_image_changed lab-cve-109619 vuln-php-apache-target 8.4.26 php-flaws-demo/cve-109619-vuln:8.4.26
restart_if_image_changed lab-php2shell php2shell-php-apache-target 8.4.26 php-flaws-demo/php2shell-reference:8.4.26

kubectl --context "$CONTEXT" -n lab-cve-109619 rollout status deployment/vuln-php-apache-target --timeout=180s
kubectl --context "$CONTEXT" -n lab-php2shell rollout status deployment/php2shell-php-apache-target --timeout=180s
"$ROOT/scripts/verify-kind-labs.sh"
"$ROOT/scripts/start-kind-port-forwards.sh"
