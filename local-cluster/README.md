# Local cluster (kind) — Worst Market PHP Flaws Demo

Scenario to run the demo on a **local Kubernetes cluster** on top of Docker, with no
cloud infrastructure. Intended for testing the CVE-2026-109618 / CVE-2026-109619
exploit on the **"careless prod"** (unhardened) profile on your own machine.

## Required applications

| Application | Purpose | Install |
|---|---|---|
| **Docker** (running) | kind runs the cluster as Docker containers; it also builds the image. | https://docs.docker.com/engine/install/ |
| **kind** ≥ 0.24 | Creates the local Kubernetes cluster. | `curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.25.0/kind-linux-amd64 && chmod +x ./kind && mkdir -p ~/.local/bin && mv ./kind ~/.local/bin/` · macOS: `brew install kind` |
| **kubectl** | Applies the manifests and queries status. | https://kubernetes.io/docs/tasks/tools/ |
| **Python** ≥ 3.11 | Runs `deploy.py`. | — |

`deploy.py` checks these tools and, if kind is missing, prints the install command.

## Machine resources

- **~2 vCPU** and **~2 GB of free RAM** (kind node + app at 1 replica).
- **Port `8080/TCP` free on `127.0.0.1`** — kind maps it to NodePort `30080`.
- ~1 GB of disk for the kind node image (`kindest/node`), downloaded once.

## What gets created (all local, nothing billable)

| Resource | Name | Notes |
|---|---|---|
| kind cluster | `php-flaws-demo` | 1 control-plane node (Docker container). |
| Namespace | `php-flaws-demo` | — |
| Deployment | `php-flaws-demo` | 1 replica. Baseline or hardened profile per `demo_mode`. |
| Service | `php-flaws-demo` | `NodePort 30080` → `localhost:8080`. |
| Image | `php-flaws-demo:local` | Built locally and loaded with `kind load docker-image`. |

Uses no cloud credentials and creates nothing in any cloud.

## Usage

```sh
python deploy.py configure        # choose the runtime profile (option 2a):
                                  #   - vulnerable-baseline  (careless prod, recommended here)
                                  #   - vulnerable-php        (hardened, for the A/B)
                                  #   - safe-simulation
python deploy.py local-cluster        # builds, creates the cluster and deploys
#   -> Local URL: http://localhost:8080
python deploy.py local-cluster-down   # deletes the local cluster
```

In the interactive menu these are options **7** (bring up) and **8** (delete).

## Profiles

| Profile | securityContext | Network | Purpose |
|---|---|---|---|
| `vulnerable-baseline` | root, escalation allowed, writable fs, **seccomp Unconfined**, SA token mounted | **open egress** (no NetworkPolicy) | Mimic an unhardened prod: exploitation enables a shell, commands (`system`, `exec`), `curl`/`nc` and lateral movement inside the cluster. |
| `vulnerable-php` | non-root (101), `cap-drop ALL`, read-only fs, **seccomp RuntimeDefault**, no SA token | See note | The "mitigated" side of the A/B: same bug, reduced blast radius. |

The baseline manifest is `manifests/20-deployment-baseline.yaml`; the hardened one,
`manifests/20-deployment-hardened.yaml`. `deploy.py` picks one based on `demo_mode`.

> **Note on NetworkPolicy in kind:** the default CNI (kindnet) does **not** enforce
> NetworkPolicy. The `egress-deny` that works in the cloud (GKE/AKS/EKS) is **not**
> reproduced in kind. In the baseline profile it doesn't matter (egress is open on
> purpose); in the hardened one, the rest of the controls do apply, but network
> isolation does not. To reproduce egress-deny locally you would install Calico on
> the kind cluster.

## Difference from `python deploy.py local`

`local` runs **a single container** with `docker run` (handy for a quick test).
`local-cluster` runs the app on a real **Kubernetes cluster** (kind), closer to how it
is deployed in production: Deployment, Service, probes and the same manifest flow as
the cloud.

## Containment limit (careless prod)

The baseline profile **allows command execution and lateral movement inside the local
cluster**. The real containment is that everything lives on your machine, in an
ephemeral kind cluster, with no cloud credentials. Do not deploy it to the cloud:
`deploy.py` blocks the baseline profile in `deploy` for that reason.
