#!/usr/bin/env python3
"""Validate rendered Compose topology and container isolation policy."""
import json
import subprocess
import sys

ROOT = __import__("pathlib").Path(__file__).resolve().parents[1]
LABS = {
    "cve619": (
        ROOT / "labs/cve-2026-109619/docker-compose.yml",
        "php-flaws-demo-cve619",
        {"vuln": ("18088", "8.4.26")},
        "php-flaws-demo-cve619-net",
    ),
    "php2shell-reference": (
        ROOT / "labs/php2shell-reference/docker-compose.yml",
        "php-flaws-demo-php2shell-reference",
        {"target": ("18098", "8.4.26")},
        "php-flaws-demo-php2shell-net",
    ),
}


def fail(message):
    raise SystemExit(f"FAIL {message}")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in LABS:
        raise SystemExit("usage: validate_compose.py [cve619|php2shell-reference]")
    key = sys.argv[1]
    path, project, expected, network_name = LABS[key]
    result = subprocess.run(
        ["docker", "compose", "-p", project, "-f", str(path), "config", "--format", "json"],
        check=True,
        capture_output=True,
        text=True,
    )
    config = json.loads(result.stdout)
    if set(config.get("services", {})) != set(expected):
        fail(f"{key}: unexpected service set {sorted(config.get('services', {}))}")
    networks = config.get("networks", {})
    lab_networks = [net for net in networks.values() if net.get("name") == network_name]
    if len(lab_networks) != 1:
        fail(f"{key}: dedicated lab network is missing")
    network = lab_networks[0]
    options = network.get("driver_opts", {})
    if network.get("driver") != "bridge" or options.get("com.docker.network.bridge.enable_ip_masquerade") != "false":
        fail(f"{key}: bridge egress masquerading is not disabled")
    if options.get("com.docker.network.bridge.enable_icc") != "false":
        fail(f"{key}: inter-container bridge connectivity is not disabled")

    all_ports = []
    for service_name, (host_port, php_version) in expected.items():
        service = config["services"][service_name]
        ports = service.get("ports", [])
        if len(ports) != 1:
            fail(f"{key}/{service_name}: expected exactly one published port")
        port = ports[0]
        if port.get("host_ip") != "127.0.0.1" or str(port.get("published")) != host_port:
            fail(f"{key}/{service_name}: host publication is not loopback:{host_port}")
        if str(port.get("target")) != "8080":
            fail(f"{key}/{service_name}: unexpected container port")
        all_ports.append(host_port)
        if service.get("platform") != "linux/amd64":
            fail(f"{key}/{service_name}: architecture is not pinned")
        if service.get("user") != "33:33":
            fail(f"{key}/{service_name}: service does not run as the unprivileged Apache user")
        if service.get("read_only") is not True:
            fail(f"{key}/{service_name}: root filesystem is writable")
        if service.get("privileged", False) or service.get("cap_add"):
            fail(f"{key}/{service_name}: privileged mode or added capabilities found")
        if [str(c).upper() for c in service.get("cap_drop", [])] != ["ALL"]:
            fail(f"{key}/{service_name}: CAP_DROP ALL is required")
        if "no-new-privileges:true" not in service.get("security_opt", []):
            fail(f"{key}/{service_name}: no-new-privileges is missing")
        if service.get("volumes"):
            fail(f"{key}/{service_name}: unexpected host volumes")
        if service.get("mem_limit") != "268435456" and service.get("mem_limit") != 268435456:
            fail(f"{key}/{service_name}: 256 MiB memory limit is missing")
        if service.get("pids_limit") != 64:
            fail(f"{key}/{service_name}: PID limit is missing")
        image = service.get("image", "")
        if php_version not in image:
            fail(f"{key}/{service_name}: image tag does not identify PHP {php_version}")
        build_args = service.get("build", {}).get("args", {})
        if not build_args.get("PHP_APACHE_IMAGE", "").startswith("php@sha256:"):
            fail(f"{key}/{service_name}: upstream PHP image is not digest-pinned")
        if service.get("healthcheck", {}).get("disable", False):
            fail(f"{key}/{service_name}: healthcheck disabled")
    if len(set(all_ports)) != len(all_ports):
        fail(f"{key}: host ports overlap")
    print(f"PASS {key}: Compose syntax, loopback ports, dedicated no-masquerade bridge, pinned amd64 images and runtime restrictions")


if __name__ == "__main__":
    main()
