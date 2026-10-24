# PHP Flaws Demo — reproducible local labs

This repository preserves the existing php-flaws-demo application in Kind and adds two target-only comparison environments for CVE-2026-109618 and CVE-2026-109619. B and C can run in the same Kind cluster in separate namespaces; Compose remains available for standalone local reproduction. No exploit is included in or automatically run by these labs.

## Environments

| Environment | Runtime | Access | Purpose |
|---|---|---|---|
| A — existing Kind app | PHP 8.5.11, built-in PHP web server (cli SAPI), php-flaws-demo:local | http://127.0.0.1:8080 | Preserved Worst Market application and baseline observation |
| B — CVE-2026-109619 | Namespace `lab-cve-109619`; vulnerable PHP 8.4.26 Apache/mod_php | http://127.0.0.1:8081 | cozybear-dev vulnerable target profile only |
| C — combined php2shell reference | Namespace `lab-php2shell`; PHP 8.4.26 Bookworm Apache/mod_php profile | http://127.0.0.1:8083 | Independent reference profile for the PoC's documented CVEs |

Environment A retains Worst Market. B and C use minimal `OK` PHP targets so their runtime configurations remain tied to their respective reference projects. B and C are independent vulnerable-only labs; this phase has no corrected-version workload or remediation comparison. TrendAI Container Security is a separate future activity.

See docs/architecture.md, docs/kind-lab-deployment.md, docs/compatibility-matrix.md, docs/trendai-container-security.md, and docs/troubleshooting.md.

## Requirements

- Ubuntu under WSL2 (or another Linux environment) with Docker Engine and the Compose plugin.
- kubectl, Kind, and the existing kind-php-flaws-demo context for environment A.
- Python 3 for the helper scripts.
- AMD64 Docker image support for B and C. Their official PHP base image digests and platform are pinned to the upstream reference's linux/amd64 profile.

Kind workloads use separate namespaces, ClusterIP-only Services, declared NetworkPolicies, UID 33, dropped capabilities, read-only root filesystems, bounded memory/CPU, and no service-account token or host mounts. The NetworkPolicy enforcement result is tested by `scripts/verify-kind-labs.sh`; the API object alone is not proof of enforcement. No workload in A is modified. Standalone Compose keeps its loopback ports and bridge protections as documented in the lab READMEs.

## Check the existing Kind environment

These commands inspect the existing installation; they do not create or recreate the cluster:

~~~bash
./scripts/healthcheck.sh kind
./scripts/inventory.sh kind
./scripts/collect-diagnostics.sh kind
~~~

Environment A's original namespace, Deployment, Service, image reference, NodePort and application behavior are preserved.

## Deploy B and C into the existing Kind cluster

~~~bash
./scripts/up-kind-labs.sh
./scripts/verify-kind-labs.sh
~~~

The `up` script builds or reuses the pinned images, loads them into the existing Kind node, creates resources only in `lab-cve-109619`, `lab-php2shell`, and the empty `trendmicro-system` namespace, verifies health, and starts all three localhost forwards in the background. It never creates/recreates Kind. See [Kind deployment](docs/kind-lab-deployment.md) for access and stop commands.

## Standalone Compose reproduction

~~~bash
docker compose -f labs/cve-2026-109619/docker-compose.yml up --build -d --wait
docker compose -f labs/php2shell-reference/docker-compose.yml up --build -d --wait
~~~

Compose is an independent reproduction option and uses its own local ports/networks. Stop only those projects with their corresponding `docker compose ... down` commands. C intentionally has no PoC container or exploit command.

## Validate all safe checks

~~~bash
./scripts/verify-labs.sh
~~~

`scripts/verify-labs.sh` checks the existing Kind app and standalone Compose profiles. `scripts/verify-kind-labs.sh` checks the three Kind environments, uses localhost port-forwards, checks NetworkPolicy traffic separation, and makes no change to A.

## TrendAI Vision One Container Security

The `trendmicro-system` namespace and a secret-free values template are prepared. The installed Kind control plane is Kubernetes 1.31.2, which is past upstream EOL, and the evaluation found no explicit Kind-on-WSL2 vendor support statement. For that reason the Container Security chart was not installed. See [the assessment and supported-cluster procedure](docs/trendai-container-security.md). No Vision One console findings or runtime detections are claimed.

## PHP security status

The upstream PHP advisory identifies PHP 8.5.12, 8.4.27, 8.3.36, and 8.2.35 as the first fixed releases for their branches. Vendor packages may backport fixes without changing the upstream version string; use package provenance and image digest as well as the version. The two CVEs are distinct: CVE-2026-109618 concerns OOM-related request-state corruption; CVE-2026-109619 concerns stale request-owned state crossing request boundaries.

Sources and consultation date are recorded in docs/compatibility-matrix.md.
