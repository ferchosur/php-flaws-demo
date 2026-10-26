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
  php-flaws-demo/php-test-site:8.3.26
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
kubectl --context "$CONTEXT" apply -k "$ROOT/k8s/labs/php-test-site"

# Local tags may now refer to rebuilt images while existing pods still use the
# previous content. Restart only lab Deployments whose running container differs
# from the freshly loaded tag.
#
# Compare config ids read from the node's containerd, not docker image IDs: once
# `kind load` imports an image, containerd records it under a synthetic
# `import-<date>@<manifest-digest>` repoDigest that never equals `docker image
# inspect --format {{.Id}}`, and the kubelet reports the first of several such
# repoDigests. The image *config id* (`crictl inspecti .status.id` for the tag,
# `crictl ps` imageRef for the running container) is stable and comparable.
NODE="${CLUSTER}-control-plane"
node_tag_config_id() {
  docker exec "$NODE" crictl inspecti "$1" 2>/dev/null \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["status"]["id"])' 2>/dev/null || true
}
running_container_config_id() {
  local namespace="$1" deployment="$2"
  docker exec "$NODE" crictl ps -o json 2>/dev/null | python3 -c '
import sys, json
ns, dep = sys.argv[1], sys.argv[2]
d = json.load(sys.stdin)
print(next((c["imageRef"] for c in d["containers"]
            if c["labels"].get("io.kubernetes.pod.namespace") == ns
            and c["labels"].get("io.kubernetes.pod.name", "").startswith(dep)), ""))
' "$namespace" "$deployment" 2>/dev/null || true
}
restart_if_image_changed() {
  local namespace="$1" deployment="$2" image="$3"
  local tag_cfg run_cfg
  tag_cfg="$(node_tag_config_id "$image")"
  run_cfg="$(running_container_config_id "$namespace" "$deployment")"
  if [[ -z "$tag_cfg" || "$run_cfg" != "$tag_cfg" ]]; then
    echo "== Refresh $namespace/$deployment to the rebuilt local image =="
    kubectl --context "$CONTEXT" -n "$namespace" rollout restart "deployment/$deployment"
  fi
}
restart_if_image_changed lab-cve-109619 vuln-php-apache-target php-flaws-demo/cve-109619-vuln:8.4.26
restart_if_image_changed lab-php2shell php2shell-php-apache-target php-flaws-demo/php2shell-reference:8.4.26
restart_if_image_changed lab-php-test-site php-test-site php-flaws-demo/php-test-site:8.3.26

kubectl --context "$CONTEXT" -n lab-cve-109619 rollout status deployment/vuln-php-apache-target --timeout=180s
kubectl --context "$CONTEXT" -n lab-php2shell rollout status deployment/php2shell-php-apache-target --timeout=180s
kubectl --context "$CONTEXT" -n lab-php-test-site rollout status deployment/php-test-site --timeout=180s
"$ROOT/scripts/verify-kind-labs.sh"
"$ROOT/scripts/start-kind-port-forwards.sh"
