# =============================================================================
# Coder Template — MVP Opción B: VS Code Web + Claude Code EMBEBIDOS
# -----------------------------------------------------------------------------
# NO usa módulos del registry → funciona con el Terraform 1.5.7 del provisioner.
# Instala code-server y Claude Code en el startup_script y expone DOS apps:
#   - /apps/vscode  → VS Code en el browser (code-server, puerto 8080)
#   - /apps/claude  → Terminal web (ttyd) con `claude` ya lanzado (puerto 7681)
#
# Identidad: por ahora usa el owner de Coder. Cuando configures GitHub OAuth +
# external-auth, descomenta el bloque `coder_external_auth` y el `gh auth login`.
# =============================================================================

terraform {
  required_providers {
    coder  = { source = "coder/coder" }
    docker = { source = "kreuzwerker/docker" }
  }
}

# --- Backend LLM de Claude Code (swappable) ----------------------------------
# Precedencia: Vertex > Bedrock > OAuth token (Pro/Max) > API key.
# Cambiar de backend = editar el config central + scripts/apply-config.sh.
variable "claude_code_oauth_token" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Token de suscripción Claude Pro/Max (generado con `claude setup-token`). Backend actual."
}

variable "anthropic_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "API key de Anthropic (pago por token). Alternativa al OAuth token."
}

variable "llm_backend" {
  type        = string
  default     = "subscription"
  description = "Backend: subscription (Pro/Max) | vertex | bedrock | api_key."
}

variable "vertex_project" {
  type        = string
  default     = ""
  description = "GCP project id para Vertex AI (si llm_backend=vertex)."
}

variable "vertex_region" {
  type        = string
  default     = "us-east5"
  description = "Región de Vertex AI (ej. us-east5)."
}

variable "docker_socket" {
  type        = string
  default     = ""
  description = "(Opcional) URI del socket de Docker."
}

# --- RBAC (Nivel 3) -----------------------------------------------------------
variable "github_org" {
  type        = string
  default     = ""
  description = <<-EOT
    Org de GitHub contra la que resolver el rol por Team. Vacío = modo OVERRIDE
    (local / cuenta sin teams): se usa `default_role`. Con valor, resolve-role.sh
    consulta la membresía de team vía `gh` (el provisioner necesita GITHUB_TOKEN con read:org).
  EOT
}

variable "default_role" {
  type        = string
  default     = "developer"
  description = "Rol usado en modo override, o fallback si el usuario no está en ningún team."
}

variable "overlays_host_path" {
  type        = string
  default     = "/home/jotamario/Documents/DevOps/coder-platform/overlays"
  description = <<-EOT
    Ruta en el HOST del dir `overlays/` a montar RO en `/opt/overlays` del
    contenedor (homelab: server y workspaces en el mismo host). El startup_script
    copia `overlays/<rol>/` a `~/.claude`. En PROD se hornea en la imagen base y
    esta variable se deja vacía (sin bind-mount).
  EOT
}

# NOTA DevSecOps: SonarCloud/SAST se configurará en la fase DevSecOps (ver
# docs/CONFIGURACION.md → "Pendiente DevSecOps"). Jira/Confluence van por OAuth
# per-usuario (external-auth atlassian). Ver docs/CONFIGURACION.md para cambiar de org.

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Resolución automática de rol (Team de GitHub → rol). Fail-closed a `unknown`
# si hay org pero el usuario no matchea ningún team. Prioridad en resolve-role.sh.
data "external" "user_role" {
  program = ["bash", "${path.module}/scripts/resolve-role.sh"]
  query = {
    github_username = data.coder_workspace_owner.me.name
    github_org      = var.github_org
    # El override (fallback) SOLO aplica en modo local (sin org). En modo real,
    # un usuario sin team válido debe caer a `unknown` (fail-closed, no a un rol).
    role_override = var.github_org == "" ? var.default_role : ""
  }
}

locals {
  role = data.external.user_role.result.role

  # Backend LLM de Claude Code: solo se setean las env vars del backend elegido
  # (evita ANTHROPIC_API_KEY vacío que confundiría a claude).
  llm_env = (
    var.llm_backend == "vertex" ? {
      CLAUDE_CODE_USE_VERTEX      = "1"
      ANTHROPIC_VERTEX_PROJECT_ID = var.vertex_project
      CLOUD_ML_REGION             = var.vertex_region
      } : var.llm_backend == "bedrock" ? {
      CLAUDE_CODE_USE_BEDROCK = "1"
      } : var.claude_code_oauth_token != "" ? {
      CLAUDE_CODE_OAUTH_TOKEN = var.claude_code_oauth_token
      } : var.anthropic_api_key != "" ? {
      ANTHROPIC_API_KEY = var.anthropic_api_key
    } : {}
  )
}

# --- GitHub token para MCP/git: EXTERNAL-AUTH PER-USUARIO --------------------
# Requisito: el github MCP solo debe tocar los repos a los que el USUARIO tiene
# acceso → hay que usar SU token (GitHub aplica su acceso). Eso obliga a 1
# autorización única (botón "Login with GitHub" en el workspace, no una URL).
# La GitHub App queda SOLO para AuthZ (resolver rol), no para dar acceso a repos.
data "coder_external_auth" "github" {
  id = "github"
}

# --- Atlassian external-auth: Jira/Confluence PER-USUARIO (OAuth 3LO) ---------
# Cada usuario autoriza 1 vez ("Login with Atlassian") → mcp-atlassian usa SU
# token (modo BYOT) → ve solo su Jira/Confluence. Reemplaza el API token compartido.
data "coder_external_auth" "atlassian" {
  id = "atlassian"
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  env = merge(local.llm_env, {
    CODER_ROLE = local.role
    # Token OAuth del USUARIO (external-auth) → github MCP solo ve SUS repos.
    GITHUB_TOKEN = data.coder_external_auth.github.access_token
    # Atlassian PER-USUARIO (mcp-atlassian modo OAuth/BYOT): token OAuth del usuario.
    # El cloud id se calcula en el startup desde accessible-resources (del sitio
    # que el usuario autorizó). Reemplaza el API token compartido.
    ATLASSIAN_OAUTH_ACCESS_TOKEN = data.coder_external_auth.atlassian.access_token
    # SonarCloud (SAST): pendiente fase DevSecOps — reañadir SONAR_ORG/SONAR_TOKEN aquí.
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  })

  startup_script = <<-EOT
    set -e
    mkdir -p ~/workspace

    # --- Herramientas: ttyd + Node 20+ (mcp servers modernos como
    #     @playwright/mcp exigen Node >= 20; el apt de Ubuntu trae 18) ---
    if ! command -v ttyd >/dev/null 2>&1; then
      sudo apt-get update -y && sudo apt-get install -y ttyd
    fi
    NODE_MAJOR=$(node -v 2>/dev/null | sed -E 's/v([0-9]+).*/\1/' || echo 0)
    if [ "$${NODE_MAJOR:-0}" -lt 20 ]; then
      curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
      sudo apt-get install -y nodejs
    fi

    # --- code-server (VS Code Web) via tarball ---
    # Guard robusto: NO basta con que exista el symlink; verificamos que
    # `code-server --version` IMPRIME una versión. Una descarga/extracción
    # truncada deja `lib/node` en 0 bytes → code-server muere sin log y el
    # `command -v` clásico lo daría por "instalado". Si no valida, reinstala limpio.
    export PATH="$HOME/.local/bin:$PATH"
    CS_VER=4.96.4
    if ! code-server --version 2>/dev/null | grep -q '[0-9]'; then
      echo "[setup] code-server ausente o corrupto → (re)instalando $${CS_VER}"
      rm -rf ~/.local/lib/code-server-$${CS_VER}-linux-amd64 ~/.local/bin/code-server
      mkdir -p ~/.local/lib ~/.local/bin
      curl -fSL --retry 3 --retry-delay 2 -o /tmp/cs.tgz https://github.com/coder/code-server/releases/download/v$${CS_VER}/code-server-$${CS_VER}-linux-amd64.tar.gz
      tar -C ~/.local/lib -xzf /tmp/cs.tgz
      ln -sf ~/.local/lib/code-server-$${CS_VER}-linux-amd64/bin/code-server ~/.local/bin/code-server
      # Verificación dura: si el node embebido quedó en 0 bytes, abortar con error.
      test -s ~/.local/lib/code-server-$${CS_VER}-linux-amd64/lib/node
      code-server --version >/dev/null
    fi

    # --- Claude Code ---
    if ! command -v claude >/dev/null 2>&1; then
      sudo npm install -g @anthropic-ai/claude-code || npm install -g @anthropic-ai/claude-code
    fi

    # --- uv/uvx (runtime del MCP mcp-atlassian: `uvx mcp-atlassian`) ---
    if ! command -v uvx >/dev/null 2>&1; then
      curl -LsSf https://astral.sh/uv/install.sh | sh || true
    fi

    # --- Identidad + git como el usuario real (external-auth) ---
    git config --global user.name  "$${GIT_AUTHOR_NAME}"  || true
    git config --global user.email "$${GIT_AUTHOR_EMAIL}" || true
    # GITHUB_TOKEN viene del external-auth (token OAuth del usuario). Lo usamos
    # para que `git push` vaya a su nombre (y el github MCP ya lo toma del env).
    if [ -n "$${GITHUB_TOKEN}" ]; then
      git config --global credential.helper store || true
      printf 'https://x-access-token:%s@github.com\n' "$${GITHUB_TOKEN}" > ~/.git-credentials
      chmod 600 ~/.git-credentials || true
    fi

    # --- Overlay por ROL: Claude queda configurado con skills + MCP del rol ---
    # /opt/overlays/<rol> llega por bind-mount del host (homelab) u horneado (prod).
    # Idempotente: se re-aplica en cada arranque (refleja cambios en overlays/).
    ROLE="$${CODER_ROLE:-unknown}"
    OVL="/opt/overlays/$${ROLE}"
    if [ "$${ROLE}" != "unknown" ] && [ -d "$${OVL}" ]; then
      echo "[overlay] aplicando rol '$${ROLE}'"
      mkdir -p ~/.claude/skills ~/workspace
      # 1) Persona/instrucciones del rol → memoria global de Claude
      [ -f "$${OVL}/CLAUDE.md" ] && cp -f "$${OVL}/CLAUDE.md" ~/.claude/CLAUDE.md
      # 2) Skills del rol → skills personales (disponibles en todo proyecto)
      [ -d "$${OVL}/skills" ] && cp -rf "$${OVL}/skills/." ~/.claude/skills/
      # 3) MCP del rol → .mcp.json del proyecto (~/workspace) + auto-aprobar servers
      [ -f "$${OVL}/mcp-config.json" ] && cp -f "$${OVL}/mcp-config.json" ~/workspace/.mcp.json
      node -e 'const fs=require("fs"),os=require("os"),d1=os.homedir()+"/.claude";fs.mkdirSync(d1,{recursive:true});const p=d1+"/settings.json";let o={};try{o=JSON.parse(fs.readFileSync(p))}catch(e){}o.enableAllProjectMcpServers=true;fs.writeFileSync(p,JSON.stringify(o,null,2))' || true
      # 4) Playwright MCP (rol qa): instalar chromium la 1ª vez (idempotente).
      if grep -q '@playwright/mcp' ~/workspace/.mcp.json 2>/dev/null && [ ! -d ~/.cache/ms-playwright ]; then
        echo "[overlay] instalando chromium para @playwright/mcp…"
        npx -y playwright install --with-deps chromium >/tmp/pw-install.log 2>&1 || true
      fi
      # 5) ui-ux-pro-max (rol developer): su search.py requiere Python 3 (stdlib).
      if [ -d ~/.claude/skills/ui-ux-pro-max ] && ! command -v python3 >/dev/null 2>&1; then
        echo "[overlay] instalando python3 para la skill ui-ux-pro-max…"
        sudo apt-get install -y python3 >/tmp/py-install.log 2>&1 || true
      fi
    else
      echo "[overlay] rol '$${ROLE}': sin overlay (perfil mínimo)"
    fi

    # --- Atlassian OAuth: cloud id del sitio que el usuario autorizó ---
    # ATLASSIAN_OAUTH_ACCESS_TOKEN viene del agent env (external-auth). Derivamos
    # el cloud id de accessible-resources y lo exportamos ANTES de lanzar ttyd
    # (claude, hijo de este script, lo hereda). Si no hay token (usuario sin
    # Connect/sin acceso Atlassian), queda vacío y mcp-atlassian simplemente no
    # tendrá datos — aislamiento per-usuario correcto.
    if [ -n "$${ATLASSIAN_OAUTH_ACCESS_TOKEN}" ]; then
      export ATLASSIAN_OAUTH_CLOUD_ID=$(curl -s -H "Authorization: Bearer $${ATLASSIAN_OAUTH_ACCESS_TOKEN}" \
        https://api.atlassian.com/oauth/token/accessible-resources 2>/dev/null | jq -r '.[0].id // empty')
      echo "[atlassian] cloud id: $${ATLASSIAN_OAUTH_CLOUD_ID:-<sin acceso>}"
    fi

    # --- Lanzar servicios ---
    code-server --bind-addr 0.0.0.0:8080 --auth none >/tmp/code-server.log 2>&1 &
    # claude arranca en ~/workspace (project root) → toma el .mcp.json del rol
    ttyd -p 7681 -W -t titleFixed='Claude Code' bash -lc 'cd ~/workspace && (claude || bash)' >/tmp/ttyd.log 2>&1 &
  EOT

  metadata {
    display_name = "Rol"
    key          = "role"
    script       = "echo ${local.role}"
    interval     = 600
    timeout      = 5
  }
}

# --- App 1: VS Code Web (ruta /apps/vscode) ----------------------------------
resource "coder_app" "vscode" {
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/code.svg"
  url          = "http://localhost:8080/?folder=/home/coder/workspace"
  subdomain    = false # ruta path-based (funciona en localhost sin wildcard)
  order        = 1
  healthcheck {
    url       = "http://localhost:8080/healthz"
    interval  = 5
    threshold = 30
  }
}

# --- App 2: Terminal con Claude (ruta /apps/claude) --------------------------
resource "coder_app" "claude" {
  agent_id     = coder_agent.main.id
  slug         = "claude"
  display_name = "Claude Code (CLI)"
  icon         = "/icon/terminal.svg"
  url          = "http://localhost:7681"
  subdomain    = false # ttyd path-based vía el proxy de Coder
  order        = 2
}

# --- Docker: volumen de home + contenedor ------------------------------------
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
}

resource "docker_container" "workspace" {
  count      = data.coder_workspace.me.start_count
  image      = "codercom/enterprise-base:ubuntu"
  name       = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname   = data.coder_workspace.me.name
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  # --- Persistencia tras reboot (Nivel 6) ------------------------------------
  # Docker revive el MISMO contenedor al bootear el host (Coder nunca hizo
  # `docker stop`, así que no está "manualmente parado"). El agente reconecta
  # sin rebuild y, como el contenedor se REINICIA en vez de recrearse, los
  # paquetes apt (ttyd/node/code-server/claude) persisten en la capa → el
  # startup_script idempotente relanza los servicios en segundos, no ~7 min.
  # Un `coder stop` manual destruye el contenedor vía count=0, sin conflicto.
  restart = "unless-stopped"
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  # Overlays por rol montados RO desde el host (homelab). En prod se hornean en
  # la imagen base y se deja `overlays_host_path=""` → sin este mount.
  dynamic "volumes" {
    for_each = var.overlays_host_path != "" ? [1] : []
    content {
      host_path      = var.overlays_host_path
      container_path = "/opt/overlays"
      read_only      = true
    }
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
  labels {
    label = "coder.com/role"
    value = local.role
  }
}
