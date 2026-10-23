# PHP Flaws Demo — Mercado Norte

Demo reutilizable para presentar CVE-2026-109618 y CVE-2026-109619 en una tienda ficticia. La experiencia comercial es HTML/JS estático. El perfil predeterminado no incluye PHP; en VM (EC2, Azure VM, Compute Engine) y Kubernetes (EKS, AKS, GKE) se puede activar de forma explícita un runtime PHP previo al parche para el laboratorio, aislado con una jaula seccomp. Ningún perfil contiene payloads de explotación. El nivel serverless de contenedores (ECS Fargate, Container Apps, Cloud Run) se queda siempre en simulación segura.

## Qué incluye

| Parte | Ruta | Descripción |
|---|---|---|
| Tienda | `web/` | HTML, CSS y JS estáticos sin dependencias ni CDN. Catálogo, carrito, checkout simulado y página de demo de seguridad. El recibo guarda solo el código, productos y total; no persiste nombre, correo ni dirección. |
| Imagen segura | `app/Dockerfile` | nginx sin privilegios, sin módulos de script, sin shell tras el build. Predeterminada para todas las nubes y plataformas. |
| Runtime vulnerable | `app/Dockerfile-vulnerable`, `app/vulnerable/` | Perfil optativo PHP 8.5.11 para VM y Kubernetes, previo a la versión corregida 8.5.12. El recorrido de interfaz no envía exploits; el runtime sí procesa HTTP. |
| Jaula seccomp | `app/seccomp-vulnerable.json` | Lista de denegación de syscalls de escape (ptrace, mount, namespaces, carga de módulos, kexec, bpf) aplicada al runtime vulnerable en VM. Sin privilegios: conserva UID 101 y `cap-drop ALL`. |
| Menú | `deploy.py` | Menú interactivo (stdlib de Python 3.11+): configura, prueba en local, planifica, despliega y destruye. |
| Infraestructura | `infra/<nube>/<plataforma>/` | Nueve raíces de Terraform con el mismo contrato de variables. |
| Kubernetes | `k8s/` | Manifiestos del namespace, con Pod Security `restricted` y red por defecto denegada. |

## Uso rápido

```sh
python deploy.py            # menú principal
python deploy.py local      # imagen en Docker con el mismo hardening que en la nube
```

Sin Docker, la tienda puede previsualizarse con `python -m http.server 8000 -d web`. Esa vista no aplica las cabeceras ni el endurecimiento de nginx.

### Menú

1. **Configurar**: nube (AWS, Azure, GCP), infraestructura, región, prefijo, responsable (`created_by`), fecha de caducidad, tamaño, réplicas, presupuesto, correo de alertas, proyecto (GCP) y, en Kubernetes, la IP del operador para el API. VM y Kubernetes permiten elegir entre simulación segura y runtime PHP vulnerable.
2. **Ver configuración**.
3. **Probar en local** con Docker.
4. **Planificar** (`terraform plan`, sin cambios).
5. **Desplegar**: pide escribir el prefijo para confirmar.
6. **Destruir**: pide confirmación igual.

`deployment.json` guarda la configuración y no contiene secretos.

### Infraestructura disponible

| Nube | Serverless contenedor | Máquina virtual | Kubernetes |
|---|---|---|---|
| AWS | ECS Fargate + ALB | EC2 (cloud-init) | EKS |
| Azure | Container Apps | Virtual Machine (cloud-init) | AKS |
| GCP | Cloud Run | Compute Engine (COS) | GKE |

No se ofrecen Lambda, Azure Functions ni Cloud Functions. Un sitio que sirve HTML y muchos recursos estáticos se ajusta mejor a contenedores serverless, que cumplen el mismo rol de "función" sin el manejo de paquetes.

### Flujo de despliegue

1. Crea `labs/<YYYY-MM>-<prefijo>/` con `INVENTARIO.md` antes de crear recursos.
2. Terraform crea solo el registro privado (`-target`).
3. Construye la imagen con `app/Dockerfile` y la publica con un tag por marca de tiempo (inmutable en la práctica).
4. Terraform aplica la infraestructura completa con esa imagen.
5. En Kubernetes, `kubectl apply` de los manifiestos renderizados en `build/k8s/`.
6. Actualiza `INVENTARIO.md` con los recursos del estado de Terraform.

El perfil PHP vulnerable se ofrece en VM (EC2, Azure VM, Compute Engine) y Kubernetes (EKS, AKS, GKE). El workload es público y HTTP; el modo vulnerable requiere escribir `DEPLOY-VULNERABLE` además de la confirmación normal. El contenedor ejecuta como UID 101, sin capacidades, con raíz de solo lectura, sin shell, funciones PHP de comandos desactivadas y sin identidad cloud. El aislamiento adicional depende de la plataforma:

- **VM (EC2, Azure VM):** jaula seccomp `app/seccomp-vulnerable.json`. Deniega los primitivos de kernel de escape y movimiento lateral (`ptrace`, `mount`/`umount2`, `pivot_root`, `chroot`, `setns`, `unshare`, carga de módulos, `kexec`, `bpf`, `perf_event_open`). `execve` queda permitido a la fuerza —el runtime lo necesita para arrancar `php`—, así que la ejecución de comandos se bloquea en la capa PHP (`disable_functions`) y porque la imagen no tiene shell ni ningún otro binario que lanzar. Egreso restringido por NSG/firewall a 443 y DNS. Compute Engine (COS/konlet) no permite un perfil seccomp personalizado por declaración de contenedor (ver residuales).
- **Kubernetes (EKS, AKS, GKE):** `seccompProfile: RuntimeDefault`, NetworkPolicy de denegación por defecto (solo ingreso HTTP y egreso DNS), sin token de ServiceAccount y sin identidad de workload. Los tres clústeres aplican NetworkPolicy (GKE Calico, AKS `azure`, EKS VPC CNI con `enableNetworkPolicy`).

**No se usa `chroot(2)`**: exigiría `CAP_SYS_CHROOT` o root al arrancar, lo que rompería el modelo sin privilegios. La jaula seccomp contiene esta clase de fallo (corrupción de memoria → posible ejecución en proceso) denegando los syscalls de escape del contenedor, mientras que `disable_functions` y la ausencia de shell impiden la ejecución de comandos. No se puede denegar `execve` por seccomp: es el syscall con el que el runtime lanza el propio `php`, y denegarlo impide que el contenedor arranque. Este aislamiento reduce el radio de impacto; no hace segura una versión vulnerable ni garantiza ausencia de escape.

Para ejecutarlo localmente, configura una plataforma VM o Kubernetes → perfil PHP vulnerable y elige `local`. Docker publica el puerto solo en `127.0.0.1`, conecta el contenedor a una red interna sin salida a internet y aplica la misma jaula seccomp (`--security-opt seccomp=app/seccomp-vulnerable.json`).

## Controles de seguridad

El objetivo es que, si alguien explota la aplicación, no tenga manera de ejecutar comandos del sistema ni de moverse hacia otros recursos.

| Control | Dónde |
|---|---|
| Perfil estático sin PHP/FastCGI; perfil vulnerable PHP separado y optativo | `app/nginx.conf`, `app/Dockerfile-vulnerable` |
| Jaula seccomp en el runtime vulnerable en VM (syscalls de escape denegadas; comandos bloqueados por `disable_functions` + sin shell); `RuntimeDefault` en Kubernetes | `app/seccomp-vulnerable.json`, cloud-init de EC2/Azure VM, `k8s/20-deployment.yaml` |
| Usuario 101, sin root, `--cap-drop ALL`, `no-new-privileges` | `app/Dockerfile`, manifiestos, todas las plataformas |
| Sin `/bin/sh`, `apk`, `wget` ni `curl` en la imagen final | `app/Dockerfile` |
| Raíz de solo lectura; solo `/tmp` escribible | Todas las plataformas (ver excepciones) |
| Sin identidad del workload; solo la identidad de pull, limitada al repositorio | Todas las raíces |
| Sin SSH, sin llaves en la imagen, sin secretos en variables de entorno | Todas |
| Ingreso solo HTTP público al punto de entrada | Todas |
| Egreso restringido: ECS sin NAT con endpoints privados; VM con NSG/firewall solo 443 y DNS; K8s con NetworkPolicy | Ver tabla de residuales |
| IMDSv2 obligatorio con hop limit 1 | EC2, nodos EKS |
| Pod Security `restricted`, sin token de service account, cuotas y LimitRange | `k8s/` |
| Etiquetas `created_by`, `expires_at`, `app`, `managed_by` en todos los recursos | `locals.tf` / `labels` |

### Riesgos residuales (no mitigados por completo)

| Plataforma | Residual |
|---|---|
| Cloud Run | Egreso a internet por defecto (sin conector VPC). |
| Container Apps | Sin VNet, egreso libre. Sin sistema de archivos de solo lectura (no soportado). |
| AKS / GKE / EKS | Los nodos tienen salida (AKS: sin NAT; EKS: un NAT gateway; GKE: sin NAT, solo Google APIs). |
| EKS | `AmazonEC2ContainerRegistryReadOnly` puede leer todos los repositorios de la cuenta. El Service `LoadBalancer` requiere instalar el AWS Load Balancer Controller, que esta raíz no instala. |
| EC2 | El rol de instancia puede llamar `GetAuthorizationToken` en `*`. La IP pública es estable (Elastic IP); una EIP sin asociar factura si la instancia se destruye sin liberar la EIP. |
| VM (Azure, GCP, EC2) | HTTP sin TLS. Azure VM genera una clave SSH en el estado si no se proporciona una. IP pública estable en las tres (EC2 Elastic IP, Azure IP estática Standard, GCP dirección reservada). |
| GCP Compute | Puerto 8080 en vez de 80, porque konlet usa `--network=host`. Sin `readOnlyRootFilesystem`; `/tmp` y `/var/cache/nginx` son tmpfs en memoria. **Konlet no aplica la jaula seccomp personalizada**: el runtime vulnerable en Compute Engine se apoya en el perfil por defecto de COS, `disable_functions`, la ausencia de shell y el firewall de egreso. Para seccomp estricto, usa EC2/Azure VM o Kubernetes. |
| Registro | ACR y ECR/Artifact Registry sin escaneo de vulnerabilidades ni inmutabilidad de tags en GCP. |
| Presupuesto | Azure usa una fecha de inicio fija (`2026-10-01`) que hay que actualizar. GCP no envía correo (requiere canal de notificaciones). |

Estas medidas reducen el radio de impacto. No sustituyen parches, no garantizan que una carga comprometida no cause daño y no protegen contra abuso del propio plano de control de la nube.

En EKS, la raíz habilita explícitamente `enableNetworkPolicy` en el addon VPC CNI; sin esa opción, las políticas Kubernetes no aplican el aislamiento esperado. Consulta la [documentación de AWS para habilitar NetworkPolicy en EKS](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy-configure.html).

## Estado de verificación

| Elemento | Verificado | No verificado |
|---|---|---|
| `deploy.py` | `py_compile`; sintaxis del asistente y acciones locales. | Flujo de despliegue real, `plan` y `apply` contra cuentas. |
| `web/` | Sintaxis JS válida con `node --check`. | Pruebas en navegador. |
| Imagen segura (`app/Dockerfile`) | — | No construida en esta sesión. |
| Jaula seccomp | JSON válido; contenedor vulnerable probado en local con el perfil (`/healthz` 200, sin shell, arranca correctamente). | Enforcement real de los syscalls denegados; wiring en cloud-init de VM (solo se verifica al arrancar la VM). |
| Imagen vulnerable | `docker build` de `Dockerfile-vulnerable` OK; corregido el orden `chown`/`rm busybox` que rompía el build. | — |
| Terraform (9 raíces) | `fmt` y `validate` pasan en todas (incl. EC2/Azure VM/GCP Compute con IP estable y seccomp). | `plan`/`apply` real; comportamiento de providers y de cloud-init. |
| `k8s/` | — | `kubectl apply --dry-run` contra clúster real. |

Antes de un despliegue real:

```sh
docker build -f app/Dockerfile -t php-flaws-demo:local .
docker run --rm -p 8080:8080 --read-only --tmpfs /tmp --user 101:101 --cap-drop ALL php-flaws-demo:local
docker run --rm --read-only --user 101:101 --entrypoint /bin/sh php-flaws-demo:local -c id   # debe fallar
```

Fijar la imagen base por digest:

```sh
docker buildx imagetools inspect nginxinc/nginx-unprivileged:1.27-alpine
```

## Reglas de laboratorio

Cada despliegue es un laboratorio: `labs/<YYYY-MM>-<prefijo>/` con `INVENTARIO.md`, etiquetas `created_by` en todos los recursos (GCP en minúsculas) y limpieza con `python deploy.py destroy`. Verifica al cerrar que no queden recursos etiquetados:

- AWS: `aws resourcegroupstaggingapi get-resources --tag-filters Key=created_by,Values=<owner>`
- Azure: `az resource list --tag created_by=<owner>`
- GCP: `gcloud asset search-all-resources --scope=projects/<P> --query="labels.created_by=<owner-minúsculas>"`

## Fuentes

- [PHP: Security advisory, 21 Oct 2026](https://www.php.net/archive/2026.php): CVE-2026-109618 (corrupción por falta de memoria) y CVE-2026-109619 (estado obsoleto tras liberar memoria); versiones corregidas 8.5.12, 8.4.27, 8.3.36 y 8.2.35.
- [Advisory GHSA-6wmf-4rv5-p3rp](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp)
- [Advisory GHSA-w8hw-w9fx-j79w](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)

## Proceso sugerido para nuevas demos

1. Validar CVE, versiones afectadas y corregidas en el aviso del fabricante.
2. Definir el objetivo y clasificar el contenido como simulación, reproducción controlada o detección.
3. Usar datos sintéticos. Mantener la simulación como opción predeterminada; el perfil previo al parche solo se ofrece en GKE con aislamiento y doble confirmación.
4. Revisar aislamiento, privilegios, acceso de red, caducidad y costo con una lista común.
5. Añadir guion comercial, pasos de reinicio/destrucción y propietario del contenido.
6. Revisar y actualizar el contenido al publicarse nuevos avisos o parches.
