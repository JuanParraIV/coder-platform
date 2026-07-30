# =============================================================================
# Coder Template — Nivel 1 (MVP): VS Code + Claude Code EMBEBIDOS sobre Docker
# -----------------------------------------------------------------------------
# Provisiona un workspace como CONTENEDOR DOCKER (no Kubernetes). Es la rampa
# directa al TO-BE: el modelo coder_agent + módulos se conserva íntegro cuando
# más adelante se cambie `docker_container` por `kubernetes_pod` (Nivel 4).
#
# Requisitos: Coder server corriendo, Docker en la máquina del provisioner.
# Ver docs/MVP.md (Nivel 0 y 1) y templates/mvp-docker/README.md.
# =============================================================================

terraform {
  required_version = ">= 1.9"
  required_providers {
    coder  = { source = "coder/coder", version = ">= 2.12" }
    docker = { source = "kreuzwerker/docker", version = "~> 3.0" }
  }
}

# -----------------------------------------------------------------------------
# Variable de template: API key de Anthropic (secreta).
# Coder la expone como "template variable"; márcala al hacer push:
#   coder templates push mvp-docker -d . --var anthropic_api_key=sk-ant-xxx
# o en la UI (Admin > Templates > Variables). Nunca se hardcodea aquí.
# -----------------------------------------------------------------------------
variable "anthropic_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "API key de Anthropic para Claude Code (ANTHROPIC_API_KEY)."
}

# -----------------------------------------------------------------------------
# Datos del workspace / owner / provisioner
# -----------------------------------------------------------------------------
data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  # Usuario Linux dentro de la imagen base (codercom/enterprise-base) = "coder".
  linux_user = "coder"
  home       = "/home/coder"
  workdir    = "/home/coder/workspace"
}

# -----------------------------------------------------------------------------
# Coder agent: corre dentro del contenedor y expone las apps.
# -----------------------------------------------------------------------------
resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    set -e
    mkdir -p ${local.workdir}
  EOT

  # Botones nativos: dejamos el Terminal web (ahí corre `claude`).
  display_apps {
    vscode                 = false # VS Code Desktop (requiere IDE local) — off en MVP
    vscode_insiders        = false
    web_terminal           = true
    ssh_helper             = false
    port_forwarding_helper = false
  }

  metadata {
    display_name = "Rol"
    key          = "role"
    script       = "echo developer" # Nivel 1: rol fijo. Nivel 3 lo hace dinámico.
    interval     = 600
    timeout      = 5
  }
}

# -----------------------------------------------------------------------------
# MÓDULO 1 — VS Code embebido (code-server) → aparece como app en el dashboard.
# https://registry.coder.com/modules/coder/code-server
# -----------------------------------------------------------------------------
module "code-server" {
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  folder   = local.workdir
  order    = 1
}

# -----------------------------------------------------------------------------
# MÓDULO 2 — Claude Code embebido → instala `claude`, acepta el trust prompt
# y recibe la API key. Disponible en el Terminal web y en Coder Tasks.
# https://registry.coder.com/modules/coder/claude-code
# NOTA: verifica la versión actual del módulo en el registry y ajusta el pin.
# -----------------------------------------------------------------------------
module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "~> 2.0"
  agent_id          = coder_agent.main.id
  workdir           = local.workdir
  anthropic_api_key = var.anthropic_api_key
  # model           = "sonnet"   # opcional: alias o id completo
  # mcp             = jsonencode({ ... })  # Nivel 2: se inyecta desde el overlay del rol
}

# -----------------------------------------------------------------------------
# Recursos Docker: imagen + volumen de home persistente + contenedor
# -----------------------------------------------------------------------------
resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all # conserva el home aunque cambie el template
  }
}

resource "docker_image" "main" {
  name         = "codercom/enterprise-base:ubuntu"
  keep_locally = true
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count # 0 = parado, 1 = corriendo
  image    = docker_image.main.image_id
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  # Arranca el agente de Coder como entrypoint.
  entrypoint = ["sh", "-c", coder_agent.main.init_script]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  # Permite llegar al host (útil para Docker-in-Docker / servicios locales).
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = local.home
    volume_name    = docker_volume.home.name
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
}
