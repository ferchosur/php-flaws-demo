#!/usr/bin/env python3
"""Verify the supplied PHP scanner landing page and its visible runtime version."""
import sys
import urllib.request


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: check_php_test_site.py BASE_URL EXPECTED_PHP_VERSION")
    base, expected = sys.argv[1:]
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(base, timeout=5) as response:
        page = response.read().decode("utf-8", errors="replace")
        if response.status != 200:
            raise SystemExit(f"FAIL landing page: HTTP {response.status}")
        if f"PHP {expected}" not in page:
            raise SystemExit(f"FAIL page does not disclose expected PHP {expected}")
        powered_by = response.headers.get("X-Powered-By", "")
        if f"PHP/{expected}" not in powered_by:
            raise SystemExit(f"FAIL X-Powered-By header is {powered_by!r}")
    print(f"PASS PHP scanner landing page, PHP {expected}, X-Powered-By {powered_by}")


if __name__ == "__main__":
    main()
