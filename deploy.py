"""Menú de despliegue de Mercado Norte (PHP Flaws Demo).

Configura la nube y la infraestructura, construye la imagen, la publica en el
registro privado del proveedor y aplica Terraform. Solo usa la biblioteca
estándar de Python 3.11 o superior.

Uso:
    python deploy.py                 # menú interactivo
    python deploy.py show            # muestra la configuración guardada
    python deploy.py local           # construye y ejecuta la imagen con Docker
    python deploy.py plan            # terraform plan sin aplicar
    python deploy.py deploy          # despliega (pide confirmación explícita)
    python deploy.py destroy         # destruye el entorno (pide confirmación explícita)
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
            "ecs": ("ECS Fargate", "contenedores serverless detrás de un Application Load Balancer"),
            "ec2": ("EC2", "máquina virtual con Docker (cloud-init)"),
            "eks": ("EKS", "clúster Kubernetes gestionado"),
        },
        "registry_address": "aws_ecr_repository.app",
    },
    "azure": {
        "label": "Azure",
        "default_region": "eastus",
        "platforms": {
            "container-apps": ("Container Apps", "contenedores serverless con ingreso HTTPS"),
            "vm": ("Virtual Machines", "máquina virtual Linux con Docker (cloud-init)"),
            "aks": ("AKS", "clúster Kubernetes gestionado"),
        },
        "registry_address": "azurerm_container_registry.app",
    },
    "gcp": {
        "label": "GCP",
        "default_region": "us-central1",
        "platforms": {
            "cloud-run": ("Cloud Run", "contenedores serverless con HTTPS"),
            "compute-engine": ("Compute Engine", "máquina virtual con Container-Optimized OS"),
            "gke": ("GKE", "clúster Kubernetes gestionado"),
        },
        "registry_address": "google_artifact_registry_repository.app",
    },
}
K8S_PLATFORMS = {"eks", "aks", "gke"}
VM_PLATFORMS = {"ec2", "vm", "compute-engine"}
# El perfil PHP vulnerable solo se ofrece en VM y Kubernetes; el nivel serverless
# de contenedores (ECS Fargate, Container Apps, Cloud Run) se queda en simulación
# segura, porque no se puede aplicar la jaula seccomp ni el egress deny con el mismo control.
VULN_PLATFORMS = VM_PLATFORMS | K8S_PLATFORMS

DOCKERFILES = {
    "safe-simulation": "Dockerfile",
    "vulnerable-php": "Dockerfile-vulnerable",
    "vulnerable-baseline": "Dockerfile-vulnerable-baseline",
}
# Modo "prod descuidado": vulnerable y SIN endurecer. Habilita ejecución de
# comandos y movimiento lateral; solo para el clúster local o labs aislados.
BASELINE_MODE = "vulnerable-baseline"
KIND_CLUSTER = "php-flaws-demo"
LOCAL_CLUSTER_SRC = ROOT / "local-cluster"
SIZES = [("small", "Pequeño"), ("medium", "Mediano")]

REGION_RE = re.compile(r"^[a-z0-9-]{4,40}$")
PREFIX_RE = re.compile(r"^[a-z][a-z0-9-]{2,20}$")
OWNER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
CIDR_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$")


# --------------------------------------------------------------------------- utilidades

def die(message):
    print(f"\nError: {message}", file=sys.stderr)
    raise SystemExit(1)


def tool(name):
    path = shutil.which(name)
    if not path:
        die(f"no se encontró '{name}' en el PATH. Instálalo antes de continuar.")
    return path


def run(args, cwd=None, stdin=None, capture=False, check=True):
    """Ejecuta un comando sin shell. Los argumentos nunca se interpretan por la shell."""
    proc = subprocess.run(
        [tool(args[0]), *args[1:]],
        cwd=cwd,
        input=stdin,
        text=True,
        capture_output=capture,
    )
    if check and proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        die(f"'{' '.join(args[:3])}' terminó con código {proc.returncode}.\n{detail}")
    return proc.stdout.strip() if capture else proc


def ask(prompt, default=None, pattern=None, required=False, cast=str):
    suffix = f" [{default}]" if default not in (None, "") else ""
    while True:
        raw = input(f"{prompt}{suffix}: ").strip()
        if raw == "" and default is not None:
            raw = str(default)
        if raw == "":
            if required:
                print("Este valor es obligatorio.")
                continue
            return ""
        if pattern and not pattern.match(raw):
            print("Formato inválido. Revisa el ejemplo y vuelve a intentarlo.")
            continue
        try:
            return cast(raw)
        except ValueError:
            print("Valor no válido.")


def choose(title, options, default=None):
    """options: lista de (clave, etiqueta). Devuelve la clave elegida."""
    print(f"\n{title}")
    keys = [key for key, _ in options]
    for number, (key, label) in enumerate(options, 1):
        marker = " (actual)" if key == default else ""
        print(f"  {number}) {label}{marker}")
    while True:
        raw = input("> ").strip()
        if raw == "" and default in keys:
            return default
        if raw.isdigit() and 1 <= int(raw) <= len(keys):
            return keys[int(raw) - 1]
        print("Opción inválida. Intenta de nuevo.")


def confirm_word(word, message):
    print(f"\n{message}")
    typed = input(f"Escribe '{word}' para continuar (cualquier otra cosa cancela): ").strip()
    return typed == word


def load_config():
    if not CONFIG_PATH.exists():
        return None
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def save_config(config):
    CONFIG_PATH.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"\nConfiguración guardada en {CONFIG_PATH.name}.")


def require_config():
    config = load_config()
    if config is None:
        die("no existe deployment.json. Ejecuta primero la configuración (opción 1 del menú).")
    return config


def stack_dir(config):
    return ROOT / "infra" / config["provider"] / config["platform"]


def lab_dir(config):
    """Carpeta de laboratorio exigida por las reglas de labs: labs/<YYYY-MM>-<prefijo>/."""
    month = dt.date.today().strftime("%Y-%m")
    return ROOT / "labs" / f"{month}-{config['name_prefix']}"


def detect_public_ip():
    try:
        with urllib.request.urlopen("https://checkip.amazonaws.com", timeout=10) as resp:
            return resp.read().decode().strip()
    except OSError:
        return ""


# --------------------------------------------------------------------------- configuración

def configure(current):
    current = current or {}
    print("\n=== Configuración del despliegue ===")

    provider = choose(
        "1. Elige la nube",
        [(key, data["label"]) for key, data in CLOUDS.items()],
        default=current.get("provider"),
    )
    platforms = CLOUDS[provider]["platforms"]
    platform = choose(
        "2. Elige la infraestructura",
        [(key, f"{name}: {desc}") for key, (name, desc) in platforms.items()],
        default=current.get("platform") if current.get("provider") == provider else None,
    )
    demo_mode = "safe-simulation"
    if platform in VULN_PLATFORMS:
        demo_mode = choose(
            "2a. Perfil del runtime",
            [
                ("safe-simulation", "Simulación segura con nginx estático"),
                ("vulnerable-php", "PHP 8.5.11 vulnerable, endurecido con jaula seccomp (confirmación al desplegar)"),
                ("vulnerable-baseline", "PHP 8.5.11 vulnerable SIN endurecer (prod descuidado; preferible en clúster local)"),
            ],
            default=current.get("demo_mode", "safe-simulation") if current.get("platform") == platform else "safe-simulation",
        )
    same_cloud = current.get("provider") == provider
    region = ask(
        "3. Región",
        default=current.get("region") if same_cloud else CLOUDS[provider]["default_region"],
        pattern=REGION_RE,
    )
    name_prefix = ask("4. Prefijo de nombres (minúsculas y guiones)", default=current.get("name_prefix", "php-flaws-demo"), pattern=PREFIX_RE)
    owner = ask("5. Responsable (etiqueta created_by)", default=current.get("owner"), pattern=OWNER_RE, required=True)
    default_expiry = (dt.date.today() + dt.timedelta(days=7)).isoformat()
    expires_at = ask("6. Caduca el (YYYY-MM-DD)", default=current.get("expires_at", default_expiry), pattern=DATE_RE)
    size = choose("7. Tamaño de la carga", SIZES, default=current.get("size", "small"))
    replicas = ask("8. Réplicas (se ignora en VM, que crean una instancia)", default=current.get("replicas", 2), cast=int)
    if not 1 <= replicas <= 5:
        die("las réplicas deben estar entre 1 y 5.")
    budget_usd = ask("9. Presupuesto mensual en USD", default=current.get("budget_usd", 25), cast=float)
    alert_email = ask("10. Correo para alertas de presupuesto (vacío = sin alertas)", default=current.get("alert_email", ""))

    project_id = ""
    billing_account_id = ""
    if provider == "gcp":
        default_project = current.get("project_id") or ""
        if not default_project and shutil.which("gcloud"):
            default_project = run(["gcloud", "config", "get-value", "project"], capture=True, check=False).stdout.strip()
        project_id = ask("11. ID del proyecto GCP", default=default_project, required=True)
        billing_account_id = ask("12. ID de cuenta de facturación (vacío = sin presupuesto)", default=current.get("billing_account_id", ""))

    admin_cidrs = current.get("admin_cidrs", []) if same_cloud else []
    if platform in K8S_PLATFORMS:
        detected = detect_public_ip()
        suggestion = f"{detected}/32" if detected else ""
        cidr = ask("13. IP pública del operador para el API de Kubernetes (x.x.x.x/32)", default=(admin_cidrs[0] if admin_cidrs else suggestion), pattern=CIDR_RE, required=True)
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
    print("\nResumen")
    print(f"  Nube:            {cloud['label']}")
    print(f"  Infraestructura: {name} ({desc})")
    print(f"  Perfil de demo:  {config.get('demo_mode', 'safe-simulation')}")
    print(f"  Región:          {config['region']}")
    print(f"  Prefijo:         {config['name_prefix']}")
    print(f"  Responsable:     {config['owner']}  (created_by)")
    print(f"  Caduca:          {config['expires_at']}")
    print(f"  Tamaño/réplicas: {config['size']} / {config['replicas']}")
    print(f"  Presupuesto:     {config['budget_usd']} USD/mes")
    print(f"  Carpeta lab:     {lab_dir(config).relative_to(ROOT)}")


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
    print("Herramientas y sesión de la nube: OK.")


def ensure_lab_folder(config):
    """Crea la carpeta del laboratorio e INVENTARIO.md antes de crear recursos."""
    folder = lab_dir(config)
    folder.mkdir(parents=True, exist_ok=True)
    inventory = folder / "INVENTARIO.md"
    if not inventory.exists():
        inventory.write_text(
            "\n".join(
                [
                    f"# Inventario — {config['name_prefix']}",
                    f"- Objetivo: demo de seguridad PHP (simulación) sobre {CLOUDS[config['provider']]['label']}",
                    f"- Owner: {config['owner']}",
                    f"- Entorno: {config['provider']} / {config['region']} / {config['platform']}",
                    "- Identidad usada: sesión local del operador (ver CLI de la nube)",
                    f"- Prefijo de nombres: {config['name_prefix']}",
                    f"- Fecha inicio: {dt.date.today().isoformat()}   Estado: ACTIVO",
                    "",
                    "| # | Tipo | Nombre / ID | Ubicación | Creado o Usado | Tag | Depende de | Fecha | Estado |",
                    "|---|---|---|---|---|---|---|---|---|",
                    "",
                ]
            ),
            encoding="utf-8",
        )
    return inventory


def update_inventory(config):
    """Añade al INVENTARIO.md la lista de recursos que Terraform reporta en el estado."""
    inventory = ensure_lab_folder(config)
    state = tf(config, "state", "list", capture=True, check=False)
    rows = [line.strip() for line in state.splitlines() if line.strip()]
    stamp = dt.date.today().isoformat()
    lines = [
        "",
        f"## Recursos según el estado de Terraform ({stamp})",
        "",
        "| # | Tipo | Nombre / ID | Ubicación | Creado o Usado | Tag | Depende de | Fecha | Estado |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for number, address in enumerate(rows, 1):
        kind = address.split(".")[0]
        lines.append(f"| {number} | {kind} | `{address}` | {config['region']} | Creado | created_by={config['owner']} (labels/tags) | - | {stamp} | ACTIVO |")
    inventory.write_text(inventory.read_text(encoding="utf-8") + "\n".join(lines) + "\n", encoding="utf-8")
    print(f"Inventario actualizado: {inventory.relative_to(ROOT)}")


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
    print(f"Construyendo imagen {image} ...")
    dockerfile = DOCKERFILES.get(config.get("demo_mode", "safe-simulation"), "Dockerfile")
    run(["docker", "build", "-f", str(ROOT / "app" / dockerfile), "-t", image, str(ROOT)])
    print("Publicando en el registro privado ...")
    run(["docker", "push", image])
    return image


def kubeconfig(config):
    command = tf_output(config, "kubeconfig_command")
    parts = command.split()
    run(parts)


def render_k8s(config, image):
    """Copia los manifiestos a build/k8s sustituyendo los marcadores."""
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
    print("Esperando la IP o el nombre del balanceador de Kubernetes ...")
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
    die("el balanceador no recibió dirección en el tiempo esperado. Revisa 'kubectl -n php-flaws-demo get svc'.")


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


# --------------------------------------------------------------------------- acciones

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
        "Esto creará recursos reales en la cuenta/proyecto de la sesión actual y puede generar costos.",
    ):
        print("Cancelado.")
        return
    if config.get("demo_mode") == BASELINE_MODE:
        die("el perfil 'prod descuidado' (sin endurecer) no se despliega en la nube desde este menú: habilita egreso y ejecución de comandos sin contención y podría pivotar hacia la cuenta. Úsalo con 'local-cluster' (o 'local').")
    if config.get("demo_mode") == "vulnerable-php":
        if config["platform"] not in VULN_PLATFORMS:
            die("el perfil vulnerable solo está habilitado en VM (EC2, Azure VM, Compute Engine) y Kubernetes (EKS, AKS, GKE).")
        if not confirm_word(
            "DEPLOY-VULNERABLE",
            "ATENCIÓN: publicará un runtime PHP vulnerable. Aislamiento: jaula seccomp (syscalls de escape denegadas), sin shell ni binarios extra, funciones de comando PHP desactivadas, egress deny (K8s) o NSG/firewall 443+DNS (VM), sin identidad cloud ni root.",
        ):
            print("Cancelado.")
            return
    ensure_lab_folder(config)
    write_tfvars(config)
    tf(config, "init", "-input=false")

    # Fase 1: solo el registro privado, para poder publicar la imagen antes del workload.
    print("\nFase 1/3: creando el registro privado ...")
    tf(config, "apply", "-input=false", "-auto-approve", "-var-file=terraform.tfvars.json",
       f"-target={CLOUDS[config['provider']]['registry_address']}")
    registry_url = tf_output(config, "registry_url")

    # Fase 2: construir y publicar la imagen.
    print("\nFase 2/3: construyendo y publicando la imagen ...")
    image = build_and_push(config, registry_url)

    # Fase 3: infraestructura completa.
    print("\nFase 3/3: aplicando la infraestructura completa ...")
    write_tfvars(config, image=image)
    tf(config, "apply", "-input=false", "-auto-approve", "-var-file=terraform.tfvars.json")

    if config["platform"] in K8S_PLATFORMS:
        print("\nConfigurando kubectl y aplicando los manifiestos ...")
        kubeconfig(config)
        manifests = render_k8s(config, image)
        run(["kubectl", "apply", "-f", str(manifests)])
        run(["kubectl", "-n", K8S_NAMESPACE, "rollout", "status", f"deployment/{APP_TAG}", "--timeout=300s"])

    url = app_url(config)
    print(f"\nURL pública: {url}")
    if health_check(url):
        print("Comprobación /healthz: OK.")
    else:
        print("Comprobación /healthz: sin respuesta todavía. Puede tardar unos minutos en propagarse.")
    update_inventory(config)


def action_destroy(config):
    preflight(config)
    if not confirm_word(config["name_prefix"], "Esto eliminará todos los recursos del entorno de la demo."):
        print("Cancelado.")
        return
    write_tfvars(config)
    tf(config, "init", "-input=false")
    if config["platform"] in K8S_PLATFORMS:
        # Eliminar primero el Service de tipo LoadBalancer para que el proveedor libere su balanceador.
        kubeconfig(config)
        manifests = BUILD_DIR / "k8s"
        if manifests.exists():
            run(["kubectl", "delete", "-f", str(manifests), "--ignore-not-found", "--wait=true"], check=False)
    tf(config, "destroy", "-input=false", "-auto-approve", "-var-file=terraform.tfvars.json")
    inventory = lab_dir(config) / "INVENTARIO.md"
    if inventory.exists():
        stamp = dt.date.today().isoformat()
        text = inventory.read_text(encoding="utf-8").replace("Estado: ACTIVO", f"Estado: ELIMINADO ({stamp})")
        inventory.write_text(text, encoding="utf-8")
    print("Entorno destruido. Revisa que no queden recursos etiquetados con created_by.")


def action_local(config):
    tool("docker")
    name = f"{APP_TAG}-local"
    image = f"{APP_TAG}:local"
    demo_mode = config.get("demo_mode", "safe-simulation")
    hardened_vuln = demo_mode == "vulnerable-php"
    baseline = demo_mode == BASELINE_MODE
    if hardened_vuln and config["platform"] not in VULN_PLATFORMS:
        die("el perfil vulnerable endurecido solo está habilitado en VM y Kubernetes; usa 'prod descuidado' o la simulación segura en el resto.")
    dockerfile = DOCKERFILES[demo_mode]
    seccomp_profile = ROOT / "app" / "seccomp-vulnerable.json"
    run(["docker", "build", "-f", str(ROOT / "app" / dockerfile), "-t", image, str(ROOT)])
    run(["docker", "rm", "-f", name], check=False)
    if baseline:
        # Prod descuidado: root, egreso abierto, comandos habilitados, sin seccomp ni read-only.
        print("ADVERTENCIA: perfil 'prod descuidado' SIN endurecer (root, egreso abierto, ejecución de comandos habilitada). Solo para el equipo local.")
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
        print("\nTienda disponible solo en este equipo: http://localhost:8080")
    else:
        print("\nEl contenedor no respondió en /healthz. Revisa: docker logs " + name)
    print(f"Detener: docker rm -f {name}")


LOCAL_CLUSTER_PREREQS = """\
Clúster local con kind — requisitos:
  Aplicaciones:
    - Docker en marcha (el clúster kind corre como contenedores Docker).
    - kind  (https://kind.sigs.k8s.io) — crea el clúster Kubernetes local.
    - kubectl (ya presente) — aplica los manifiestos.
  Recursos del equipo:
    - ~2 vCPU y ~2 GB de RAM libres para el nodo kind + la app (1 réplica).
    - Puerto 8080/TCP libre en 127.0.0.1 (kind lo mapea al NodePort 30080).
  Qué se crea (todo local, nada en la nube):
    - 1 clúster kind llamado 'php-flaws-demo' (contenedor control-plane).
    - namespace 'php-flaws-demo', Deployment (1 réplica), Service NodePort.
    - La imagen se construye local y se carga al clúster con 'kind load'.
  Nada de esto usa credenciales cloud ni crea recursos facturables.
"""


def render_local_cluster(config, image):
    """Renderiza los manifiestos del clúster local a build/local-cluster/."""
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
        die("falta 'kind'. Instálalo y repite:\n"
            "  Linux:  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64 && chmod +x ./kind && mkdir -p ~/.local/bin && mv ./kind ~/.local/bin/\n"
            "  macOS:  brew install kind\n"
            "  Docs:   https://kind.sigs.k8s.io/docs/user/quick-start/#installation")
    demo_mode = config.get("demo_mode", "safe-simulation")
    if demo_mode == "vulnerable-php":
        print("Nota: en kind el endurecimiento de red (NetworkPolicy/egress-deny) NO aplica (kindnet no las implementa). El resto del endurecimiento sí.")
    if demo_mode == BASELINE_MODE and not confirm_word(
        "LOCAL-BASELINE",
        "Perfil 'prod descuidado' SIN endurecer en el clúster local: root, egreso abierto, ejecución de comandos. Solo en tu equipo.",
    ):
        print("Cancelado.")
        return
    image = f"{APP_TAG}:local"
    dockerfile = DOCKERFILES[demo_mode]
    print(f"\nConstruyendo imagen local ({dockerfile}) ...")
    run(["docker", "build", "-f", str(ROOT / "app" / dockerfile), "-t", image, str(ROOT)])
    existing = run([kind, "get", "clusters"], capture=True, check=False) or ""
    if KIND_CLUSTER not in existing.split():
        print(f"Creando clúster kind '{KIND_CLUSTER}' ...")
        run([kind, "create", "cluster", "--name", KIND_CLUSTER, "--config", str(LOCAL_CLUSTER_SRC / "kind-config.yaml")])
    else:
        print(f"Clúster kind '{KIND_CLUSTER}' ya existe; se reutiliza.")
    print("Cargando la imagen al clúster ...")
    run([kind, "load", "docker-image", image, "--name", KIND_CLUSTER])
    context = f"kind-{KIND_CLUSTER}"
    manifests = render_local_cluster(config, image)
    run(["kubectl", "--context", context, "apply", "-f", str(manifests)])
    run(["kubectl", "--context", context, "-n", K8S_NAMESPACE, "rollout", "status",
         f"deployment/{APP_TAG}", "--timeout=180s"])
    url = "http://localhost:8080"
    print(f"\nURL local: {url}")
    if health_check(url):
        print("Comprobación /healthz: OK.")
    else:
        print(f"Comprobación /healthz: sin respuesta todavía. Revisa: kubectl --context {context} -n {K8S_NAMESPACE} get pods")
    print(f"\nBorrar el clúster local: python deploy.py local-cluster-down  (o: kind delete cluster --name {KIND_CLUSTER})")


def action_local_cluster_down(config=None):
    kind = shutil.which("kind")
    if not kind:
        die("falta 'kind' en el PATH.")
    run([kind, "delete", "cluster", "--name", KIND_CLUSTER])
    print("Clúster local borrado.")


MENU = [
    ("1", "Configurar despliegue (nube, infraestructura, parámetros)"),
    ("2", "Ver configuración guardada"),
    ("3", "Probar localmente con Docker (un contenedor)"),
    ("4", "Planificar (terraform plan, sin cambios)"),
    ("5", "Desplegar en la nube"),
    ("6", "Destruir el entorno"),
    ("7", "Clúster local con kind (levantar)"),
    ("8", "Clúster local con kind (borrar)"),
    ("0", "Salir"),
]


def interactive():
    print("PHP Flaws Demo — Mercado Norte\nPerfil seguro por defecto; PHP vulnerable en VM y Kubernetes con confirmación explícita.")
    while True:
        print("\nMenú principal")
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
            print("Primero configura el despliegue (opción 1).")
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
                print("Opción inválida.")
        except KeyboardInterrupt:
            print("\nOperación interrumpida.")
        except SystemExit as exc:
            if exc.code not in (0, None):
                print("La operación no se completó. Corrige el error y vuelve a intentarlo.")


def main(argv):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Despliegue de Mercado Norte (PHP Flaws Demo).")
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
