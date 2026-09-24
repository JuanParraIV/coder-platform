# =============================================================================
# Coder Template — Variante GitHub + GitHub Copilot (CLI)
# -----------------------------------------------------------------------------
# NO usa módulos del registry → funciona con el Terraform 1.5.7 del provisioner.
# Instala code-server y GitHub Copilot CLI (`gh copilot`) en el startup_script y
# expone DOS apps:
#   - /apps/vscode   → VS Code en el browser (code-server, puerto 8080)
#   - /apps/copilot  → Terminal web (ttyd) con `gh copilot` disponible (puerto 7681)
#
# RBAC por GitHub Teams (igual que main). El asistente es Copilot CLI, no Claude:
# NO hay backend LLM de Anthropic ni MCP; el rol inyecta copilot-instructions.md.
# =============================================================================

terraform {
  required_providers {
    coder  = { source = "coder/coder" }
    docker = { source = "kreuzwerker/docker" }
  }
}

# --- Asistente: GitHub Copilot CLI -------------------------------------------
# Esta variante NO usa backend LLM de Anthropic. El asistente es `gh copilot`
# (extensión de GitHub CLI), que se autentica con el GITHUB_TOKEN del usuario
# (external-auth) y requiere que su cuenta tenga suscripción a GitHub Copilot.

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
}

# --- GitHub token para MCP/git: EXTERNAL-AUTH PER-USUARIO --------------------
# Requisito: el github MCP solo debe tocar los repos a los que el USUARIO tiene
# acceso → hay que usar SU token (GitHub aplica su acceso). Eso obliga a 1
# autorización única (botón "Login with GitHub" en el workspace, no una URL).
# La GitHub App queda SOLO para AuthZ (resolver rol), no para dar acceso a repos.
data "coder_external_auth" "github" {
  id = "github"
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  env = {
    CODER_ROLE = local.role
    # Token OAuth del USUARIO (external-auth) → `gh`/`gh copilot` y git actúan
    # como el usuario (Copilot requiere que su cuenta tenga suscripción Copilot).
    GITHUB_TOKEN        = data.coder_external_auth.github.access_token
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

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

    # --- GitHub CLI + extensión Copilot (`gh copilot`) ---
    if ! command -v gh >/dev/null 2>&1; then
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      sudo apt-get update -y && sudo apt-get install -y gh
    fi
    # gh se autentica con GITHUB_TOKEN (external-auth). Instala la extensión Copilot.
    gh extension install github/gh-copilot >/tmp/gh-copilot.log 2>&1 || \
      gh extension upgrade gh-copilot >/tmp/gh-copilot.log 2>&1 || true

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

    # --- Overlay por ROL: instrucciones de Copilot del rol -------------------
    # /opt/overlays/<rol> llega por bind-mount del host u horneado. gh copilot CLI
    # no tiene "skills"/MCP/persona; el rol aporta copilot-instructions.md (útil
    # además si el usuario usa Copilot en el editor) y un banner de rol.
    ROLE="$${CODER_ROLE:-unknown}"
    OVL="/opt/overlays/$${ROLE}"
    mkdir -p ~/workspace/.github
    if [ "$${ROLE}" != "unknown" ] && [ -d "$${OVL}" ]; then
      echo "[overlay] aplicando rol '$${ROLE}'"
      [ -f "$${OVL}/copilot-instructions.md" ] && cp -f "$${OVL}/copilot-instructions.md" ~/workspace/.github/copilot-instructions.md
      echo "$${ROLE}" > ~/.coder-role
    else
      echo "[overlay] rol '$${ROLE}': sin overlay (perfil mínimo)"
    fi

    # --- Lanzar servicios ---
    code-server --bind-addr 0.0.0.0:8080 --auth none >/tmp/code-server.log 2>&1 &
    # Terminal con gh copilot disponible (no es REPL: se usa `gh copilot suggest/explain`).
    ttyd -p 7681 -W -t titleFixed='GitHub Copilot' bash -lc 'cd ~/workspace && echo "GitHub Copilot CLI — usa:  gh copilot suggest \"...\"   |   gh copilot explain \"...\"  (rol: $(cat ~/.coder-role 2>/dev/null||echo n/a))" && exec bash' >/tmp/ttyd.log 2>&1 &
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

# --- App 2: Terminal con GitHub Copilot (ruta /apps/copilot) -----------------
resource "coder_app" "copilot" {
  agent_id     = coder_agent.main.id
  slug         = "copilot"
  display_name = "GitHub Copilot (CLI)"
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
