# Local cluster (kind)

Run the single vulnerable PHP 8.4.26 profile on Kubernetes locally. It allows PHP command execution and has no runtime hardening; use an isolated machine with synthetic data.

## Requirements

| Application | Purpose |
|---|---|
| Docker | Runs the kind node and builds the image. |
| kind | Creates the local Kubernetes cluster. |
| kubectl | Applies manifests and checks status. |
| Python 3.11+ | Runs `deploy.py`. |

Allow about 2 vCPU, 2 GB free RAM, 1 GB disk, and port 8080 on localhost.

## Usage

```sh
python deploy.py configure
# Select vulnerable-baseline
python deploy.py local-cluster
# http://localhost:8080
python deploy.py local-cluster-down
```

The cluster, namespace and workload are local. No cloud credentials are used. kind's default CNI does not enforce NetworkPolicy.
