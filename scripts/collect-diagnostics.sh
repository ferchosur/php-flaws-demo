#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${1:-kind}"
OUT="${2:-${TMPDIR:-/tmp}/php-flaws-demo-diagnostics-$(date -u +%Y%m%dT%H%M%SZ)}"
umask 077
mkdir -p "$OUT"
printf 'environment=%s\ncaptured_at_utc=%s\n' "$ENVIRONMENT" "$(date -u +%FT%TZ)" >"$OUT/metadata.txt"

case "$ENVIRONMENT" in
  kind)
    CONTEXT="${KUBE_CONTEXT:-kind-php-flaws-demo}"
    NAMESPACE="${KUBE_NAMESPACE:-php-flaws-demo}"
    kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods,deploy,svc -o wide >"$OUT/resources.txt"
    kubectl --context "$CONTEXT" -n "$NAMESPACE" describe deployment php-flaws-demo >"$OUT/deployment.txt"
    POD="$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods -l app=php-flaws-demo -o jsonpath='{.items[0].metadata.name}')"
    kubectl --context "$CONTEXT" -n "$NAMESPACE" logs "$POD" --tail=100 >"$OUT/app.log" 2>&1 || true
    ;;
  cve619)
    docker compose -p php-flaws-demo-cve619 -f "$ROOT/labs/cve-2026-109619/docker-compose.yml" ps -a >"$OUT/resources.txt"
    docker compose -p php-flaws-demo-cve619 -f "$ROOT/labs/cve-2026-109619/docker-compose.yml" logs --no-color --tail=100 >"$OUT/services.log" 2>&1 || true
    ;;
  php2shell-reference)
    docker compose -p php-flaws-demo-php2shell-reference -f "$ROOT/labs/php2shell-reference/docker-compose.yml" ps -a >"$OUT/resources.txt"
    docker compose -p php-flaws-demo-php2shell-reference -f "$ROOT/labs/php2shell-reference/docker-compose.yml" logs --no-color --tail=100 >"$OUT/services.log" 2>&1 || true
    ;;
  *)
    echo "usage: $0 [kind|cve619|php2shell-reference] [output-directory]" >&2
    exit 2
    ;;
esac
printf 'Diagnostics written to %s\n' "$OUT"
