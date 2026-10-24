#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT="${KUBE_CONTEXT:-kind-php-flaws-demo}"
NAMESPACE="${KUBE_NAMESPACE:-php-flaws-demo}"
ENVIRONMENT="${1:-kind}"
printf 'captured_at_utc=%s\nenvironment=%s\n' "$(date -u +%FT%TZ)" "$ENVIRONMENT"

case "$ENVIRONMENT" in
  kind)
    kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods -l app=php-flaws-demo \
      -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[0].ready,IMAGE:.spec.containers[0].image,IMAGE_ID:.status.containerStatuses[0].imageID,NODE:.spec.nodeName'
    POD="$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods -l app=php-flaws-demo -o jsonpath='{.items[0].metadata.name}')"
    IMAGE="$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get deployment php-flaws-demo -o jsonpath='{.spec.template.spec.containers[0].image}')"
    printf '\n--- local image ---\n'
    docker image inspect "$IMAGE" --format='id={{.Id}} repo_digests={{json .RepoDigests}}' || true
    printf '\n--- base operating system ---\n'
    kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- cat /etc/os-release
    printf '\n--- server process ---\n'
    kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- sh -c 'tr "\000" " " </proc/1/cmdline; echo'
    printf '\n--- PHP CLI SAPI (also serves the built-in web server) ---\n'
    kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- php -v
    kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- php -i \
      | grep -E '^(Server API|Loaded Configuration File|memory_limit|session.upload_progress.enabled|disable_functions|display_errors|display_startup_errors|error_reporting) =>'
    kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- php -m
    ;;
  cve619|php2shell-reference)
    if [[ "$ENVIRONMENT" == cve619 ]]; then
      COMPOSE="$ROOT/labs/cve-2026-109619/docker-compose.yml"
      PROJECT=php-flaws-demo-cve619
      SERVICES=(vuln)
    else
      COMPOSE="$ROOT/labs/php2shell-reference/docker-compose.yml"
      PROJECT=php-flaws-demo-php2shell-reference
      SERVICES=(target)
    fi
    for SERVICE in "${SERVICES[@]}"; do
      ID="$(docker compose -p "$PROJECT" -f "$COMPOSE" ps -q "$SERVICE")"
      printf '\n--- %s / %s ---\n' "$ENVIRONMENT" "$SERVICE"
      docker inspect "$ID" --format='image={{.Config.Image}} image_id={{.Image}} user={{.Config.User}} ports={{json .NetworkSettings.Ports}}'
      docker compose -p "$PROJECT" -f "$COMPOSE" exec -T "$SERVICE" cat /etc/os-release
      docker compose -p "$PROJECT" -f "$COMPOSE" exec -T "$SERVICE" php --ini
      docker compose -p "$PROJECT" -f "$COMPOSE" exec -T "$SERVICE" php -i \
        | grep -E '^(Server API|Loaded Configuration File|memory_limit|session.upload_progress.enabled|disable_functions|display_errors|display_startup_errors|error_reporting) =>'
      docker compose -p "$PROJECT" -f "$COMPOSE" exec -T "$SERVICE" php -m
      HOST_PORT="$(docker inspect "$ID" --format='{{(index (index .NetworkSettings.Ports "8080/tcp") 0).HostPort}}')"
      curl --noproxy '*' --fail --silent --show-error "http://127.0.0.1:$HOST_PORT/__lab_runtime.php" | python3 -m json.tool
    done
    ;;
  *)
    echo "usage: $0 [kind|cve619|php2shell-reference]" >&2
    exit 2
    ;;
esac
