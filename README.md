# PHP Flaws Demo — Worst Market

Reusable demo to showcase CVE-2026-109618 and CVE-2026-109619 in a fictional store. The commercial experience is static HTML/JS. The default profile does not include PHP; on VM (EC2, Azure VM, Compute Engine) and Kubernetes (EKS, AKS, GKE) you can explicitly enable a pre-patch PHP runtime for the lab, isolated with a seccomp jail. No profile contains exploitation payloads. Serverless options are not offered.

## What's included

| Part | Path | Description |
|---|---|---|
| Store | `web/` | Static HTML, CSS and JS with no dependencies or CDN. Catalog, cart, simulated checkout and a security demo page. The receipt stores only the code, products and total; it does not persist name, email or address. |
| Secure image | `app/Dockerfile` | Unprivileged nginx, no scripting modules, no shell after the build. Default for every cloud and platform. |
| Vulnerable runtime | `app/Dockerfile-vulnerable`, `app/vulnerable/` | Optional PHP 8.5.11 profile for VM and Kubernetes, prior to the fixed version 8.5.12. The UI walkthrough sends no exploits; the runtime does process HTTP. |
| Seccomp jail | `app/seccomp-vulnerable.json` | Deny-list of escape syscalls (ptrace, mount, namespaces, module loading, kexec, bpf) applied to the vulnerable runtime on VM. Unprivileged: keeps UID 101 and `cap-drop ALL`. |
| "Careless prod" runtime | `app/Dockerfile-vulnerable-baseline` | Vulnerable profile with NO hardening (root, shell, `curl`/`nc`, no `disable_functions`, no seccomp) to contrast with the hardened one. Local cluster / isolated labs only; `deploy.py` blocks it in the cloud. |
| Local cluster | `local-cluster/` | kind scenario (local Kubernetes on Docker) with prerequisites, resources and manifests. See [local-cluster/README.md](local-cluster/README.md). |
| Menu | `deploy.py` | Interactive menu (Python 3.11+ stdlib): configure, test locally, plan, deploy and destroy. |
| Infrastructure | `infra/<cloud>/<platform>/` | Six Terraform roots (VM and Kubernetes per cloud) sharing the same variable contract. |
| Kubernetes | `k8s/` | Namespace manifests, with Pod Security `restricted` and default-deny networking. |

## Deployment options

There are **four ways** to run the demo, from lowest to highest fidelity. All use the same content (`web/`) and, except the static preview, the same image built from `app/`.

| # | Option | For | Requirements | Profiles | Command |
|---|---|---|---|---|---|
| 1 | Static preview | See the store (HTML/JS), no backend | Python | — (static only) | `python -m http.server 8000 -d web` |
| 2 | Single Docker container | Quick image test | Docker | all three | `python deploy.py local` |
| 3 | Local kind cluster | Reproduce K8s on your machine (ideal for exploit testing) | Docker, kind, kubectl | all three | `python deploy.py local-cluster` |
| 4 | Cloud (AWS/Azure/GCP) | Real public environment (VM or Kubernetes) | Authenticated cloud CLI, Terraform, Docker | safe · hardened vulnerable | `python deploy.py` → configure → deploy |

`python deploy.py` (no arguments) opens the interactive menu with every action; direct subcommands also exist: `configure`, `local`, `local-cluster`, `local-cluster-down`, `plan`, `deploy`, `destroy`. `deployment.json` stores the configuration (no secrets).

### Runtime profiles

Chosen during **Configure** (step 2a), available in options 2, 3 and 4 (in option 4, safe and hardened vulnerable only):

| Profile | What it is | Where it's allowed |
|---|---|---|
| `safe-simulation` | Static nginx, no PHP. **Default.** | Every option and platform |
| `vulnerable-php` | Pre-patch PHP 8.5.11, **hardened**: non-root, `cap-drop ALL`, read-only fs, no shell, `disable_functions`, seccomp / `RuntimeDefault`, no cloud identity. | VM, Kubernetes and local cluster (double confirmation in cloud) |
| `vulnerable-baseline` | Pre-patch PHP 8.5.11, **"careless prod"**: root, shell, `curl`/`nc`, no `disable_functions`, no seccomp, open egress. | **Only** local cluster / `local`; `deploy.py` **blocks** it in the cloud |

No profile includes exploitation payloads: the UI walkthrough does not attack, and the vulnerable runtime only processes HTTP.

### 1. Static preview

Just the store, no image or backend. Does not apply nginx headers or hardening.

```sh
python -m http.server 8000 -d web   # http://localhost:8000
```

### 2. Single Docker container

One container via `docker run`, with the same hardening as the cloud.

```sh
python deploy.py configure   # choose cloud/platform and, in 2a, the runtime profile
python deploy.py local       # builds the profile's image and runs it
# http://localhost:8080   — stop: docker rm -f php-flaws-demo-local
```

The hardened profile attaches the container to an internal Docker network (no egress) and applies the seccomp jail; "careless prod" runs as root with open egress.

### 3. Local kind cluster

Local Kubernetes on Docker — the **recommended option for exploit testing**. Prerequisites, resources and details in **[local-cluster/README.md](local-cluster/README.md)**.

```sh
python deploy.py configure           # in 2a choose the profile (e.g. vulnerable-baseline)
python deploy.py local-cluster       # builds, creates the kind cluster and deploys
# http://localhost:8080
python deploy.py local-cluster-down  # deletes the cluster when done
```

Requires `kind` (if missing, `deploy.py` prints the install command) and `kubectl`. Note: kind's CNI (kindnet) does not enforce NetworkPolicy, so the hardened profile's egress-deny is not reproduced locally.

### 4. Cloud deployment

Real public environment. Platform matrix:

| Cloud | Virtual machine | Kubernetes |
|---|---|---|
| AWS | EC2 (cloud-init) | EKS |
| Azure | Virtual Machine (cloud-init) | AKS |
| GCP | Compute Engine (COS) | GKE |

Serverless (Lambda, Azure Functions, Cloud Functions, ECS Fargate, Container Apps, Cloud Run) is not offered: the seccomp jail and egress-deny cannot be applied there with the same control as on VM and Kubernetes.

**Step by step:**

1. **Authenticate to the cloud** and have the tools (`terraform`, `docker`, and `aws`/`az`/`gcloud` with an active session).
   - AWS: `aws sso login` (or your flow). If Terraform doesn't pick up credentials from an SSO/role session, export them in the same shell: `eval "$(aws configure export-credentials --format env)"`.
2. **Configure** — `python deploy.py configure`: cloud, platform, region, prefix, owner (`created_by`), expiry, size, replicas, budget, alert email, project (GCP) and, on Kubernetes, your public IP for the API. On VM/K8s you choose the runtime profile (step 2a).
3. **Plan** (optional, creates nothing) — `python deploy.py plan`.
4. **Deploy** — `python deploy.py deploy`: prompts you to type the prefix to confirm; the vulnerable profile also prompts you to type `DEPLOY-VULNERABLE`. Internally:
   1. Creates `labs/<YYYY-MM>-<prefix>/` with `INVENTARIO.md`.
   2. Terraform creates only the private registry (`-target`).
   3. Builds the profile's image and publishes it with a timestamp tag (effectively immutable).
   4. Terraform applies the full infrastructure with that image.
   5. On Kubernetes, `kubectl apply` of the manifests rendered into `build/k8s/`.
   6. Prints the public URL and updates `INVENTARIO.md`.
5. **Destroy** — `python deploy.py destroy` (prompts for the prefix): deletes the LoadBalancer Service first, then `terraform destroy`.

**Vulnerable-profile isolation in the cloud** (platform-dependent):

- **VM (EC2, Azure VM):** seccomp jail `app/seccomp-vulnerable.json`. Denies the kernel escape / lateral-movement primitives (`ptrace`, `mount`/`umount2`, `pivot_root`, `chroot`, `setns`, `unshare`, module loading, `kexec`, `bpf`, `perf_event_open`). `execve` is necessarily left allowed — the runtime needs it to launch `php` — so command execution is blocked at the PHP layer (`disable_functions`) and because the image has no shell or any other binary to launch. Egress restricted by NSG/firewall to 443 and DNS. Compute Engine (COS/konlet) does not allow a custom seccomp profile via container declaration (see residuals).
- **Kubernetes (EKS, AKS, GKE):** `seccompProfile: RuntimeDefault`, default-deny NetworkPolicy (HTTP ingress and DNS egress only), no ServiceAccount token and no workload identity. All three clusters enforce NetworkPolicy (GKE Calico, AKS `azure`, EKS VPC CNI with `enableNetworkPolicy`).

**`chroot(2)` is not used**: it would require `CAP_SYS_CHROOT` or root at startup, breaking the unprivileged model. The seccomp jail contains this class of bug (memory corruption → possible in-process execution) by denying the container's escape syscalls, while `disable_functions` and the absence of a shell prevent command execution. `execve` cannot be denied via seccomp: it is the syscall the runtime uses to launch `php` itself, and denying it stops the container from starting. This isolation reduces blast radius; it does not make a vulnerable version safe nor guarantee there is no escape.

## Security controls

The goal is that if someone exploits the application, they have no way to run system commands or move toward other resources.

| Control | Where |
|---|---|
| Static profile with no PHP/FastCGI; separate, optional vulnerable PHP profile | `app/nginx.conf`, `app/Dockerfile-vulnerable` |
| Seccomp jail on the vulnerable runtime on VM (escape syscalls denied; commands blocked by `disable_functions` + no shell); `RuntimeDefault` on Kubernetes | `app/seccomp-vulnerable.json`, EC2/Azure VM cloud-init, `k8s/20-deployment.yaml` |
| User 101, non-root, `--cap-drop ALL`, `no-new-privileges` | `app/Dockerfile`, manifests, all platforms |
| No `/bin/sh`, `apk`, `wget` or `curl` in the final image | `app/Dockerfile` |
| Read-only root; only `/tmp` writable | All platforms (see exceptions) |
| No workload identity; only the pull identity, scoped to the repository | All roots |
| No SSH, no keys in the image, no secrets in environment variables | All |
| Public HTTP ingress to the entry point only | All |
| Restricted egress: VM with NSG/firewall only 443 and DNS; K8s with NetworkPolicy | See residuals table |
| IMDSv2 required with hop limit 1 | EC2, EKS nodes |
| Pod Security `restricted`, no service account token, quotas and LimitRange | `k8s/` |
| `created_by`, `expires_at`, `app`, `managed_by` labels on every resource | `locals.tf` / `labels` |

### Residual risks (not fully mitigated)

| Platform | Residual |
|---|---|
| AKS / GKE / EKS | Nodes have egress (AKS: no NAT; EKS: one NAT gateway; GKE: no NAT, Google APIs only). |
| EKS | `AmazonEC2ContainerRegistryReadOnly` can read every repository in the account. The `LoadBalancer` Service requires installing the AWS Load Balancer Controller, which this root does not install. |
| EC2 | The instance role can call `GetAuthorizationToken` on `*`. The public IP is stable (Elastic IP); an unassociated EIP bills if the instance is destroyed without releasing the EIP. |
| VM (Azure, GCP, EC2) | HTTP without TLS. Azure VM generates an SSH key into state if one isn't provided. Stable public IP on all three (EC2 Elastic IP, Azure Static Standard IP, GCP reserved address). |
| GCP Compute | Port 8080 instead of 80, because konlet uses `--network=host`. No `readOnlyRootFilesystem`; `/tmp` and `/var/cache/nginx` are in-memory tmpfs. **Konlet does not apply the custom seccomp jail**: the vulnerable runtime on Compute Engine relies on COS's default profile, `disable_functions`, the absence of a shell and the egress firewall. For strict seccomp, use EC2/Azure VM or Kubernetes. |
| Registry | ACR and ECR/Artifact Registry without vulnerability scanning or tag immutability on GCP. |
| Budget | Azure uses a fixed start date (`2026-10-01`) that must be updated. GCP sends no email (requires a notification channel). |

These measures reduce blast radius. They do not replace patches, do not guarantee that a compromised workload causes no harm, and do not protect against abuse of the cloud control plane itself.

On EKS, the root explicitly enables `enableNetworkPolicy` on the VPC CNI addon; without that option, Kubernetes policies do not enforce the expected isolation. See the [AWS documentation for enabling NetworkPolicy on EKS](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy-configure.html).

## Verification status

| Item | Verified | Not verified |
|---|---|---|
| `deploy.py` | `py_compile`; wizard syntax and local actions. | Real deployment flow, `plan` and `apply` against accounts. |
| `web/` | Valid JS syntax with `node --check`. | Browser testing. |
| Secure image (`app/Dockerfile`) | — | Not built in this session. |
| Seccomp jail | Valid JSON; vulnerable container tested locally with the profile (`/healthz` 200, no shell, starts correctly). | Real enforcement of the denied syscalls; VM cloud-init wiring (only verified when the VM boots). |
| Vulnerable image | `docker build` of `Dockerfile-vulnerable` OK; fixed the `chown`/`rm busybox` ordering that broke the build. | — |
| Terraform (9 roots) | `fmt` and `validate` pass on all (incl. EC2/Azure VM/GCP Compute with stable IP and seccomp). | Real `plan`/`apply`; provider and cloud-init behavior. |
| `k8s/` | — | `kubectl apply --dry-run` against a real cluster. |

Before a real deployment:

```sh
docker build -f app/Dockerfile -t php-flaws-demo:local .
docker run --rm -p 8080:8080 --read-only --tmpfs /tmp --user 101:101 --cap-drop ALL php-flaws-demo:local
docker run --rm --read-only --user 101:101 --entrypoint /bin/sh php-flaws-demo:local -c id   # must fail
```

Pin the base image by digest:

```sh
docker buildx imagetools inspect nginxinc/nginx-unprivileged:1.27-alpine
```

## Lab rules

Every deployment is a lab: `labs/<YYYY-MM>-<prefix>/` with `INVENTARIO.md`, `created_by` labels on every resource (lowercase on GCP) and cleanup with `python deploy.py destroy`. On teardown, verify no tagged resources remain:

- AWS: `aws resourcegroupstaggingapi get-resources --tag-filters Key=created_by,Values=<owner>`
- Azure: `az resource list --tag created_by=<owner>`
- GCP: `gcloud asset search-all-resources --scope=projects/<P> --query="labels.created_by=<owner-lowercase>"`

## Sources

- [PHP: Security advisory, 21 Oct 2026](https://www.php.net/archive/2026.php): CVE-2026-109618 (out-of-memory corruption) and CVE-2026-109619 (use-after-free / stale state); fixed versions 8.5.12, 8.4.27, 8.3.36 and 8.2.35.
- [Advisory GHSA-6wmf-4rv5-p3rp](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp)
- [Advisory GHSA-w8hw-w9fx-j79w](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)

## Suggested process for new demos

1. Validate the CVE, affected and fixed versions in the vendor advisory.
2. Define the goal and classify the content as simulation, controlled reproduction or detection.
3. Use synthetic data. Keep simulation as the default option; the pre-patch profile is offered only on VM and Kubernetes, with isolation and double confirmation.
4. Review isolation, privileges, network access, expiry and cost against a shared checklist.
5. Add the commercial script, restart/teardown steps and content owner.
6. Review and update the content when new advisories or patches are published.
