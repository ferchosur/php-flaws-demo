# Troubleshooting

Run all commands from Ubuntu WSL in the repository root. They use the explicit Kind context and lab-specific Compose project names.

## Existing Kind app

~~~bash
kubectl --context kind-php-flaws-demo -n php-flaws-demo get pods,deploy,svc -o wide
./scripts/healthcheck.sh kind
./scripts/inventory.sh kind
./scripts/collect-diagnostics.sh kind
~~~

If kubectl cannot connect, check kubectl config current-context; this procedure must use kind-php-flaws-demo, not a cloud context. If port 8080 is unavailable, inspect local-cluster/kind-config.yaml and the existing NodePort Service. Do not recreate the cluster as a diagnostic step.

## Compose targets do not start

~~~bash
docker info
docker compose -f labs/cve-2026-109619/docker-compose.yml config
docker compose -f labs/cve-2026-109619/docker-compose.yml ps -a
docker compose -f labs/cve-2026-109619/docker-compose.yml logs --tail=100
~~~

Both target builds are pinned to AMD64 official PHP Apache image digests. On an ARM-only Docker host, provide amd64 emulation rather than changing heap/build assumptions. Docker pulls may fail if WSL cannot use the host proxy; do not replace digest pins with mutable tags.

The Apache target intentionally runs as UID 33, listens on unprivileged container port 8080, and writes runtime data to bounded tmpfs mounts. Its dedicated bridge disables inter-container links and IP masquerading. This cuts ordinary NAT-based outbound access but does not guarantee isolation from host or directly routed LAN addresses. If Apache reports a permission or PID-file error, inspect its tmpfs mounts; do not switch to privileged mode or add capabilities as a workaround.

## Port conflicts

Check 18088 and 18098 before starting the new labs. Stop only the corresponding vulnerable lab project:

~~~bash
docker compose -f labs/cve-2026-109619/docker-compose.yml down
docker compose -f labs/php2shell-reference/docker-compose.yml down
~~~

These commands do not remove images or volumes and do not affect Kind. Do not use docker system prune, kind delete cluster, or kubectl delete namespace as troubleshooting.

## Rebuilt image does not reach the pod

`deploy-kind-labs.sh` and `verify-kind-labs.sh` check image freshness with the
image *config id* read from the node's containerd (`crictl inspecti <tag>` for
the loaded tag, `crictl ps` imageRef for the running container), not the Docker
image ID. Reason: `kind load docker-image` imports each tag under a synthetic
`docker.io/library/import-<date>@<manifest-digest>` repoDigest that never equals
`docker image inspect --format {{.Id}}`, and the kubelet reports the first of
several accumulated repoDigests — so a Docker-ID comparison gives false
mismatches. The lab Compose builds set `provenance: false` and `sbom: false` so
BuildKit produces a plain single-manifest image (attestations would add a
manifest list, compounding the divergence). If a rebuild still seems stale,
confirm the two config ids match:

~~~bash
NODE=php-flaws-demo-control-plane
docker exec "$NODE" crictl inspecti php-flaws-demo/cve-109619-vuln:8.4.26 \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["status"]["id"])'
docker exec "$NODE" crictl ps -o json \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print([c["imageRef"] for c in d["containers"] if c["labels"].get("io.kubernetes.pod.namespace")=="lab-cve-109619"])'
~~~

## Diagnostics

Diagnostics are written to a local directory with restrictive permissions. Review/redact logs before sharing them:

~~~bash
./scripts/collect-diagnostics.sh cve619
./scripts/collect-diagnostics.sh php2shell-reference
~~~
