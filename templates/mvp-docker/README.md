# Template `mvp-docker` — Nivel 1

Workspace de Coder con **VS Code (code-server) y Claude Code embebidos**, corriendo
como **contenedor Docker** (sin Kubernetes). Es el MVP de la escalera descrita en
[`docs/MVP.md`](../../docs/MVP.md).

## Qué provisiona

- Un `coder_agent` dentro de un contenedor `codercom/enterprise-base:ubuntu`.
- **VS Code en el browser** (módulo `coder/code-server`) → botón en el dashboard.
- **Claude Code** (módulo `coder/claude-code`) → instalado y listo en el Terminal web
  (`claude`) y en Coder Tasks; recibe la API key vía la variable de template.
- Home persistente en un `docker_volume`.

> El botón dedicado de "Claude Code" del TO-BE se materializa del todo al habilitar
> **Coder Tasks**; en este nivel Claude ya está disponible en el Terminal web.

## Prerrequisitos

- Docker corriendo en la máquina del provisioner (la misma del `coder server`).
- Coder server accesible (`coder login`).
- Una API key de Anthropic (`sk-ant-...`).

## Uso

```bash
# 1) Desde este directorio, sube el template pasando la API key como variable secreta
coder templates push mvp-docker \
  --directory . \
  --var anthropic_api_key="sk-ant-xxxxx" \
  --yes

# 2) Crea un workspace
coder create mi-workspace --template mvp-docker --yes

# 3) Abre el dashboard: verás el botón "code-server" (VS Code).
#    Para Claude: abre el Terminal y ejecuta `claude`.
```

En vez de `--var` puedes definir la variable en la UI: **Admin → Templates →
mvp-docker → Variables** (queda oculta por ser `sensitive`).

## Notas de implementación

- **Rol fijo `developer`** en este nivel (metadata del agente). El rol dinámico por
  GitHub Team llega en el **Nivel 3** (ver `prompts/nivel-3-rbac.md`).
- **Sin overlay** todavía: el `CLAUDE.md`/skills/MCP por rol se montan en el
  **Nivel 2** (`prompts/nivel-2-overlay-rol.md`).
- **Pin de versión del módulo `claude-code`**: está en `~> 2.0`. Si `terraform init`
  (lo corre Coder al hacer push) falla por versión, revisa la versión actual en
  <https://registry.coder.com/modules/coder/claude-code> y ajusta el `version`.
- **Egress**: en local no hay restricción; en el banco, Claude sale a
  `api.anthropic.com` (o Bedrock/Vertex) — decisión que se cierra en el Nivel 5.

## Ruta al TO-BE

Este `main.tf` migra a Kubernetes cambiando **solo** `docker_container`/`docker_volume`
por `kubernetes_pod`/`persistentVolumeClaim`. El `coder_agent` y los dos módulos se
conservan. Ver `prompts/nivel-4-kubernetes.md`.
