# MVP incremental — de "Hola workspace" al TO-BE

Este documento define **cómo llegar al diseño de `docs/TO-BE/` por niveles**, empezando
por lo más básico posible y añadiendo una capa a la vez. Cada nivel es funcional y
reutilizable: nada se tira al pasar al siguiente.

> Principio: **el modelo `coder_agent` + `coder_app`/módulos es idéntico en Docker y en
> Kubernetes.** Solo cambia el recurso de compute. Por eso un MVP en Docker es la rampa
> real al TO-BE, no un prototipo desechable.

Referencias base: [`README.md`](../README.md) (estado deseado) y
[`docs/TO-BE/`](./TO-BE/) (diseño completo aprobado). Prompts de ejecución por nivel en
[`prompts/`](../prompts/).

**Docs operativos (para colaboradores):**
- [`docs/RUNBOOK.md`](./RUNBOOK.md) — levantar/recuperar el entorno local tras un reboot.
- [`docs/rbac-setup.md`](./rbac-setup.md) — GitHub OAuth + resolución de rol por Team (Nivel 3).

---

## La escalera

| Nivel | Objetivo | Provisioner | Entregable | Prompt |
|------:|----------|-------------|------------|--------|
| **0** | Coder corriendo + 1 workspace Docker de arranque | Docker | Coder server + template base | [`prompts/nivel-0-coder-server.md`](../prompts/nivel-0-coder-server.md) |
| **1** | **VS Code + Claude Code embebidos** (2 módulos) | Docker | `templates/mvp-docker/` | [`prompts/nivel-1-embebido.md`](../prompts/nivel-1-embebido.md) |
| **2** | Overlay de rol estático (CLAUDE.md + skills + MCP) | Docker | overlay montado en `~/.claude` | [`prompts/nivel-2-overlay-rol.md`](../prompts/nivel-2-overlay-rol.md) |
| **3** | RBAC: GitHub OAuth + rol por Team | Docker | `resolve-role.sh` + OAuth | [`prompts/nivel-3-rbac.md`](../prompts/nivel-3-rbac.md) |
| **4** | Salto a Kubernetes | **K8s** | template K8s + imagen propia | [`prompts/nivel-4-kubernetes.md`](../prompts/nivel-4-kubernetes.md) |
| **5** | Network isolation + secretos | K8s | Cilium + ESO + Jira OAuth | [`prompts/nivel-5-isolation-secretos.md`](../prompts/nivel-5-isolation-secretos.md) |
| **6** | Operación Day-2 | K8s | auto-create + observabilidad + CI/CD | [`prompts/nivel-6-operacion.md`](../prompts/nivel-6-operacion.md) |

**Objetivo inmediato del usuario:** llegar al **Nivel 1** — un Coder local con VS Code
y Claude Code embebidos. Todo lo demás es aditivo sobre el mismo template.

---

## Detalle por nivel

### Nivel 0 — "Hola workspace"
- **Meta:** validar que Coder corre y provisiona un contenedor.
- **Cómo:** `curl -L https://coder.com/install.sh | sh` → `coder server` → crear admin →
  Templates → plantilla **Docker** de arranque → crear workspace.
- **Exit criteria:** un workspace en estado *Running* con Terminal web.

### Nivel 1 — Embebido (VS Code + Claude Code)
- **Meta:** los dos entornos del TO-BE, en local.
- **Cómo:** template [`templates/mvp-docker/`](../templates/mvp-docker/) con los módulos
  `coder/code-server` y `coder/claude-code` + variable secreta `anthropic_api_key`.
- **Exit criteria:** botón **VS Code** abre code-server; en Terminal, `claude` responde.

### Nivel 2 — Overlay de rol (estático)
- **Meta:** el workspace arranca con el `CLAUDE.md`, `skills/` y MCP de un rol.
- **Cómo:** montar `overlays/developer/` en el contenedor y copiarlo a un `~/.claude`
  **escribible** en el `startup_script` (el overlay read-only choca con la escritura de
  Claude — ver hueco #4 del análisis). MCP del overlay → input `mcp` del módulo.
- **Exit criteria:** `claude` lee el CLAUDE.md del rol y lista sus skills.

### Nivel 3 — RBAC
- **Meta:** el rol se resuelve solo por GitHub Team.
- **Cómo:** GitHub OAuth en Coder + `scripts/resolve-role.sh` (Team → rol,
  least-privilege qa < developer < architect) vía `data "external"`. Selección del overlay por rol.
- **Exit criteria:** dos usuarios de Teams distintos obtienen overlays distintos sin
  intervención manual. Base: `docs/TO-BE/02-rbac-mapping-roles.md`.

### Nivel 4 — Salto a Kubernetes
- **Meta:** correr en el clúster.
- **Cómo:** cambiar `docker_container`/`docker_volume` por `kubernetes_pod` + PVC;
  construir y publicar la imagen base propia (`docker/workspace/Dockerfile`, base
  `docs/TO-BE/06-imagen-base-docker.md`). Overlays vía ConfigMap.
- **Exit criteria:** mismo comportamiento del Nivel 3, pero en pods etiquetados por rol.

### Nivel 5 — Network isolation + secretos
- **Meta:** aislamiento y credenciales gobernadas.
- **Cómo:** CiliumNetworkPolicy FQDN por rol (incluye el endpoint de Claude elegido) +
  External Secrets Operator per-user + Jira OAuth 3LO.
- **Exit criteria:** egress default-deny; cada rol solo alcanza sus FQDN; tokens
  rotados automáticamente. Base: `docs/TO-BE/05`, `09`, `10`.

### Nivel 6 — Operación Day-2
- **Meta:** producción operable.
- **Cómo:** CronJob de auto-create al primer login, observabilidad
  (Prometheus/Grafana/Loki), CI/CD (`build-workspace-image`, `push-template`),
  auto-stop, backups. Base: `docs/TO-BE/07`, `08`.
- **Exit criteria:** onboarding 100% automático + dashboards de adopción/costo/gobernanza.

---

## Decisiones que hay que cerrar antes del Nivel 5

No urgen para el MVP local, pero bloquean producción:

1. **Egress al modelo:** `api.anthropic.com` en el allowlist FQDN vs. Bedrock/Vertex por
   endpoint privado.
2. **Auth de Claude en prod:** API key per-user (ESO) vs. clave compartida por rol.

---

## Estado

| Nivel | Estado |
|------:|--------|
| 0 | ✅ **validado en local** (2026-07-08) — ver "Notas de entorno" |
| 1 | 🟩 **casi cerrado** (2026-07-09) — workaround `templates/mvp-embedded/` validado con **Terraform 1.5.7** (sin módulos del registry); workspace `dev1` *Running/Healthy*, code-server (`:8080`) y ttyd+claude (`:7681`) arriba. **Pendiente único:** inyectar `ANTHROPIC_API_KEY` para que `claude` autentique. El scaffold `mvp-docker` sigue bloqueado por Terraform < 1.9 (usa OpenTofu 1.9.1 si se quiere esa vía). |
| 2 | ✅ **implementado y validado E2E (2026-07-09)** — al entrar, Claude queda configurado con skills+MCP+persona del rol. Delivery homelab = **bind-mount** de `overlays/` → `/opt/overlays` RO. `startup_script` mapea `CLAUDE.md→~/.claude/CLAUDE.md`, `skills/→~/.claude/skills/`, `mcp-config.json→~/workspace/.mcp.json` + `enableAllProjectMcpServers`. **MCP conectando:** **github** (external-auth OAuth per-usuario → solo repos del user) ✔; **atlassian** (`uvx mcp-atlassian`: Jira proyecto SCRUM + Confluence spaces) ✔; **playwright** (`@playwright/mcp`, Node20+chromium) ✔; sonar pendiente (falta cuenta SonarCloud). Secretos: ver `docs/TO-BE/09`. |
| 3 | ✅ **cerrado E2E (2026-07-09)** — ver [`docs/rbac-setup.md`](./rbac-setup.md). Resolución por GitHub Team vía **GitHub App de la org** (no PAT personal), least-privilege + one-role-per-user. Diferenciación validada con cuentas reales: `susanacarolina` en `qa-engineers`→`qa`, en `architects`→`architect`; `platform-developers`→`developer`. Label `coder.com/role` + overlay por rol. |
| 4–6 | ⬜ pendiente (prompts listos en `prompts/`) |

## Notas de entorno (Nivel 0 validado)

Ejecución local del Nivel 0 (máquina Linux x86_64, Docker operativo):

- Coder instalado **sin sudo** en `~/.local/bin` (modo standalone), versión **v2.35.1**.
- Server: `coder server` con PostgreSQL **embebido** (`~/.config/coderv2/postgres`).
- **Bind a `0.0.0.0:3000` (no `127.0.0.1`)**: el agente corre *dentro* del contenedor y
  alcanza el host por `host.docker.internal`; un listener en loopback **no** es alcanzable
  y el workspace queda `HEALTHY=false`. Con `CODER_HTTP_ADDRESS=0.0.0.0:3000` conecta al
  instante. `CODER_ACCESS_URL=http://localhost:3000` (se reescribe a `host.docker.internal`
  para el agente).
- Admin creado no-interactivo (`--first-user-*`). Credenciales locales entregadas aparte.
- Template `starter-docker` (imagen `codercom/enterprise-base:ubuntu`) + workspace
  `smoke-test` en `HEALTHY=true`, exec verificado.

### ⚠️ Bloqueo para el Nivel 1 — versión de Terraform

El provisioner de Coder usa el `terraform` del **PATH**, que aquí es **1.5.7**
(linuxbrew). Los módulos oficiales del registry (`code-server`, `jetbrains`,
**`claude-code`**) exigen **Terraform >= 1.9**, así que el `push` falla con
*"Unsupported Terraform Core version"*.

Por eso en el Nivel 0 se subió el starter **sin** esos módulos (solo agente + Terminal).
**Antes del Nivel 1** hay que darle a Coder un Terraform >= 1.9 dentro de su rango
soportado (instalar Terraform 1.9–1.11 y ponerlo primero en el PATH del proceso
`coder server`, o usar OpenTofu). Ver `prompts/nivel-1-embebido.md`.
