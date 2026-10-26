#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== Build or reuse the pinned PHP lab images =="
docker compose -f "$ROOT/labs/cve-2026-109619/docker-compose.yml" build
docker compose -f "$ROOT/labs/php2shell-reference/docker-compose.yml" build
docker compose -f "$ROOT/labs/php-test-site/docker-compose.yml" build

echo "== Load, deploy, verify, and start localhost access =="
"$ROOT/scripts/deploy-kind-labs.sh"
