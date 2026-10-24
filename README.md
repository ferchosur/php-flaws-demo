# PHP Flaws Demo — Worst Market

Demo of CVE-2026-109618 and CVE-2026-109619 in a fictional store. The application has one runtime profile: vulnerable PHP 8.5.11 without hardening. Use it only in an isolated local lab. Cloud deployment is blocked for this profile.

## What's included

| Part | Path | Description |
|---|---|---|
| Store UI | `web/` | HTML, CSS and JS served by the PHP runtime. The checkout uses synthetic data and stores no personal information. |
| Vulnerable runtime | `app/Dockerfile-vulnerable-baseline`, `app/vulnerable/` | PHP 8.5.11 with command execution enabled, intended for isolated local testing. |
| Local cluster | `local-cluster/` | kind manifests and instructions for a local Kubernetes lab. |
| Deployment menu | `deploy.py` | Configure, run locally, plan, deploy and destroy. |
| Cloud infrastructure | `infra/` | Terraform roots for AWS, Azure and GCP. Deployment of the vulnerable profile is blocked by the menu. |

## Run locally with Docker

Requirements: Docker and Python 3.11+.

```sh
python deploy.py configure
# Select vulnerable-baseline
python deploy.py local
# http://localhost:8080
```

Stop the container with `docker rm -f php-flaws-demo-local`.

## Run in a local Kubernetes cluster

Requirements: Docker, kind, kubectl and Python 3.11+.

```sh
python deploy.py configure
# Select vulnerable-baseline
python deploy.py local-cluster
# http://localhost:8080
python deploy.py local-cluster-down
```

The local profile runs as root, has a shell and network tools, and allows PHP command execution. kind's default CNI does not enforce NetworkPolicy. Use an isolated machine and synthetic data.

## Cloud commands

Terraform plan and destroy commands remain available for existing infrastructure. `deploy.py deploy` refuses to publish the vulnerable profile. The code does not provide a hardened alternative.

## Lab cleanup

Each cloud environment uses `labs/<YYYY-MM>-<prefix>/INVENTARIO.md`. After teardown, verify that resources tagged with `created_by` are gone using the relevant cloud CLI.
