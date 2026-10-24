#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT="${KUBE_CONTEXT:-kind-php-flaws-demo}"
NAMESPACE="${KUBE_NAMESPACE:-php-flaws-demo}"
ENVIRONMENT="${1:-kind}"

case "$ENVIRONMENT" in
  kind)
    kubectl --context "$CONTEXT" -n "$NAMESPACE" rollout status deployment/php-flaws-demo --timeout=30s
    curl --noproxy '*' --fail --silent --show-error http://127.0.0.1:8080/healthz
    ;;
  cve619)
    python3 "$ROOT/scripts/check_runtime.py" http://127.0.0.1:18088 8.4.26 apache2handler
    ;;
  php2shell-reference)
    python3 "$ROOT/scripts/check_runtime.py" http://127.0.0.1:18098 8.4.26 apache2handler
    ;;
  *)
    echo "usage: $0 [kind|cve619|php2shell-reference]" >&2
    exit 2
    ;;
esac
