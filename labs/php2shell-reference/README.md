# PHP2Shell combined PoC reference target

Environment C is an independent target harness for the default requirements declared by [eness/php2shell-CVE-2026-109618-CVE-2026-109619-PoC](https://github.com/eness/php2shell-CVE-2026-109618-CVE-2026-109619-PoC). The PoC repository does not provide a runnable Apache target Dockerfile or Compose setup. This harness derives from its README's default `bookworm` profile and remains separate from B.

## Declared target profile

The README specifies the official PHP 8.4.26 Apache image on Debian 12 (Bookworm), Apache 2.4.69, mod_php, prefork with one worker, `display_errors=1`, `memory_limit=8M`, `max_input_vars=1000`, cookies enabled, strict mode disabled, and session upload progress enabled. The README also describes a distinct custom Apache 2.4.68 `lab` profile and states that offsets depend on the exact binary and architecture. This harness selects the pinned official Bookworm image; it does not alter offsets or PoC logic.

C owns its Dockerfile and Apache/PHP configuration under `target/`. Its target endpoint returns `OK`; `/healthz.php` and `/__lab_runtime.php` provide safe diagnostics. The container listens on port 8080 and runs as UID 33 for the isolated non-root harness; these are packaging choices, not requirements claimed by the upstream README. Runtime inspection found Debian 12 and Apache 2.4.68 in the pinned Bookworm image, while the README declares Apache 2.4.69 for its default profile. The upstream repository provides no target image/build/digest to reproduce that exact profile. Exact fidelity is BLOCKED and PoC compatibility is NOT TESTED. No PoC or exploit runs automatically.

## Kind deployment

~~~bash
docker compose -f labs/php2shell-reference/docker-compose.yml build
./scripts/deploy-kind-labs.sh
kubectl --context kind-php-flaws-demo -n lab-php2shell get pods,svc -o wide
~~~

The Service is ClusterIP only. `./scripts/up-kind-labs.sh` also starts the localhost-only background forward at `http://127.0.0.1:8083/`. The workload has an independent namespace and NetworkPolicy.

## Safe checks

~~~bash
docker compose -f labs/php2shell-reference/docker-compose.yml up --build -d --wait
./scripts/healthcheck.sh php2shell-reference
./scripts/inventory.sh php2shell-reference
docker compose -f labs/php2shell-reference/docker-compose.yml down
~~~

Expected observations are HTTP health 200, PHP 8.4.26, `apache2handler`, and the README-declared PHP INI values. These checks establish profile identity only; they do not establish exploitability. The PoC remains out of scope until a separate authorized test plan exists.
