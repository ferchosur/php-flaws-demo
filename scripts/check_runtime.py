#!/usr/bin/env python3
"""Check a lab's HTTP health endpoint and request-side PHP runtime JSON."""
import json
import sys
import urllib.request


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: check_runtime.py BASE_URL EXPECTED_PHP_VERSION EXPECTED_SAPI")
    base, expected_version, expected_sapi = sys.argv[1:]
    local_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with local_opener.open(f"{base}/healthz.php", timeout=5) as response:
        health = response.read().decode().strip()
        if response.status != 200 or health != "ok":
            raise SystemExit(f"FAIL health: HTTP {response.status}, body={health!r}")
    with local_opener.open(base, timeout=5) as response:
        page = response.read().decode("utf-8", errors="replace")
        if response.status != 200 or "Worst Market" not in page:
            raise SystemExit(f"FAIL storefront: HTTP {response.status}, 'Worst Market' marker absent")
    with local_opener.open(f"{base}/__lab_runtime.php", timeout=5) as response:
        runtime = json.load(response)
    if runtime.get("php_version") != expected_version:
        raise SystemExit(f"FAIL PHP version: {runtime.get('php_version')!r}")
    if runtime.get("sapi") != expected_sapi:
        raise SystemExit(f"FAIL request SAPI: {runtime.get('sapi')!r}")
    settings = runtime.get("settings", {})
    if settings.get("memory_limit") != "8M":
        raise SystemExit("FAIL request memory_limit is not 8M")
    if settings.get("session.upload_progress.enabled") not in ("1", "On"):
        raise SystemExit("FAIL request session.upload_progress.enabled is not enabled")
    if settings.get("display_errors") not in ("1", "On"):
        raise SystemExit("FAIL request display_errors is not enabled")
    if settings.get("max_input_vars") != "1000":
        raise SystemExit("FAIL request max_input_vars is not 1000")
    if settings.get("session.use_cookies") not in ("1", "On"):
        raise SystemExit("FAIL request session.use_cookies is not enabled")
    if settings.get("session.use_strict_mode") != "0":
        raise SystemExit("FAIL request session.use_strict_mode is not disabled")
    if "session" not in runtime.get("extensions", []):
        raise SystemExit("FAIL session extension is absent")
    print("PASS", f"reference endpoint, health, PHP {runtime['php_version']}, SAPI {runtime['sapi']}, memory_limit={settings['memory_limit']}, upload_progress={settings['session.upload_progress.enabled']}")


if __name__ == "__main__":
    main()
