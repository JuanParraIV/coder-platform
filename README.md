# Coder + Claude RBAC Platform

Plataforma de workspaces AI-augmented con RBAC por rol para DevSecOps Banco.  
Cada operador obtiene un entorno aislado con VS Code en browser + Claude Code CLI, pre-configurado según su rol.

---

## ¿Qué obtienes?

Al completar el setup, cada operador del equipo:

1. Entra a https://coder.banco-internal.com
2. Se autentica con GitHub (automático con OAuth)
3. **Su workspace se crea automáticamente** (CronJob detecta nuevo usuario)
4. Ve **dos opciones** en su dashboard:
┌─────────────────────────────────────────────────────────┐
│  🏠 Mi Workspace                            [Running]    │
│                                                          │
│  ┌─────────────────────┐  ┌──────────────────────────┐  │
│  │  🖥️ VS Code          │  │  🤖 Claude Code (CLI)    │  │
│  │  (click para abrir) │  │  (click para abrir)      │  │
│  └─────────────────────┘  └──────────────────────────┘  │
│                                                          │
│  Role: developer │ Skills: 3 │ MCP: 3 │ 🔒 Isolated    │
└─────────────────────────────────────────────────────────┘

**VS Code** → Editor completo en browser (extensions, terminal integrado)
**Claude Code** → Terminal web con Claude Code CLI ya lanzado, con tu rol configurado

Todo pre-configurado: skills, MCP servers, governance, network isolation. Sin instalar nada local.

---

## Arquitectura
                         ┌─────────────────────────────┐
                         │    OPERADOR (solo browser)    │
                         └──────────────┬──────────────┘
                                        │ HTTPS
                         ┌──────────────▼──────────────┐
                         │  coder.banco-internal.com  │
                         │  (Coder Control Plane - K8s) │
                         │                              │
                         │  • Auth (GitHub OAuth)       │
                         │  • Template Engine (TF)      │
                         │  • Workspace Manager         │
                         └──────────────┬──────────────┘
                                        │ Ejecuta main.tf
                         ┌──────────────▼──────────────┐
                         │    WORKSPACE POD (K8s)       │
                         │                              │
                         │  ┌────────────────────────┐  │
                         │  │ code-server (VS Code)  │  │
                         │  │ Claude Code CLI        │  │
                         │  │ git, gh, node, python  │  │
                         │  │                        │  │
                         │  │ ~/.claude/             │  │
                         │  │   CLAUDE.md (rol)      │  │
                         │  │   MCP config (rol)     │  │
                         │  │   skills/ (rol)        │  │
                         │  └────────────────────────┘  │
                         │                              │
                         │  🔒 CiliumNetworkPolicy      │
                         │  🏷️ label: coder.com/role    │
                         └──────────────────────────────┘

---

## Pre-requisitos

| Componente | Versión mínima | Para qué |
|-----------|---------------|----------|
| Kubernetes cluster | v1.28+ | Ejecutar Coder y workspaces |
| Cilium CNI | v1.14+ | Network policies FQDN-based |
| Helm | v3.x | Instalar Coder |
| Terraform | v1.5+ | Templates de Coder (incluido en Coder) |
| kubectl | v1.28+ | Administración del cluster |
| GitHub OAuth App | — | Autenticación de operadores |
| PostgreSQL | v14+ | Base de datos de Coder |
| DNS | — | Dominio para Coder (ej: coder.banco-internal.com) |
| TLS cert | — | HTTPS (cert-manager o cert manual) |

---

## Setup Paso a Paso

### Paso 1: Crear GitHub OAuth App

1. Ir a: `https://github.com/organizations/qintess/settings/applications`
2. Click **"New OAuth App"**
3. Configurar:
   - **Application name:** Coder Platform
   - **Homepage URL:** https://coder.banco-internal.com
   - **Authorization callback URL:** `https://coder.banco-internal.com/api/v2/users/oidc/callback`
4. Guardar el **Client ID** y **Client Secret**

### Paso 2: Crear GitHub Teams (si no existen)

En la org qintess, crear estos teams:

| Team slug | Rol en Coder | Miembros |
|-----------|-------------|----------|
| platform-developers | developer | Los devs del squad |
| qa-engineers | qa | Los QA del squad |

Agregar los operadores al team correspondiente.

### Paso 3: Preparar el cluster
bash
# Verificar que el cluster está activo
kubectl cluster-info

# Verificar que Cilium está instalado
cilium status

# Si Cilium no está, instalarlo:
# helm repo add cilium https://helm.cilium.io/
# helm install cilium cilium/cilium --namespace kube-system

### Paso 4: Crear los secrets en Kubernetes
bash
# Namespace para Coder server
kubectl create namespace coder

# Namespace para los workspaces
kubectl create namespace coder-workspaces

# Secret: GitHub OAuth (del Paso 1)
kubectl create secret generic coder-github-oauth -n coder \
  --from-literal=client-id=<TU_CLIENT_ID> \
  --from-literal=client-secret=<TU_CLIENT_SECRET>

# Secret: PostgreSQL connection URL
kubectl create secret generic coder-db -n coder \
  --from-literal=url='postgres://coder:PASSWORD@postgres-host:5432/coder?sslmode=require'

### Paso 5: Configurar el dominio

Editar helm/values.yaml si tu dominio es diferente:
yaml
coder:
  env:
    - name: CODER_ACCESS_URL
      value: "https://TU-DOMINIO.com"       # ← Cambiar
    - name: CODER_WILDCARD_ACCESS_URL
      value: "*.TU-DOMINIO.com"             # ← Cambiar
  ingress:
    host: "TU-DOMINIO.com"                  # ← Cambiar
    wildcardHost: "*.TU-DOMINIO.com"        # ← Cambiar

### Paso 6: Ejecutar el bootstrap
bash
# Desde la raíz del proyecto
bash deploy/bootstrap.sh

Esto hace automáticamente:
1. ✅ Crea namespaces
2. ✅ Verifica secrets
3. ✅ Instala Coder server via Helm
4. ✅ Crea ConfigMaps con los overlays por rol
5. ✅ Aplica network policies (Cilium)
6. ✅ Sube el template de workspace a Coder

### Paso 7: Activar auto-creación de workspaces
bash
# Crear token de admin para el CronJob
ADMIN_TOKEN=$(coder tokens create --name auto-create --lifetime 8760h)
kubectl create secret generic coder-auto-create-token -n coder \
  --from-literal=token="$ADMIN_TOKEN"

# Desplegar CronJob que auto-crea workspaces para usuarios nuevos
kubectl apply -f deploy/cronjob-auto-create.yaml

Esto ejecuta un job cada minuto que detecta usuarios sin workspace y les crea uno automáticamente.

### Paso 8: Login inicial en Coder
bash
# Instalar Coder CLI (si no lo tienes)
curl -L https://coder.com/install.sh | sh

# Login como admin
coder login https://coder.banco-internal.com

La primera persona en hacer login se convierte en admin.

---

## Uso Diario (Operadores)

### Primera vez

1. Abrir https://coder.banco-internal.com en el browser
2. Click **"Sign in with GitHub"**
3. **Listo.** Tu workspace se crea automáticamente (~30 segundos)

### Tu Dashboard

Al entrar ves tu workspace con dos botones:

| Botón | Qué abre | Cuándo usarlo |
|-------|----------|---------------|
| **🖥️ VS Code** | VS Code completo en el browser | Editar código, navegar repos, usar extensiones |
| **🤖 Claude Code (CLI)** | Terminal web con Claude Code ya iniciado | Pedirle a Claude que implemente, revise, genere tests |

Ambos tienen acceso al mismo filesystem (/home/coder/workspace/).

### Usar Claude Code (click en "Claude Code")
bash
# Dentro del workspace, Claude ya está configurado
claude

# Claude ya tiene:
# - CLAUDE.md con tu rol, skills y prohibiciones
# - MCP servers configurados (GitHub, Jira, Sonar, etc.)
# - Network isolation (solo puede acceder a APIs de tu rol)

### Usar VS Code (browser)

Abre archivos, edita código, usa el terminal integrado
Claude Code funciona desde el terminal integrado de VS Code
Las extensiones se pueden instalar normalmente

### Parar/Iniciar workspace
bash
# Desde CLI (opcional)
coder stop mi-workspace
coder start mi-workspace

# O desde la UI web: botones Stop/Start
>**Auto-stop:** Los workspaces se detienen automáticamente tras 2 horas de inactividad para ahorrar costos.
---

## Qué tiene cada rol

### Developer (team: platform-developers)

| Recurso | Valor |
|---------|-------|
| **Skills** | code-review-security, feature-implementation, jira-dev-sync |
| **MCP: GitHub** | Read/Write (push, create PRs) |
| **MCP: Jira** | Read + transition stories |
| **MCP: SonarCloud** | ✅ (ver métricas) |
| **Network** | github, anthropic, npm, pypi, docker, sonar, jira |
| **Governance** | BDD-first, max 15 files/PR, max 500 lines |

### QA (team: qa-engineers)

| Recurso | Valor |
|---------|-------|
| **Skills** | bdd-test-generation, coverage-gap-analysis, unit-test-generation |
| **MCP: GitHub** | Read-only (no push) |
| **MCP: Jira** | Read + create bugs |
| **MCP: Playwright** | ✅ (E2E tests) |
| **Network** | github, anthropic, jira, selenium-grid |
| **Governance** | Coverage 80%, test quality gates |

---

## Gestión de Secretos (MCP Tokens)

Los tokens que usan los MCP servers (GitHub, Jira, SonarCloud) se gestionan **automáticamente**:

`
tHub App genera token personal → Secret Manager → ESO → K8s Secret → Pod env vars → Claude MCP
`
## Cómo funciona

| Token | Fuente | Automatización |
|-------|--------|----------------|
| **GitHub** | GitHub App (Installation Token, 1h TTL) | Auto-generado, auto-rotado cada hora |
| **Jira** | Service account API token (compartido) | Rotación manual cada 90 días |
| **SonarCloud** | Org-level token (compartido) | Rotación manual cada 90 días |

### Onboarding de un operador nuevo

**100% automático.** Solo necesitas:

1. Agregar al operador al GitHub Team
2. El operador hace login en Coder
3. El `onboard-controller` hace todo el resto (tokens, secrets, workspace)
> Documentación completa: [`docs/09-gestion-secretos.md`](docs/09-gestion-secretos.md)

### Setup inicial (una vez)
```bash

# 1. Instalar External Secrets Operator
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace

# 2. Crear SecretStore
kubectl apply -f secrets/secret-store.yaml

# 3. Configurar secretos compartidos
aws secretsmanager create-secret --name "coder/shared/atlassian-api-token" --secret-string "ATATT3xxx"
aws secretsmanager create-secret --name "coder/shared/atlassian-base-url" --secret-string "https://banco-jira.atlassian.net"
aws secretsmanager create-secret --name "coder/shared/atlassian-email" --secret-string "coder-bot@banco.com"
aws secretsmanager create-secret --name "coder/shared/sonar-token" --secret-string "85baf0xxx"

# 4. Desplegar onboard-controller (auto-genera tokens per-user)
kubectl apply -f deploy/cronjob-onboard-controller.yaml
```

## Administración

### Agregar un nuevo operador

1. Agregarlo al GitHub Team correspondiente (`platform-developers` o `qa-engineers`)
2. **Listo.** El onboard-controller crea tokens + secrets + workspace automáticamente.

### Agregar un nuevo rol

```bash

# 1. Crear overlay
mkdir -p overlays/<nuevo-rol>
# Crear CLAUDE.md y mcp-config.json en ese directorio

# 2. Crear network policy
# Crear network-policies/<nuevo-rol>-egress.yaml

# 3. Agregar team en resolve-role.sh
# Editar templates/scripts/resolve-role.sh

# 4. Desplegar
kubectl create configmap overlay-<nuevo-rol> \
  --from-file=overlays/<nuevo-rol>/ -n coder-workspaces
kubectl apply -f network-policies/
coder templates push workspace-rbac --directory ./templates/ --yes
```
 Actualizar overlays (cambiar skills/MCP de un rol)

```bash

# Editar archivos en overlays/<rol>/
# Luego:
kubectl delete configmap overlay-<rol> -n coder-workspaces --ignore-not-found
kubectl create configmap overlay-<rol> --from-file=overlays/<rol>/ -n coder-workspaces

# Los workspaces nuevos usan el overlay actualizado.
# Workspaces existentes necesitan restart:
coder restart <workspace-name>
```
 Actualizar la imagen Docker

```bash

# Editar docker/workspace/Dockerfile
docker build -t ghcr.io/qintess/coder-workspace:latest docker/workspace/
docker push ghcr.io/qintess/coder-workspace:latest

# Los workspaces nuevos usan la imagen nueva.
# Existentes necesitan rebuild:
coder restart <workspace-name>
```
 Ver métricas y audit

- **Grafana dashboard:** Importar `observability/dashboards/adoption.json`
- **Alertas:** Aplicar `observability/alerts/cost-budget.yaml` y `observability/prometheus-rules.yaml`
- **Coder audit log:** UI → Admin → Audit Log

---

## CI/CD (automático)

| Workflow | Trigger | Qué hace |
|----------|---------|----------|
| `build-workspace-image.yml` | Push a `docker/workspace/**` en main | Build + push imagen a GHCR |
| `push-template.yml` | Push a `templates/**` o `overlays/**` en main | Push template + update ConfigMaps |

---

## Tests

```bash

# Correr todos los tests de validación
bash tests/test-full-integration.sh

# Tests individuales
bash tests/test-resolve-role.sh      # Lógica de roles
bash tests/test-overlay-mount.sh     # Archivos de overlay
bash tests/test-network-policy.sh    # Network policies
```

## Estructura del Proyecto

```
code
r-platform/
├── deploy/
│   └── bootstrap.sh               ← Script de provisión completa
├── docker/workspace/
│   ├── Dockerfile                  ← Imagen base del workspace
│   └── scripts/startup.sh         ← Init: monta overlays + arranca code-server
├── templates/
│   ├── main.tf                     ← Template Terraform (Coder lo ejecuta)
│   ├── variables.tf                ← Variables configurables
│   ├── outputs.tf                  ← Outputs del workspace
│   └── scripts/resolve-role.sh     ← Resolución automática de rol
├── overlays/
│   ├── developer/
│   │   ├── CLAUDE.md               ← System prompt Developer
│   │   └── mcp-config.json         ← MCP servers Developer
│   └── qa/
│       ├── CLAUDE.md               ← System prompt QA
│       └── mcp-config.json         ← MCP servers QA
├── network-policies/
│   ├── base-deny-all.yaml          ← Default deny
│   ├── developer-egress.yaml       ← Cilium FQDN policy Developer
│   └── qa-egress.yaml              ← Cilium FQDN policy QA
├── observability/
│   ├── prometheus-rules.yaml       ← Recording rules
│   ├── alerts/cost-budget.yaml     ← Alertas
│   └── dashboards/adoption.json    ← Grafana dashboard
├── helm/
│   └── values.yaml                 ← Config de Coder server
├── .github/workflows/
│   ├── build-workspace-image.yml   ← CI: build Docker image
│   └── push-template.yml           ← CD: push template a Coder
├── tests/                          ← Tests de validación
└── README.md                       ← Este archivo
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| "Cannot create workspace" | Verificar que el template está subido: `coder templates list` |
| "Role: unknown" en el workspace | Verificar que el usuario está en un GitHub Team válido |
| Claude no tiene MCP servers | Verificar que `~/.claude/settings.local.json` existe dentro del workspace |
| Network timeout en Claude | Verificar CiliumNetworkPolicy: `kubectl get cnp -n coder-workspaces` |
| Workspace no arranca | Ver logs: `kubectl logs <pod-name> -n coder-workspaces` |
| OAuth login falla | Verificar callback URL en GitHub OAuth App settings |
| ConfigMap vacío | Recrear: `kubectl create configmap overlay-<rol> --from-file=overlays/<rol>/` |

---

## FAQ

**¿Necesito instalar algo en mi máquina local?**  
No. Solo necesitas un browser moderno. VS Code corre en el server.

**¿Puedo usar mi IDE local en vez del browser?**  
Sí. Coder soporta conexión remota via SSH. Instala el plugin de Coder en tu VS Code/JetBrains local.

**¿Qué pasa si pertenezco a dos teams?**  
Se asigna el rol más permisivo automáticamente (developer > qa > product).

**¿Mis archivos persisten entre sesiones?**  
Con la config actual usan `emptyDir` (efímeros). Para persistencia, agregar un PVC al template.

**¿Cuánto cuesta por usuario?**  
Depende del cloud. Estimado: ~$2-5/día por workspace activo (2 CPU, 4GB RAM).