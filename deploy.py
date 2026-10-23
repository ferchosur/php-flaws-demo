"""Deployment menu for Mercado Norte (PHP Flaws Demo).

Configures the cloud and infrastructure, builds the image, publishes it to the
provider's private registry and applies Terraform. Uses only the Python 3.11+
standard library.

Usage:
    python deploy.py                 # interactive menu
    python deploy.py show            # show the saved configuration
    python deploy.py local           # build and run the image with Docker
    python deploy.py plan            # terraform plan without applying
    python deploy.py deploy          # deploy (asks for explicit confirmation)
    python deploy.py destroy         # destroy the environment (asks for explicit confirmation)
"""

import argparse
import datetime as dt
import getpass
import json
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CONFIG_PATH = ROOT / "deployment.json"
BUILD_DIR = ROOT / "build"
K8S_SRC = ROOT / "k8s"
IMAGE_REPO = "php-flaws-demo"
K8S_NAMESPACE = "php-flaws-demo"
APP_TAG = "php-flaws-demo"

CLOUDS = {
    "aws": {
        "label": "AWS",
        "default_region": "us-east-1",
        "platforms": {
            "ecs": ("ECS Fargate", "serverless containers behind an Application Load Balancer"),
            "ec2": ("EC2", "virtual machine with Docker (cloud-init)"),
            "eks": ("EKS", "managed Kubernetes cluster"),
        },
        "registry_address": "aws_ecr_repository.app",
    },
    "azure": {
        "label": "Azure",
        "default_region": "eastus",
        "platforms": {
            "container-apps": ("Container Apps", "serverless containers with HTTPS ingress"),
            "vm": ("Virtual Machines", "Linux virtual machine with Docker (cloud-init)"),
            "aks": ("AKS", "managed Kubernetes cluster"),
        },
        "registry_address": "azurerm_container_registry.app",
    },
    "gcp": {
        "label": "GCP",
        "default_region": "us-central1",
        "platforms": {
            "cloud-run": ("Cloud Run", "serverless containers with HTTPS"),
            "compute-engine": ("Compute Engine", "virtual machine with Container-Optimized OS"),
            "gke": ("GKE", "managed Kubernetes cluster"),
        },
        "registry_address": "google_artifact_registry_repository.app",
    },
}
K8S_PLATFORMS = {"eks", "aks", "gke"}
VM_PLATFORMS = {"ec2", "vm", "compute-engine"}
# The vulnerable PHP profile is offered only on VM and Kubernetes; the serverless
# container tier (ECS Fargate, Container Apps, Cloud Run) stays on safe simulation,
# because the seccomp jail and egress-deny cannot be applied with the same control.
VULN_PLATFORMS = VM_PLATFORMS | K8S_PLATFORMS

DOCKERFILES = {
    "safe-simulation": "Dockerfile",
    "vulnerable-php": "Dockerfile-vulnerable",
    "vulnerable-baseline": "Dockerfile-vulnerable-baseline",
}
# "Careless prod" mode: vulnerable and NOT hardened. Enables command execution
# and lateral movement; local cluster or isolated labs only.
BASELINE_MODE = "vulnerable-baseline"
KIND_CLUSTER = "php-flaws-demo"
LOCAL_CLUSTER_SRC = ROOT / "local-cluster"
SIZES = [("small", "Small"), ("medium", "Medium")]

REGION_RE = re.compile(r"^[a-z0-9-]{4,40}$")
PREFIX_RE = re.compile(r"^[a-z][a-z0-9-]{2,20}$")
OWNER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
CIDR_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$")


# --------------------------------------------------------------------------- utilities

def die(message):
    print(f"\nError: {message}", file=sys.stderr)
    raise SystemExit(1)


def tool(name):
    path = shutil.which(name)
    if not path:
        die(f"'{name}' was not found in PATH. Install it before continuing.")
    return path


def run(args, cwd=None, stdin=None, capture=False, check=True):
    """Run a command without a shell. Arguments are never interpreted by the shell."""
    proc = subprocess.run(
        [tool(args[0]), *args[1:]],
        cwd=cwd,
        input=stdin,
        text=True,
        capture_output=capture,
    )
    if check and proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        die(f"'{' '.join(args[:3])}' exited with code {proc.returncode}.\n{detail}")
    return proc.stdout.strip() if capture else proc


def ask(prompt, default=None, pattern=None, required=False, cast=str):
    suffix = f" [{default}]" if default not in (None, "") else ""
    while True:
        raw = input(f"{prompt}{suffix}: ").strip()
        if raw == "" and default is not None:
            raw = str(default)
        if raw == "":
            if required:
                print("This value is required.")
                continue
            return ""
        if pattern and not pattern.match(raw):
            print("Invalid format. Check the example and try again.")
            continue
        try:
            return cast(raw)
        except ValueError:
            print("Invalid value.")


def choose(title, options, default=None):
    """options: list of (key, label). Returns the chosen key."""
    print(f"\n{title}")
    keys = [key for key, _ in options]
    for number, (key, label) in enumerate(options, 1):
        marker = " (current)" if key == default else ""
        print(f"  {number}) {label}{marker}")
    while True:
        raw = input("> ").strip()
        if raw == "" and default in keys:
            return default
        if raw.isdigit() and 1 <= int(raw) <= len(keys):
            return keys[int(raw) - 1]
        print("Invalid option. Try again.")


def confirm_word(word, message):
    print(f"\n{message}")
    typed = input(f"Type '{word}' to continue (anything else cancels): ").strip()
    return typed == word


def load_config():
    if not CONFIG_PATH.exists():
        return None
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def save_config(config):
    CONFIG_PATH.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"\nConfiguration saved to {CONFIG_PATH.name}.")


def require_config():
    config = load_config()
    if config is None:
        die("deployment.json does not exist. Run the configuration first (menu option 1).")
    return config


def stack_dir(config):
    return ROOT / "infra" / config["provider"] / config["platform"]


def lab_dir(config):
    """Lab folder required by the lab rules: labs/<YYYY-MM>-<prefix>/."""
    month = dt.date.today().strftime("%Y-%m")
    return ROOT / "labs" / f"{month}-{config['name_prefix']}"


def detect_public_ip():
    try:
        with urllib.request.urlopen("https://checkip.amazonaws.com", timeout=10) as resp:
            return resp.read().decode().strip()
    except OSError:
        return ""


# --------------------------------------------------------------------------- configuration

def configure(current):
    current = current or {}
    print("\n=== Deployment configuration ===")

    provider = choose(
        "1. Choose the cloud",
        [(key, data["label"]) for key, data in CLOUDS.items()],
        default=current.get("provider"),
    )
    platforms = CLOUDS[provider]["platforms"]
    platform = choose(
        "2. Choose the infrastructure",
        [(key, f"{name}: {desc}") for key, (name, desc) in platforms.items()],
        default=current.get("platform") if current.get("provider") == provider else None,
    )
    demo_mode = "safe-simulation"
    if platform in VULN_PLATFORMS:
        demo_mode = choose(
            "2a. Runtime profile",
            [
                ("safe-simulation", "Safe simulation with static nginx"),
                ("vulnerable-php", "PHP 8.5.11 vulnerable, hardened with a seccomp jail (confirmation on deploy)"),
                ("vulnerable-baseline", "PHP 8.5.11 vulnerable, NOT hardened (careless prod; prefer the local cluster)"),
            ],
            default=current.get("demo_mode", "safe-simulation") if current.get("platform") == platform else "safe-simulation",
        )
    same_cloud = current.get("provider") == provider
    region = ask(
        "3. Region",
        default=current.get("region") if same_cloud else CLOUDS[provider]["default_region"],
        pattern=REGION_RE,
    )
    name_prefix = ask("4. Name prefix (lowercase and hyphens)", default=current.get("name_prefix", "php-flaws-demo"), pattern=PREFIX_RE)
    owner = ask("5. Owner (created_by label)", default=current.get("owner"), pattern=OWNER_RE, required=True)
    default_expiry = (dt.date.today() + dt.timedelta(days=7)).isoformat()
    expires_at = ask("6. Expires on (YYYY-MM-DD)", default=current.get("expires_at", default_expiry), pattern=DATE_RE)
    size = choose("7. Workload size", SIZES, default=current.get("size", "small"))
    replicas = ask("8. Replicas (ignored on VM, which create a single instance)", default=current.get("replicas", 2), cast=int)
    if not 1 <= replicas <= 5:
        die("replicas must be between 1 and 5.")
    budget_usd = ask("9. Monthly budget in USD", default=current.get("budget_usd", 25), cast=float)
    alert_email = ask("10. Email for budget alerts (empty = no alerts)", default=current.get("alert_email", ""))

    project_id = ""
    billing_account_id = ""
    if provider == "gcp":
        default_project = current.get("project_id") or ""
        if not default_project and shutil.which("gcloud"):
            default_project = run(["gcloud", "config", "get-value", "project"], capture=True, check=False).stdout.strip()
        project_id = ask("11. GCP project ID", default=default_project, required=True)
        billing_account_id = ask("12. Billing account ID (empty = no budget)", default=current.get("billing_account_id", ""))

    admin_cidrs = current.get("admin_cidrs", []) if same_cloud else []
    if platform in K8S_PLATFORMS:
        detected = detect_public_ip()
        suggestion = f"{detected}/32" if detected else ""
        cidr = ask("13. Operator public IP for the Kubernetes API (x.x.x.x/32)", default=(admin_cidrs[0] if admin_cidrs else suggestion), pattern=CIDR_RE, required=True)
        admin_cidrs = [cidr]

    config = {
        "app": "php-flaws-demo",
        "demo_mode": demo_mode,
        "exposure": "public-http-only",
        "provider": provider,
        "platform": platform,
        "region": region,
        "name_prefix": name_prefix,
        "owner": owner,
        "expires_at": expires_at,
        "size": size,
        "replicas": replicas,
        "budget_usd": budget_usd,
        "alert_email": alert_email,
        "project_id": project_id,
        "billing_account_id": billing_account_id,
        "admin_cidrs": admin_cidrs,
    }
    save_config(config)
    show(config)
    return config


def show(config):
    cloud = CLOUDS[config["provider"]]
    name, desc = cloud["platforms"][config["platform"]]
    print("\nSummary")
    print(f"  Cloud:           {cloud['label']}")
    print(f"  Infrastructure:  {name} ({desc})")
    print(f"  Demo profile:    {config.get('demo_mode', 'safe-simulation')}")
    print(f"  Region:          {config['region']}")
    print(f"  Prefix:          {config['name_prefix']}")
    print(f"  Owner:           {config['owner']}  (created_by)")
    print(f"  Expires:         {config['expires_at']}")
    print(f"  Size/replicas:   {config['size']} / {config['replicas']}")
    print(f"  Budget:          {config['budget_usd']} USD/month")
    print(f"  Lab folder:      {lab_dir(config).relative_to(ROOT)}")


# --------------------------------------------------------------------------- Terraform

def tfvars_path(config):
    return stack_dir(config) / "terraform.tfvars.json"


def write_tfvars(config, image=""):
    values = {
        "name_prefix": config["name_prefix"],
        "region": config["region"],
        "owner": config["owner"],
        "expires_at": config["expires_at"],
        "image": image,
        "size": config["size"],
        "replicas": config["replicas"],
        "budget_usd": config["budget_usd"],
        "alert_email": config["alert_email"],
        "billing_account_id": config["billing_account_id"],
        "project_id": config["project_id"],
        "admin_cidrs": config["admin_cidrs"],
    }
    tfvars_path(config).write_text(json.dumps(values, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def tf(config, *args, capture=False, check=True):
    return run(["terraform", f"-chdir={stack_dir(config)}", *args], capture=capture, check=check)


def tf_output(config, name):
    return tf(config, "output", "-raw", name, capture=True, check=False)


def preflight(config, need_docker=True):
    provider, platform = config["provider"], config["platform"]
    tools = ["terraform"]
    if need_docker:
        tools.append("docker")
    tools.append({"aws": "aws", "azure": "az", "gcp": "gcloud"}[provider])
    if platform in K8S_PLATFORMS:
        tools.append("kubectl")
    for name in tools:
        tool(name)

    if provider == "aws":
        run(["aws", "sts", "get-caller-identity", "--output", "json"], capture=True)
    elif provider == "azure":
        run(["az", "account", "show", "--output", "none"], capture=True)
    else:
        run(["gcloud", "auth", "list", "--filter=status:ACTIVE", "--format=value(account)"], capture=True)
    print("Tools and cloud session: OK.")


def ensure_lab_folder(config):
    """Creates the lab folder and INVENTARIO.md before creating resources."""
    folder = lab_dir(config)
    folder.mkdir(parents=True, exist_ok=True)
    inventory = folder / "INVENTARIO.md"
    if not inventory.exists():
        inventory.write_text(
            "\n".join(
                [
                    f"# Inventory — {config['name_prefix']}",
                    f"- Objective: PHP security demo (simulation) on {CLOUDS[config['provider']]['label']}",
                    f"- Owner: {config['owner']}",
                    f"- Environment: {config['provider']} / {config['region']} / {config['platform']}",
                    "- Identity used: operator local session (see cloud CLI)",
                    f"- Name prefix: {config['name_prefix']}",
                    f"- Start date: {dt.date.today().isoformat()}   Status: ACTIVE",
                    "",
                    "| # | Type | Name / ID | Location | Created or Used | Tag | Depends on | Date | Status |",
                    "|---|---|---|---|---|---|---|---|---|",
                    "",
                ]
            ),
            encoding="utf-8",
        )
    return inventory


def update_inventory(config):
    """Appends to INVENTARIO.md the list of resources Terraform reports in state."""
    inventory = ensure_lab_folder(config)
    state = tf(config, "state", "list", capture=True, check=False)
    rows = [line.strip() for line in state.splitlines() if line.strip()]
    stamp = dt.date.today().isoformat()
    lines = [
        "",
        f"## Resources per Terraform state ({stamp})",
        "",
        "| # | Type | Name / ID | Location | Created or Used | Tag | Depends on | Date | Status |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for number, address in enumerate(rows, 1):
        kind = address.split(".")[0]
        lines.append(f"| {number} | {kind} | `{address}` | {config['region']} | Created | created_by={config['owner']} (labels/tags) | - | {stamp} | ACTIVE |")
    inventory.write_text(inventory.read_text(encoding="utf-8") + "\n".join(lines) + "\n", encoding="utf-8")
    print(f"Inventory updated: {inventory.relative_to(ROOT)}")


def image_uri(config, registry_url, tag):
    return f"{registry_url}:{tag}"


def docker_login(config, registry_url):
    provider = config["provider"]
    host = registry_url.split("/")[0]
    if provider == "aws":
        password = run(["aws", "ecr", "get-login-password", "--region", config["region"]], capture=True)
        run(["docker", "login", "--username", "AWS", "--password-stdin", host], stdin=password)
    elif provider == "azure":
        run(["az", "acr", "login", "--name", host.split(".")[0]], capture=True)
    else:
        run(["gcloud", "auth", "configure-docker", host, "--quiet"], capture=True)


def build_and_push(config, registry_url):
    tag = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S")
    image = image_uri(config, registry_url, tag)
    docker_login(config, registry_url)
    print(f"Building image {image} ...")
    dockerfile = DOCKERFILES.get(config.get("demo_mode", "safe-simulation"), "Dockerfile")
    run(["docker", "build", "-f", str(ROOT / "app" / dockerfile), "-t", image, str(ROOT)])
    print("Pushing to the private registry ...")
    run(["docker", "push", image])
    return image


def kubeconfig(config):
    command = tf_output(config, "kubeconfig_command")
    parts = command.split()
    if not parts:
        print("No kubeconfig_command in state (partial or already-destroyed infra); skipping kubectl.")
        return False
    run(parts)
    return True


def render_k8s(config, image):
    """Copies the manifests to build/k8s replacing the markers."""
    target = BUILD_DIR / "k8s"
    target.mkdir(parents=True, exist_ok=True)
    replacements = {
        "__OWNER__": config["owner"],
        "__EXPIRES_AT__": config["expires_at"],
        "__REPLICAS__": str(config["replicas"]),
        "__IMAGE__": image,
    }
    for source in sorted(K8S_SRC.glob("*.yaml")):
        text = source.read_text(encoding="utf-8")
        for marker, value in replacements.items():
            text = text.replace(marker, value)
        (target / source.name).write_text(text, encoding="utf-8")
    return target


def wait_for_app_url(config, timeout=600):
    deadline = time.time() + timeout
    print("Waiting for the Kubernetes load balancer IP or hostname ...")
    while time.time() < deadline:
        address = run(
            ["kubectl", "-n", K8S_NAMESPACE, "get", "service", APP_TAG, "-o",
             "jsonpath={.status.loadBalancer.ingress[0].hostname}{.status.loadBalancer.ingress[0].ip}"],
            capture=True,
            check=False,
        )
        if address:
            return f"http://{address}"
        time.sleep(15)
    die("the balancer did not receive an address in the expected time. Check 'kubectl -n php-flaws-demo get svc'.")


def app_url(config):
    if config["platform"] in K8S_PLATFORMS:
        return wait_for_app_url(config)
    return tf_output(config, "app_url")


def health_check(url):
    for _ in range(30):
        try:
            with urllib.request.urlopen(f"{url}/healthz", timeout=10) as resp:
                if resp.status == 200:
                    return True
        except OSError:
            time.sleep(10)
    return False


# --------------------------------------------------------------------------- actions

def action_plan(config):
    preflight(config, need_docker=False)
    write_tfvars(config)
    tf(config, "init", "-input=false")
    tf(config, "plan", "-input=false", "-var-file=terraform.tfvars.json")


def action_deploy(config):
    preflight(config)
    show(config)
    if not confirm_word(
        config["name_prefix"],
        "This will create real resources in the current session's account/project and may incur costs.",
    ):
        print("Cancelled.")
        return
    if config.get("demo_mode") == BASELINE_MODE:
        die("the 'careless prod' profile (unhardened) is not deployed to the cloud from this menu: it enables egress and command execution with no containment and could pivot into the account. Use it with 'local-cluster' (or 'local').")
    if config.get("demo_mode") == "vulnerable-php":
        if config["platform"] not in VULN_PLATFORMS:
            die("the vulnerable profile is only enabled on VM (EC2, Azure VM, Compute Engine) and Kubernetes (EKS, AKS, GKE).")
        if not confirm_word(
            "DEPLOY-VULNERABLE",
            "WARNING: this will publish a vulnerable PHP runtime. Isolation: seccomp jail (escape syscalls denied), no shell or extra binaries, PHP command functions disabled, egress deny (K8s) or NSG/firewall 443+DNS (VM), no cloud identity or root.",
        ):
            print("Cancelled.")
            return
    ensure_lab_folder(config)
    write_tfvars(config)
    tf(config, "init", "-input=false")

    # Phase 1: only the private registry, so the image can be pushed before the workload.
    print("\nPhase 1/3: creating the private registry ...")
    tf(config, "apply", "-input=false", "-auto-approve", "-var-file=terraform.tfvars.json",
       f"-target={CLOUDS[config['provider']]['registry_address']}")
    registry_url = tf_output(config, "registry_url")

    # Phase 2: build and push the image.
    print("\nPhase 2/3: building and pushing the image ...")
    image = build_and_push(config, registry_url)

    # Phase 3: full infrastructure.
    print("\nPhase 3/3: applying the full infrastructure ...")
    write_tfvars(config, image=image)
    tf(config, "apply", "-input=false", "-auto-approve", "-var-file=terraform.tfvars.json")

    if config["platform"] in K8S_PLATFORMS:
        print("\nConfiguring kubectl and applying the manifests ...")
        kubeconfig(config)
        manifests = render_k8s(config, image)
        run(["kubectl", "apply", "-f", str(manifests)])
        run(["kubectl", "-n", K8S_NAMESPACE, "rollout", "status", f"deployment/{APP_TAG}", "--timeout=300s"])

    url = app_url(config)
    print(f"\nPublic URL: {url}")
    if health_check(url):
        print("/healthz check: OK.")
    else:
        print("/healthz check: no response yet. It may take a few minutes to propagate.")
    update_inventory(config)


def action_destroy(config):
    preflight(config)
    if not confirm_word(config["name_prefix"], "This will delete all resources of the demo environment."):
        print("Cancelled.")
        return
    write_tfvars(config)
    tf(config, "init", "-input=false")
    if config["platform"] in K8S_PLATFORMS and kubeconfig(config):
        # Delete the LoadBalancer Service first so the provider releases its balancer.
        manifests = BUILD_DIR / "k8s"
        if manifests.exists():
            run(["kubectl", "delete", "-f", str(manifests), "--ignore-not-found", "--wait=true"], check=False)
    tf(config, "destroy", "-input=false", "-auto-approve", "-var-file=terraform.tfvars.json")
    inventory = lab_dir(config) / "INVENTARIO.md"
    if inventory.exists():
        stamp = dt.date.today().isoformat()
        text = inventory.read_text(encoding="utf-8").replace("Status: ACTIVE", f"Status: DELETED ({stamp})")
        inventory.write_text(text, encoding="utf-8")
    print("Environment destroyed. Check that no resources tagged created_by remain.")


def action_local(config):
    tool("docker")
    name = f"{APP_TAG}-local"
    image = f"{APP_TAG}:local"
    demo_mode = config.get("demo_mode", "safe-simulation")
    hardened_vuln = demo_mode == "vulnerable-php"
    baseline = demo_mode == BASELINE_MODE
    if hardened_vuln and config["platform"] not in VULN_PLATFORMS:
        die("the hardened vulnerable profile is only enabled on VM and Kubernetes; use 'careless prod' or the safe simulation otherwise.")
    dockerfile = DOCKERFILES[demo_mode]
    seccomp_profile = ROOT / "app" / "seccomp-vulnerable.json"
    run(["docker", "build", "-f", str(ROOT / "app" / dockerfile), "-t", image, str(ROOT)])
    run(["docker", "rm", "-f", name], check=False)
    if baseline:
        # Careless prod: root, open egress, commands enabled, no seccomp or read-only.
        print("WARNING: 'careless prod' profile with NO hardening (root, open egress, command execution enabled). Local machine only.")
        run([
            "docker", "run", "-d", "--name", name,
            "-p", "127.0.0.1:8080:8080",
            "--pids-limit", "200",
            "--memory", "512m",
            image,
        ])
    else:
        network = f"{APP_TAG}-internal"
        if hardened_vuln and not run(["docker", "network", "inspect", network], capture=True, check=False):
            run(["docker", "network", "create", "--driver", "bridge", "--internal", network])
        run([
            "docker", "run", "-d", "--name", name,
            "-p", "127.0.0.1:8080:8080",
            *( ["--network", network] if hardened_vuln else [] ),
            "--read-only", "--tmpfs", "/tmp",
            "--user", "101:101",
            "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges",
            *( ["--security-opt", f"seccomp={seccomp_profile}"] if hardened_vuln else [] ),
            "--pids-limit", "100",
            "--memory", "256m",
            image,
        ])
    if health_check("http://localhost:8080"):
        print("\nStore available on this machine only: http://localhost:8080")
    else:
        print("\nThe container did not respond on /healthz. Check: docker logs " + name)
    print(f"Stop: docker rm -f {name}")


LOCAL_CLUSTER_PREREQS = """\
Local cluster with kind — requirements:
  Applications:
    - Docker running (the kind cluster runs as Docker containers).
    - kind  (https://kind.sigs.k8s.io) — creates the local Kubernetes cluster.
    - kubectl (already present) — applies the manifests.
  Machine resources:
    - ~2 vCPU and ~2 GB of free RAM for the kind node + the app (1 replica).
    - Port 8080/TCP free on 127.0.0.1 (kind maps it to NodePort 30080).
  What gets created (all local, nothing in the cloud):
    - 1 kind cluster named 'php-flaws-demo' (control-plane container).
    - namespace 'php-flaws-demo', Deployment (1 replica), NodePort Service.
    - The image is built locally and loaded into the cluster with 'kind load'.
  None of this uses cloud credentials or creates billable resources.
"""


def render_local_cluster(config, image):
    """Renders the local cluster manifests into build/local-cluster/."""
    demo_mode = config.get("demo_mode", "safe-simulation")
    deployment = "20-deployment-baseline.yaml" if demo_mode == BASELINE_MODE else "20-deployment-hardened.yaml"
    target = BUILD_DIR / "local-cluster"
    target.mkdir(parents=True, exist_ok=True)
    replacements = {"__OWNER__": config.get("owner", "Fgiraldo"), "__IMAGE__": image}
    for name in ("00-namespace.yaml", deployment, "30-service.yaml"):
        text = (LOCAL_CLUSTER_SRC / "manifests" / name).read_text(encoding="utf-8")
        for marker, value in replacements.items():
            text = text.replace(marker, value)
        out = target / name.replace("-baseline", "").replace("-hardened", "")
        out.write_text(text, encoding="utf-8")
    return target


def action_local_cluster(config):
    print(LOCAL_CLUSTER_PREREQS)
    tool("docker")
    tool("kubectl")
    kind = shutil.which("kind")
    if not kind:
        die("'kind' is missing. Install it and retry:\n"
            "  Linux:  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.25.0/kind-linux-amd64 && chmod +x ./kind && mkdir -p ~/.local/bin && mv ./kind ~/.local/bin/\n"
            "  macOS:  brew install kind\n"
            "  Docs:   https://kind.sigs.k8s.io/docs/user/quick-start/#installation")
    demo_mode = config.get("demo_mode", "safe-simulation")
    if demo_mode == "vulnerable-php":
        print("Note: on kind the network hardening (NetworkPolicy/egress-deny) does NOT apply (kindnet does not implement it). The rest of the hardening does.")
    if demo_mode == BASELINE_MODE and not confirm_word(
        "LOCAL-BASELINE",
        "'Careless prod' profile with NO hardening in the local cluster: root, open egress, command execution. On your machine only.",
    ):
        print("Cancelled.")
        return
    image = f"{APP_TAG}:local"
    dockerfile = DOCKERFILES[demo_mode]
    print(f"\nBuilding local image ({dockerfile}) ...")
    run(["docker", "build", "-f", str(ROOT / "app" / dockerfile), "-t", image, str(ROOT)])
    existing = run([kind, "get", "clusters"], capture=True, check=False) or ""
    if KIND_CLUSTER not in existing.split():
        print(f"Creating kind cluster '{KIND_CLUSTER}' ...")
        run([kind, "create", "cluster", "--name", KIND_CLUSTER, "--config", str(LOCAL_CLUSTER_SRC / "kind-config.yaml")])
    else:
        print(f"kind cluster '{KIND_CLUSTER}' already exists; reusing it.")
    print("Loading the image into the cluster ...")
    run([kind, "load", "docker-image", image, "--name", KIND_CLUSTER])
    context = f"kind-{KIND_CLUSTER}"
    manifests = render_local_cluster(config, image)
    run(["kubectl", "--context", context, "apply", "-f", str(manifests)])
    run(["kubectl", "--context", context, "-n", K8S_NAMESPACE, "rollout", "status",
         f"deployment/{APP_TAG}", "--timeout=180s"])
    url = "http://localhost:8080"
    print(f"\nLocal URL: {url}")
    if health_check(url):
        print("/healthz check: OK.")
    else:
        print(f"/healthz check: no response yet. Check: kubectl --context {context} -n {K8S_NAMESPACE} get pods")
    print(f"\nDelete the local cluster: python deploy.py local-cluster-down  (or: kind delete cluster --name {KIND_CLUSTER})")


def action_local_cluster_down(config=None):
    kind = shutil.which("kind")
    if not kind:
        die("'kind' is missing from PATH.")
    run([kind, "delete", "cluster", "--name", KIND_CLUSTER])
    print("Local cluster deleted.")


MENU = [
    ("1", "Configure deployment (cloud, infrastructure, parameters)"),
    ("2", "Show saved configuration"),
    ("3", "Test locally with Docker (single container)"),
    ("4", "Plan (terraform plan, no changes)"),
    ("5", "Deploy to the cloud"),
    ("6", "Destroy the environment"),
    ("7", "Local cluster with kind (bring up)"),
    ("8", "Local cluster with kind (delete)"),
    ("0", "Exit"),
]


def interactive():
    print("PHP Flaws Demo — Mercado Norte\nSafe profile by default; vulnerable PHP on VM and Kubernetes with explicit confirmation.")
    while True:
        print("\nMain menu")
        for key, label in MENU:
            print(f"  {key}) {label}")
        choice = input("> ").strip()
        config = load_config()
        if choice == "0":
            return 0
        if choice == "1":
            configure(config)
            continue
        if config is None and choice in {"2", "3", "4", "5", "6", "7"}:
            print("Configure the deployment first (option 1).")
            continue
        try:
            if choice == "2":
                show(config)
            elif choice == "3":
                action_local(config)
            elif choice == "4":
                action_plan(config)
            elif choice == "5":
                action_deploy(config)
            elif choice == "6":
                action_destroy(config)
            elif choice == "7":
                action_local_cluster(config)
            elif choice == "8":
                action_local_cluster_down(config)
            else:
                print("Invalid option.")
        except KeyboardInterrupt:
            print("\nOperation interrupted.")
        except SystemExit as exc:
            if exc.code not in (0, None):
                print("The operation did not complete. Fix the error and try again.")


def main(argv):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Deployment of Mercado Norte (PHP Flaws Demo).")
    parser.add_argument("command", nargs="?", choices=["configure", "show", "local", "plan", "deploy", "destroy", "local-cluster", "local-cluster-down"])
    args = parser.parse_args(argv)
    if args.command is None:
        return interactive()
    if args.command == "configure":
        configure(load_config())
        return 0
    if args.command == "local-cluster-down":
        action_local_cluster_down()
        return 0
    config = require_config()
    actions = {
        "show": show,
        "local": action_local,
        "plan": action_plan,
        "deploy": action_deploy,
        "destroy": action_destroy,
        "local-cluster": action_local_cluster,
    }
    actions[args.command](config)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
