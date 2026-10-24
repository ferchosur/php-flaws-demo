# Compatibility and source matrix

**PHP advisory check:** 2026-10-24. B and C intentionally use vulnerable PHP 8.4.26. No corrected image or remediation comparison is deployed in this phase. A version string alone does not prove patch status if a vendor backported fixes; retain image digest and package provenance.

| Environment | Runtime/image | Server and SAPI | Reference-specific settings | Status |
|---|---|---|---|---|
| A — existing Kind | PHP 8.5.11, `php-flaws-demo:local`, Alpine | Built-in server / CLI SAPI | Existing configuration and behavior preserved | Verified healthy; unchanged |
| B — CVE-2026-109619 | Official PHP 8.4.26 Apache image, digest pinned; linux/amd64 | Apache prefork + mod_php; one worker; KeepAlive Off | `memory_limit=8M`, displayed errors, `max_input_vars=1000`, cookies on, strict mode off, upload progress and cleanup on, session path `/tmp` | Vulnerable target only; no PoC run |
| C — combined PoC reference | Official `php:8.4.26-apache-bookworm`, digest `sha256:745ef8b8...`; linux/amd64 | **Observed:** Apache 2.4.68 prefork + mod_php; Debian 12; one worker | Independently taken from eness README: `display_errors=1`, `memory_limit=8M`, `max_input_vars=1000`, cookies on, strict mode off, upload progress on | Harness prepared; README's Apache 2.4.69 does not match the pinned Bookworm image; exact PoC profile BLOCKED |

## Source inspection

### cozybear-dev/cve-2026-109619

Its Compose defines PHP 8.4.26 vulnerable and PHP 8.4.27 fixed targets plus a Python attacker. The vulnerable target uses official Apache/mod_php, `linux/amd64`, prefork with one worker, KeepAlive Off, upload progress and cleanup enabled, `memory_limit=8M`, displayed errors, `max_input_vars=1000`, cookies enabled, strict mode disabled, and a session path under `/tmp`. The target page is only `OK`; the PoC is omitted here. The current B lab uses only the vulnerable target image digest.

Sources: [README](https://github.com/cozybear-dev/cve-2026-109619/blob/main/README.md), [Compose](https://github.com/cozybear-dev/cve-2026-109619/blob/main/compose.yaml), [Apache config](https://github.com/cozybear-dev/cve-2026-109619/blob/main/target/apache.conf), [PHP INI](https://github.com/cozybear-dev/cve-2026-109619/blob/main/target/php.ini).

### eness/php2shell-CVE-2026-109618-CVE-2026-109619-PoC

Its default `bookworm` profile declares official `php:8.4.26-apache` on Debian 12 with Apache 2.4.69. The README independently specifies mod_php, Apache prefork with one worker, `display_errors=1`, `memory_limit=8M`, `max_input_vars=1000`, cookies enabled, strict mode disabled, and session upload progress enabled. It also describes a separate custom Apache 2.4.68 `lab` profile and notes that offsets vary by binary and architecture. The pinned official Bookworm image available here reports Apache 2.4.68, not 2.4.69. The upstream README does not provide a digest or runnable build files to resolve the discrepancy, so exact default-profile fidelity is BLOCKED; this lab does not substitute the generic Trixie image or claim PoC compatibility.

The repository does not contain a runnable Apache target Compose or Dockerfile. C is therefore a separate target harness derived from the declared default profile, not a claim of reproducing an upstream runnable lab. The harness pins the official `php:8.4.26-apache-bookworm` linux/amd64 manifest (`sha256:745ef8b8...`) and keeps its own Dockerfile/config. It uses localhost port 8080 for the non-root isolated container. Its observed Apache 2.4.68 does not match the README's 2.4.69; exact default-profile fidelity is BLOCKED. PoC compatibility is NOT TESTED; no offsets or PoC logic were modified and no exploit was run.

Source: [PoC README](https://github.com/eness/php2shell-CVE-2026-109618-CVE-2026-109619-PoC).

## Official vulnerability distinction

- **CVE-2026-109618 / GHSA-w8hw-w9fx-j79w:** an out-of-memory error path can leave request state inconsistent.
- **CVE-2026-109619 / GHSA-6wmf-4rv5-p3rp:** stale request-owned session state can be consumed across requests.

The PHP 8.4 fix is 8.4.27; it is deliberately not deployed here. See the official [PHP security archive](https://www.php.net/archive/2026.php) and the advisories for [CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) and [CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
