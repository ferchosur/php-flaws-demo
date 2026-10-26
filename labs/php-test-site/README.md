# Lab D — PHP scanner test site

This lab adapts the `onprem/` application from the team-shared `php-test-site.zip`. It is a small PHP landing page intended to let a vulnerability scanner identify the PHP runtime. The page reports `PHP_VERSION`; its ordinary request code does not implement an exploit or a vulnerable business feature. The vulnerable component is PHP 8.3.26 itself. Trend Micro's current advisory lists PHP versions below 8.3.36 as affected by CVE-2026-109618 and CVE-2026-109619.

The supplied image is PHP 8.3.26 with Apache/mod_php on Debian Bookworm (official image digest `sha256:33025d411fb4ed9b96947af349dd382afee37024e5d940f9fa17e1fa41753ff3`, linux/amd64). Its PHP configuration enables `expose_php`, and the page renders the PHP version in its footer. It does not provide the PoC endpoints or prove exploitability. This is a scanner target/profile, not a reproduction of either exploit.

## Kind deployment

From the repository root, deploy only D into the already-running Kind cluster:

~~~bash
./scripts/deploy-kind-php-test-site.sh
~~~

Lab D runs in namespace `lab-php-test-site`, behind a ClusterIP Service. The deployment script starts its local access URL at `http://127.0.0.1:8082/`; the port-forward binds only to loopback. It has a separate NetworkPolicy that denies egress and allows ingress only from pods in its namespace. The pod runs as UID 33 with dropped capabilities, RuntimeDefault seccomp, a read-only root filesystem, bounded resources and ephemeral writable runtime directories. No service-account token is mounted. Stop the local forward with `./scripts/stop-kind-port-forwards.sh`.

## Standalone Compose

~~~bash
docker compose -f labs/php-test-site/docker-compose.yml up --build -d --wait
curl --noproxy '*' --fail http://127.0.0.1:18082/
docker compose -f labs/php-test-site/docker-compose.yml down
~~~

Compose publishes only on `127.0.0.1:18082`. The image and namespace are separate from environments A, B and C.

## Findings and limits

- The source is a mostly static HTML landing page with one PHP version interpolation.
- Apache uses mod_php; the worker runs as UID 33. PHP 8.3.26 is below the advisory's fixed 8.3.36 release.
- `expose_php=On` and the visible page footer help scanners fingerprint the runtime.
- The supplied Compose file originally bound `0.0.0.0:8080`; this lab intentionally limits access to localhost/loopback.
- A version match is a useful inventory signal, but vendor backports and image provenance can change patch status. The lab pins the upstream version tag, not a registry digest.
- No exploit, PoC, or external scanner is run as part of deployment.
