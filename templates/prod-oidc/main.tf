# =============================================================================
# Coder Template — PRODUCCIÓN (Nivel 3): rol por GRUPO nativo (OIDC group sync)
# -----------------------------------------------------------------------------
# Diferencia clave vs `templates/mvp-embedded/`:
#   - El rol NO se resuelve con `resolve-role.sh` ni con ningún PAT/GITHUB_TOKEN.
#   - Coder sincroniza los grupos del IdP (OIDC/GitHub) y los expone al template
#     en `data.coder_workspace_owner.me.groups`. El rol sale de ahí en HCL puro.
#   - Cero credenciales de servidor para AuthZ, cero llamada a la API en caliente.
#
# Prerrequisitos (ver docs/RUNBOOK-prod-oidc.md y docs/TO-BE/13-authz-a-escala.md):
#   1. Coder con OIDC configurado + group sync activo (CODER_OIDC_GROUP_*).
#   2. Grupos creados/sincronizados: architects, platform-developers, qa-engineers.
#   3. Template ACL: cada grupo con acceso a los templates que le correspondan.
#   4. (Group sync avanzado / regex-mapping = feature Coder Premium/Enterprise.)
# =============================================================================

terraform {
  required_providers {
    coder  = { source = "coder/coder" }
    docker = { source = "kreuzwerker/docker" }
  }
}

variable "anthropic_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "API key de Anthropic para Claude Code (ANTHROPIC_API_KEY). En prod, inyectar vía secret manager, no en claro."
}

variable "docker_socket" {
  type        = string
  default     = ""
  description = "(Opcional) URI del socket de Docker."
}

# --- Atlassian (mcp-atlassian). En prod: per-usuario o service account via vault. ---
variable "jira_url" {
  type        = string
  default     = ""
  description = "Base URL de Atlassian Cloud (ej. https://tuorg.atlassian.net)."
}
variable "jira_username" {
  type        = string
  default     = ""
  description = "Email de la cuenta Atlassian (Basic auth con el API token)."
}
variable "jira_api_token" {
  type        = string
  sensitive   = true
  default     = ""
  description = "API token de Atlassian."
}
variable "confluence_url" {
  type        = string
  default     = ""
  description = "Base URL de Confluence (<jira_url>/wiki). Vacío = Confluence off."
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# --- GitHub external-auth (para que el workspace autentique gh como el usuario) -
# En prod se usa junto al OIDC login. El token del USUARIO es solo para su git;
# NO se usa para resolver el rol (eso lo hace el group sync del IdP).
data "coder_external_auth" "github" {
  id = "github"
}

# =============================================================================
# RESOLUCIÓN DE ROL — NATIVA POR GRUPO (sin script, sin token)
# -----------------------------------------------------------------------------
# `data.coder_workspace_owner.me.groups` = lista de grupos del usuario, poblada
# por el group sync del IdP en cada login. Mapeamos grupo→rol y aplicamos
# prioridad. Fail-closed: si no matchea ningún grupo conocido → "unknown".
# =============================================================================
locals {
  # Mapa grupo del IdP → rol de la plataforma. Ajustar los slugs a los grupos
  # reales que sincroniza tu IdP.
  group_to_role = {
    "architects"          = "architect"
    "platform-developers" = "developer"
    "qa-engineers"        = "qa"
  }

  # LEAST-PRIVILEGE (política única, 2026-07-09): si el usuario está en varios
  # grupos gana el rol MENOS permisivo (anti-escalada, deny-by-default banca).
  # Permisividad: qa < developer < architect. Orden = del menos al más permisivo.
  role_priority = ["qa", "developer", "architect"]

  owner_groups  = data.coder_workspace_owner.me.groups
  matched_roles = [for g in local.owner_groups : local.group_to_role[g] if contains(keys(local.group_to_role), g)]

  # Primer rol por prioridad que el usuario tenga; si ninguno → unknown (fail-closed).
  role = try([for r in local.role_priority : r if contains(local.matched_roles, r)][0], "unknown")

  # Config por rol. `unknown` cae a un perfil mínimo (sin egress a servicios,
  # sin skills) — el workspace arranca pero sin privilegios, nunca al revés.
  role_config = {
    architect = { overlay = "architect", egress = ["api.github.com", "api.anthropic.com"] }
    developer = { overlay = "developer", egress = ["api.github.com", "api.anthropic.com", "registry.npmjs.org"] }
    qa        = { overlay = "qa", egress = ["api.github.com", "api.anthropic.com", "jira.atlassian.net"] }
    unknown   = { overlay = "unknown", egress = [] }
  }
  active = local.role_config[local.role]
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  env = {
    ANTHROPIC_API_KEY  = var.anthropic_api_key
    CODER_ROLE         = local.role
    CODER_ROLE_OVERLAY = local.active.overlay
    # github MCP/git como el usuario (external-auth OAuth) → solo SUS repos.
    GITHUB_TOKEN = data.coder_external_auth.github.access_token
    # Atlassian (mcp-atlassian). En prod, per-usuario o service account via vault.
    JIRA_URL            = var.jira_url
    JIRA_USERNAME       = var.jira_username
    JIRA_API_TOKEN      = var.jira_api_token
    CONFLUENCE_URL      = var.confluence_url
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  startup_script = <<-EOT
    set -e
    mkdir -p ~/workspace

    # Fail-closed en runtime: si el rol es unknown, no montamos overlay ni skills.
    if [ "$${CODER_ROLE}" = "unknown" ]; then
      echo "[rbac] Rol UNKNOWN: el usuario no pertenece a ningún grupo mapeado." >&2
      echo "[rbac] Workspace arranca en perfil mínimo (sin overlay/skills)." >&2
    fi

    # --- Herramientas: ttyd + Node 20+ (mcp servers modernos exigen >=20) ---
    if ! command -v ttyd >/dev/null 2>&1; then
      sudo apt-get update -y && sudo apt-get install -y ttyd
    fi
    NODE_MAJOR=$(node -v 2>/dev/null | sed -E 's/v([0-9]+).*/\1/' || echo 0)
    if [ "$${NODE_MAJOR:-0}" -lt 20 ]; then
      curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
      sudo apt-get install -y nodejs
    fi

    # Guard robusto: verifica que code-server IMPRIME versión (un `lib/node` de
    # 0 bytes por descarga truncada lo dejaría "instalado" pero muerto). Reinstala
    # limpio si no valida. Ver docs/github-app-config.md / incidencia code-server.
    export PATH="$HOME/.local/bin:$PATH"
    CS_VER=4.96.4
    if ! code-server --version 2>/dev/null | grep -q '[0-9]'; then
      echo "[setup] code-server ausente o corrupto → (re)instalando $${CS_VER}"
      rm -rf ~/.local/lib/code-server-$${CS_VER}-linux-amd64 ~/.local/bin/code-server
      mkdir -p ~/.local/lib ~/.local/bin
      curl -fSL --retry 3 --retry-delay 2 -o /tmp/cs.tgz https://github.com/coder/code-server/releases/download/v$${CS_VER}/code-server-$${CS_VER}-linux-amd64.tar.gz
      tar -C ~/.local/lib -xzf /tmp/cs.tgz
      ln -sf ~/.local/lib/code-server-$${CS_VER}-linux-amd64/bin/code-server ~/.local/bin/code-server
      test -s ~/.local/lib/code-server-$${CS_VER}-linux-amd64/lib/node
      code-server --version >/dev/null
    fi

    if ! command -v claude >/dev/null 2>&1; then
      sudo npm install -g @anthropic-ai/claude-code || npm install -g @anthropic-ai/claude-code
    fi

    # --- uv/uvx (runtime del MCP mcp-atlassian) ---
    if ! command -v uvx >/dev/null 2>&1; then
      curl -LsSf https://astral.sh/uv/install.sh | sh || true
    fi

    # --- Identidad + gh como el usuario real (external-auth, NO para AuthZ) ---
    git config --global user.name  "$${GIT_AUTHOR_NAME}"  || true
    git config --global user.email "$${GIT_AUTHOR_EMAIL}" || true
    coder external-auth access-token github 2>/dev/null | gh auth login --with-token 2>/dev/null || true

    # --- Overlay por ROL: Claude queda configurado con skills + MCP del rol ---
    # Mapeo correcto a la config real de Claude Code (no un cp genérico):
    #   CLAUDE.md → ~/.claude/CLAUDE.md ; skills → ~/.claude/skills ;
    #   mcp-config.json → .mcp.json del proyecto + enableAllProjectMcpServers.
    OVL="/opt/overlays/$${CODER_ROLE_OVERLAY}"
    if [ "$${CODER_ROLE_OVERLAY}" != "unknown" ] && [ -d "$${OVL}" ]; then
      echo "[overlay] aplicando rol '$${CODER_ROLE_OVERLAY}'"
      mkdir -p ~/.claude/skills ~/workspace
      [ -f "$${OVL}/CLAUDE.md" ] && cp -f "$${OVL}/CLAUDE.md" ~/.claude/CLAUDE.md
      [ -d "$${OVL}/skills" ] && cp -rf "$${OVL}/skills/." ~/.claude/skills/
      [ -f "$${OVL}/mcp-config.json" ] && cp -f "$${OVL}/mcp-config.json" ~/workspace/.mcp.json
      node -e 'const fs=require("fs"),os=require("os"),d1=os.homedir()+"/.claude";fs.mkdirSync(d1,{recursive:true});const p=d1+"/settings.json";let o={};try{o=JSON.parse(fs.readFileSync(p))}catch(e){}o.enableAllProjectMcpServers=true;fs.writeFileSync(p,JSON.stringify(o,null,2))' || true
      # Playwright MCP (rol qa): chromium la 1ª vez (idempotente).
      if grep -q '@playwright/mcp' ~/workspace/.mcp.json 2>/dev/null && [ ! -d ~/.cache/ms-playwright ]; then
        npx -y playwright install --with-deps chromium >/tmp/pw-install.log 2>&1 || true
      fi
      # ui-ux-pro-max (rol developer): su search.py requiere Python 3 (stdlib).
      if [ -d ~/.claude/skills/ui-ux-pro-max ] && ! command -v python3 >/dev/null 2>&1; then
        sudo apt-get install -y python3 >/tmp/py-install.log 2>&1 || true
      fi
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

resource "coder_app" "vscode" {
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/code.svg"
  url          = "http://localhost:8080/?folder=/home/coder/workspace"
  subdomain    = false
  order        = 1
  healthcheck {
    url       = "http://localhost:8080/healthz"
    interval  = 5
    threshold = 30
  }
}

resource "coder_app" "claude" {
  agent_id     = coder_agent.main.id
  slug         = "claude"
  display_name = "Claude Code (CLI)"
  icon         = "/icon/terminal.svg"
  url          = "http://localhost:7681"
  subdomain    = false
  order        = 2
}

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

  restart = "unless-stopped" # persistencia Nivel 6 (ver mvp-embedded)
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
  # Rol estampado en el contenedor para NetworkPolicies/auditoría (viene del
  # group sync, no de un token). Fail-closed a `unknown`.
  labels {
    label = "coder.com/role"
    value = local.role
  }
}
