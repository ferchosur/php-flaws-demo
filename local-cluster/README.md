# Clúster local (kind) — Mercado Norte PHP Flaws Demo

Escenario para correr la demo en un **clúster Kubernetes local** sobre Docker, sin
infraestructura en la nube. Pensado para probar el exploit de CVE-2026-109618 /
CVE-2026-109619 en el perfil **"prod descuidado"** (sin endurecer) en tu propio equipo.

## Aplicaciones requeridas

| Aplicación | Para qué | Instalación |
|---|---|---|
| **Docker** (en marcha) | kind corre el clúster como contenedores Docker; también construye la imagen. | https://docs.docker.com/engine/install/ |
| **kind** ≥ 0.24 | Crea el clúster Kubernetes local. | `curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.25.0/kind-linux-amd64 && chmod +x ./kind && mkdir -p ~/.local/bin && mv ./kind ~/.local/bin/` · macOS: `brew install kind` |
| **kubectl** | Aplica los manifiestos y consulta el estado. | https://kubernetes.io/docs/tasks/tools/ |
| **Python** ≥ 3.11 | Ejecuta `deploy.py`. | — |

`deploy.py` comprueba estas herramientas y, si falta kind, imprime el comando de instalación.

## Recursos del equipo

- **~2 vCPU** y **~2 GB de RAM** libres (nodo kind + app a 1 réplica).
- **Puerto `8080/TCP` libre en `127.0.0.1`** — kind lo mapea al NodePort `30080`.
- ~1 GB de disco para la imagen de nodo de kind (`kindest/node`), se descarga una vez.

## Qué se crea (todo local, nada facturable)

| Recurso | Nombre | Notas |
|---|---|---|
| Clúster kind | `php-flaws-demo` | 1 nodo control-plane (contenedor Docker). |
| Namespace | `php-flaws-demo` | — |
| Deployment | `php-flaws-demo` | 1 réplica. Perfil baseline o endurecido según `demo_mode`. |
| Service | `php-flaws-demo` | `NodePort 30080` → `localhost:8080`. |
| Imagen | `php-flaws-demo:local` | Construida en local y cargada con `kind load docker-image`. |

No usa credenciales cloud ni crea recursos en ninguna nube.

## Uso

```sh
python deploy.py configure        # elige perfil del runtime (opción 2a):
                                  #   - vulnerable-baseline  (prod descuidado, recomendado aquí)
                                  #   - vulnerable-php        (endurecido, para el A/B)
                                  #   - safe-simulation
python deploy.py local-cluster        # construye, crea el clúster y despliega
#   -> URL local: http://localhost:8080
python deploy.py local-cluster-down   # borra el clúster local
```

En el menú interactivo son las opciones **7** (levantar) y **8** (borrar).

## Perfiles

| Perfil | securityContext | Red | Para qué |
|---|---|---|---|
| `vulnerable-baseline` | root, escalada permitida, fs de escritura, **seccomp Unconfined**, token de SA montado | **egreso abierto** (sin NetworkPolicy) | Imitar un prod sin endurecer: la explotación habilita shell, comandos (`system`, `exec`), `curl`/`nc` y movimiento lateral dentro del clúster. |
| `vulnerable-php` | no root (101), `cap-drop ALL`, fs de solo lectura, **seccomp RuntimeDefault**, sin token de SA | Ver nota | Lado "mitigado" del A/B: mismo bug, radio de impacto reducido. |

El manifiesto baseline es `manifests/20-deployment-baseline.yaml`; el endurecido,
`manifests/20-deployment-hardened.yaml`. `deploy.py` elige según `demo_mode`.

> **Nota sobre NetworkPolicy en kind:** el CNI por defecto (kindnet) **no** aplica
> NetworkPolicy. El `egress-deny` que sí funciona en la nube (GKE/AKS/EKS) **no** se
> reproduce en kind. En el perfil baseline da igual (el egreso está abierto a
> propósito); en el endurecido, el resto de los controles sí aplican, pero el
> aislamiento de red no. Para reproducir egress-deny en local habría que instalar
> Calico en el clúster kind.

## Diferencia con `python deploy.py local`

`local` corre **un solo contenedor** con `docker run` (útil para una prueba rápida).
`local-cluster` corre la app en un **clúster Kubernetes** real (kind), más cercano a
cómo se despliega en producción: Deployment, Service, probes y el mismo flujo de
manifiestos que la nube.

## Límite de la contención (prod descuidado)

El perfil baseline **permite ejecución de comandos y movimiento lateral dentro del
clúster local**. La contención real es que todo vive en tu equipo, en un clúster kind
efímero, sin credenciales cloud. No lo despliegues en la nube: `deploy.py` bloquea el
perfil baseline en `deploy` por ese motivo.
