#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT="${KUBE_CONTEXT:-kind-php-flaws-demo}"
PF_PIDS=()
cleanup() {
  for PID in "${PF_PIDS[@]:-}"; do
    kill "$PID" 2>/dev/null || true
  done
}
trap cleanup EXIT

echo "== Preserve and verify the existing A environment =="
"$ROOT/scripts/healthcheck.sh" kind
[[ "$(kubectl --context "$CONTEXT" -n php-flaws-demo get deployment php-flaws-demo -o jsonpath='{.spec.template.spec.containers[0].image}')" == php-flaws-demo:local ]]
[[ "$(kubectl --context "$CONTEXT" -n php-flaws-demo get svc php-flaws-demo -o jsonpath='{.spec.ports[0].nodePort}')" == 30080 ]]
POD_A="$(kubectl --context "$CONTEXT" -n php-flaws-demo get pods -l app=php-flaws-demo -o jsonpath='{.items[0].metadata.name}')"
PHP_A="$(kubectl --context "$CONTEXT" -n php-flaws-demo exec "$POD_A" -- php -r 'echo PHP_VERSION,"/",PHP_SAPI;')"
[[ "$PHP_A" == 8.5.11/cli ]] || { echo "FAIL A runtime changed: $PHP_A"; exit 1; }
echo "PASS A remains on image php-flaws-demo:local, NodePort 30080 and PHP $PHP_A"

echo "== Verify new workloads and actual image references =="
for ITEM in \
  'lab-cve-109619 vuln-php-apache-target php-flaws-demo/cve-109619-vuln:8.4.26 28088 8.4.26' \
  'lab-php2shell php2shell-php-apache-target php-flaws-demo/php2shell-reference:8.4.26 28098 8.4.26'; do
  read -r NS DEPLOY IMAGE HOST_PORT PHP_VERSION <<<"$ITEM"
  kubectl --context "$CONTEXT" -n "$NS" rollout status "deployment/$DEPLOY" --timeout=30s >/dev/null
  SPEC_IMAGE="$(kubectl --context "$CONTEXT" -n "$NS" get deployment "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].image}')"
  [[ "$SPEC_IMAGE" == "$IMAGE" ]] || { echo "FAIL $DEPLOY spec image is $SPEC_IMAGE"; exit 1; }
  POD="$(kubectl --context "$CONTEXT" -n "$NS" get pods -l "lab.php-flaws-demo/php-version=$PHP_VERSION" -o jsonpath='{.items[0].metadata.name}')"
  STATUS_IMAGE="$(kubectl --context "$CONTEXT" -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].image}')"
  [[ "$STATUS_IMAGE" == "$IMAGE" || "$STATUS_IMAGE" == "docker.io/$IMAGE" ]] || { echo "FAIL $DEPLOY running image is $STATUS_IMAGE"; exit 1; }
  LOCAL_IMAGE_ID="$(docker image inspect "$IMAGE" --format '{{.Id}}')"
  RUNNING_IMAGE_ID="$(kubectl --context "$CONTEXT" -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].imageID}')"
  [[ "${RUNNING_IMAGE_ID##*@}" == "$LOCAL_IMAGE_ID" ]] || { echo "FAIL $DEPLOY imageID $RUNNING_IMAGE_ID differs from local $LOCAL_IMAGE_ID"; exit 1; }
  kubectl --context "$CONTEXT" -n "$NS" port-forward --address 127.0.0.1 "service/$DEPLOY" "$HOST_PORT:8080" >/dev/null 2>&1 &
  PF_PIDS+=("$!")
  READY=0
  for _ in {1..20}; do
    if curl --noproxy '*' --fail --silent --show-error "http://127.0.0.1:$HOST_PORT/healthz.php" >/dev/null 2>&1; then READY=1; break; fi
    sleep 1
  done
  [[ "$READY" == 1 ]] || { echo "FAIL HTTP health for $NS/$DEPLOY"; exit 1; }
  python3 "$ROOT/scripts/check_runtime.py" "http://127.0.0.1:$HOST_PORT" "$PHP_VERSION" apache2handler
  echo "PASS $NS/$DEPLOY uses $STATUS_IMAGE at $LOCAL_IMAGE_ID (imagePullPolicy Never)"
done

C_OS="$(kubectl --context "$CONTEXT" -n lab-php2shell exec deployment/php2shell-php-apache-target -- sh -c '. /etc/os-release; echo "$VERSION_CODENAME"')"
C_APACHE="$(kubectl --context "$CONTEXT" -n lab-php2shell exec deployment/php2shell-php-apache-target -- apache2 -v 2>&1 | sed -n 's/^Server version: Apache\/\([^ ]*\).*/\1/p')"
[[ "$C_OS" == bookworm ]] || { echo "FAIL C base OS is $C_OS, expected bookworm"; exit 1; }
if [[ "$C_APACHE" == 2.4.69 ]]; then
  echo "PASS C Apache version matches the eness README (2.4.69)"
else
  echo "BLOCKED C exact eness default profile: README declares Apache 2.4.69; pinned Bookworm image reports $C_APACHE"
fi

echo "== Check namespace traffic separation with a harmless health request =="
VULN_SERVICE_IP="$(kubectl --context "$CONTEXT" -n lab-cve-109619 get svc vuln-php-apache-target -o jsonpath='{.spec.clusterIP}')"
set +e
kubectl --context "$CONTEXT" -n lab-php2shell exec deployment/php2shell-php-apache-target -- php -r '$c=stream_context_create(["http"=>["timeout"=>3]]); $r=@file_get_contents("http://'"$VULN_SERVICE_IP"':8080/healthz.php",false,$c); exit($r === "ok\n" ? 29 : 0);' >/dev/null 2>&1
TRAFFIC_RC=$?
set -e
if [[ "$TRAFFIC_RC" == 29 ]]; then
  echo "FAIL CNI allowed cross-namespace HTTP from C to B; NetworkPolicy isolation is not enforced" >&2
  exit 1
elif [[ "$TRAFFIC_RC" != 0 ]]; then
  echo "FAIL isolation probe did not complete as expected (kubectl rc=$TRAFFIC_RC)" >&2
  exit 1
fi
echo "PASS harmless cross-namespace HTTP from C to B was blocked"

echo "== Final inventory =="
kubectl --context "$CONTEXT" get namespaces lab-cve-109619 lab-php2shell trendmicro-system
kubectl --context "$CONTEXT" -n lab-cve-109619 get pods,svc -o wide
kubectl --context "$CONTEXT" -n lab-php2shell get pods,svc -o wide
echo "No exploit or PoC was run. Port-forward listeners bind only to 127.0.0.1 and are stopped by this script."
