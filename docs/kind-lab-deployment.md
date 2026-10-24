# Deploying the PHP labs into the existing Kind cluster

## Namespaces and resources

| Environment | Namespace | Resources | Access |
|---|---|---|---|
| A — original app | `php-flaws-demo` | Existing Deployment and NodePort Service; unchanged | Existing `http://localhost:8080/` |
| B — vulnerable | `lab-cve-109619` | `vuln-php-apache-target` Deployment and ClusterIP Service; PHP 8.4.26 | `kubectl port-forward` to localhost |
| C — combined PoC reference | `lab-php2shell` | `php2shell-php-apache-target` Deployment and ClusterIP Service; independent PHP 8.4.26 Bookworm Apache profile | `kubectl port-forward` to localhost |
| TrendAI preparation | `trendmicro-system` | Empty namespace reserved for a later supported evaluation | No sensor installed |

Kustomize keeps the Apache/PHP Pod specification in `k8s/labs/base/`; overlays change only image, namespace, name, and identification labels. The builds remain shared with the existing Compose definitions. Container images are loaded into the existing Kind node with `kind load docker-image`; `imagePullPolicy: Never` ensures Kubernetes uses those local artifacts and never tries to pull them.

Only A serves the Worst Market UI. B and C use minimal `OK` targets and separate PHP/Apache profile configuration. Their `/healthz.php` and `/__lab_runtime.php` endpoints provide safe diagnostics. B follows cozybear-dev's vulnerable 8.4.26 target. C follows the eness README's default Bookworm profile and pins the official Bookworm image digest; the reference repo does not supply a runnable target Compose/Dockerfile.

The B/C Services are `ClusterIP` only. No host port or NodePort is allocated. The NetworkPolicies allow ingress from pods in their own namespace on TCP/8080 and deny egress. They are intended to limit the lab traffic to same-namespace peers and prevent outbound traffic. Actual enforcement must be checked against the active Kind CNI; the policy objects can exist without enforcement on older CNI builds. Do not treat namespace separation alone as a network boundary.

The workloads run as UID/GID 33, drop all Linux capabilities, disallow privilege escalation, use RuntimeDefault seccomp and a read-only root filesystem. Only ephemeral memory-backed volumes cover Apache runtime/log and PHP `/tmp` paths. The ServiceAccount token is not mounted. No PoC, Docker socket, host filesystem, or credentials are present in these Pods.

## Deploy and verify

Build both vulnerable-only Compose labs first if the two local images are absent:

~~~bash
docker compose -f labs/cve-2026-109619/docker-compose.yml build
docker compose -f labs/php2shell-reference/docker-compose.yml build
~~~

Build, deploy, verify, and expose all three scenarios with one command:

~~~bash
./scripts/up-kind-labs.sh
~~~

The script checks the current context and existing cluster instead of creating one, builds/reuses the two pinned vulnerable images, confirms A's health, loads only B and C images, and applies resources only in the lab namespaces. It waits for B/C Deployments and runs `scripts/verify-kind-labs.sh`. The latter uses temporary test forwards at ports 28088 and 28098 and terminates those after validation. Finally, two persistent forwards start in the background, bound to `127.0.0.1` on ports 8081 (B) and 8083 (C); no terminal stays open.

Manual verification:

~~~bash
kubectl --context kind-php-flaws-demo -n lab-cve-109619 get pods,svc -o wide
kubectl --context kind-php-flaws-demo -n lab-php2shell get pods,svc -o wide
kubectl --context kind-php-flaws-demo -n lab-cve-109619 exec deploy/vuln-php-apache-target -- php -v
kubectl --context kind-php-flaws-demo -n lab-php2shell exec deploy/php2shell-php-apache-target -- php -v
~~~

The background forwards remain available at `http://localhost:8081/` (B) and `http://localhost:8083/` (C). Re-running `scripts/start-kind-port-forwards.sh` is safe; it reports if both are already active. Stop only the local forward processes with:

~~~bash
./scripts/stop-kind-port-forwards.sh
~~~

The cluster workloads remain running. Re-open their local URLs later with `scripts/start-kind-port-forwards.sh`.

The tests inspect A's pod, image reference, NodePort, PHP runtime, and `/healthz` before and after. They do not roll out, restart, or edit any A resource. A test that finds cross-namespace access succeeds is a FAIL for network isolation; do not use the environment for sensitive workloads.

## Stop without removing resources

Scale only these new Deployments to zero when the vulnerable targets should no longer be serving:

~~~bash
kubectl --context kind-php-flaws-demo -n lab-cve-109619 scale deploy/vuln-php-apache-target --replicas=0
kubectl --context kind-php-flaws-demo -n lab-php2shell scale deploy/php2shell-php-apache-target --replicas=0
~~~

Restore them by using `scripts/deploy-kind-labs.sh`. Namespace/policy cleanup is intentionally omitted so no data or state is removed automatically. Do not use `kind delete cluster` for this workflow.

## Observed cluster baseline — 2026-10-24

- Kind cluster `php-flaws-demo`; current context `kind-php-flaws-demo`.
- One Ready node `php-flaws-demo-control-plane`, Kubernetes `v1.31.2`, containerd `1.7.18`, running in `kindest/node:v1.31.2` on the WSL2 kernel. Its allocatable capacity was 14 CPU and about 15.3 GiB memory.
- `kube-system/kindnet` image was `kindest/kindnetd:v20241023-a345ebe4`. With the lab policies applied, the verification script's harmless HTTP health request from C to B was blocked (PASS for that tested path). This is evidence for that path only, not a blanket audit of every ingress/egress route.
- A remained 1/1 Ready with image `php-flaws-demo:local`, PHP 8.5.11, and its original NodePort 30080.
- The original fixed PHP 8.4.27 Deployment/Service were removed from `lab-cve-109619` during the vulnerable-only scope correction. Only the vulnerable B target remains; A and C were not removed or modified by that cleanup.
