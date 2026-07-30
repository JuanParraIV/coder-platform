# Prompt — Nivel 1: VS Code + Claude Code embebidos

## Rol
Eres un ingeniero de plataforma. Tu objetivo es entregar un workspace de Coder con
**VS Code (code-server) y Claude Code embebidos**, corriendo como contenedor Docker.

## Contexto
- Nivel 0 completado: Coder server corriendo, Docker operativo.
- El scaffold ya existe en `templates/mvp-docker/` (`main.tf` + `README.md`) usando los
  módulos oficiales `coder/code-server` y `coder/claude-code`.
- Necesitas una API key de Anthropic (`sk-ant-...`).

## ⚠️ Prerrequisito bloqueante — Terraform >= 1.9
El provisioner de Coder usa el `terraform` del **PATH**. Si es < 1.9 (en el Nivel 0 era
**1.5.7** de linuxbrew), el `push` falla con *"Unsupported Terraform Core version"* porque
los módulos `code-server`/`claude-code` exigen **>= 1.9**. **Antes de la tarea 3:**
1. Instala Terraform 1.9–1.11 (dentro del rango soportado por Coder) **o** OpenTofu.
2. Ponlo primero en el PATH del proceso `coder server` y reinícialo:
   ```bash
   which terraform && terraform version   # debe reportar >= 1.9
   # reinicia: pkill -f "coder server"; CODER_HTTP_ADDRESS=0.0.0.0:3000 \
   #   CODER_ACCESS_URL=http://localhost:3000 coder server &
   ```
3. Confirma en el log que Coder toma el terraform >= 1.9.

## Objetivo
Subir el template `mvp-docker`, crear un workspace y comprobar que **VS Code abre en el
browser** y que **`claude` responde en el Terminal**.

## Tareas
1. Revisa `templates/mvp-docker/main.tf`. Confirma:
   - `variable "anthropic_api_key"` es `sensitive`.
   - Los dos `module` (`code-server`, `claude-code`) usan `agent_id = coder_agent.main.id`.
   - `docker_container` arranca con `coder_agent.main.init_script` y el `CODER_AGENT_TOKEN`.
2. Verifica el **pin de versión** del módulo `claude-code` (`~> 2.0`). Si `terraform init`
   falla al hacer push, consulta <https://registry.coder.com/modules/coder/claude-code> y
   ajusta `version`.
3. Sube el template pasando la key como variable secreta:
   ```bash
   cd templates/mvp-docker
   coder templates push mvp-docker -d . --var anthropic_api_key="sk-ant-xxxxx" --yes
   ```
4. Crea el workspace: `coder create dev1 --template mvp-docker --yes`.
5. Abre el dashboard: pulsa **code-server** (VS Code). Abre el **Terminal** y ejecuta
   `claude` — debe iniciar sesión con la API key inyectada.
6. Actualiza `docs/MVP.md`: Nivel 1 → ✅.

## Archivos a crear/modificar
- `templates/mvp-docker/main.tf` — solo si hay que ajustar el pin de versión o la imagen.
- `docs/MVP.md` — marcar Nivel 1 completado.

## Criterios de aceptación
- [ ] `coder templates push` termina sin error (`terraform init/plan` OK).
- [ ] El workspace `dev1` está *Running*.
- [ ] El botón **code-server** abre VS Code en el browser sobre `/home/coder/workspace`.
- [ ] En el Terminal, `claude` arranca y responde a un prompt simple.
- [ ] La API key **no** aparece en el `main.tf` ni en logs (se pasó como `--var` secreta).

## Validación
```bash
coder list
coder show dev1                     # apps: code-server presente
# En el Terminal del workspace:
which claude && claude --version
echo "di hola" | claude -p          # respuesta del modelo
```

## Notas
- **Rol fijo `developer`** en este nivel (metadata del agente). El rol dinámico es Nivel 3.
- Aún **sin overlay**: Claude usa su config por defecto. El `CLAUDE.md`/skills/MCP del rol
  llegan en el Nivel 2.
- El botón dedicado "Claude Code" del TO-BE se completa al habilitar **Coder Tasks**; en
  este nivel Claude vive en el Terminal web.
- No hay restricción de red en local; el egress gobernado es Nivel 5.
