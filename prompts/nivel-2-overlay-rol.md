# Prompt — Nivel 2: Overlay de rol estático

## Rol
Eres un ingeniero de plataforma. Tu objetivo es que el workspace arranque con el
**`CLAUDE.md`, `skills/` y MCP de un rol** (empieza por `developer`), montados en el
`~/.claude` de Claude Code.

## Contexto
- Nivel 1 completado: VS Code + Claude Code embebidos sobre `templates/mvp-docker/`.
- Los overlays por rol ya existen en `overlays/{developer,qa,architect}/`
  (`CLAUDE.md`, `mcp-config.json`, `skills/<skill>/SKILL.md` + `references/`).
- **Hueco #4 conocido:** montar el overlay read-only en `~/.claude` rompe la escritura de
  Claude (estado/sesiones). Hay que montar en ruta neutra y **copiar a un `~/.claude`
  escribible** en el arranque.

## Objetivo
Que `claude`, dentro del workspace, lea el `CLAUDE.md` del rol y liste sus skills, con la
config MCP del rol cargada.

## Tareas
1. En `templates/mvp-docker/main.tf`, monta el overlay del rol dentro del contenedor en
   una ruta neutra, p. ej. `/etc/coder-overlay` (bind del directorio `overlays/developer/`
   o vía `docker_volume`/`host` según tu setup local).
2. En el `startup_script` del `coder_agent`, copia el overlay a un `~/.claude` escribible:
   ```bash
   mkdir -p ~/.claude
   cp -r /etc/coder-overlay/skills ~/.claude/skills
   cp /etc/coder-overlay/CLAUDE.md ~/.claude/CLAUDE.md
   # MCP: traduce mcp-config.json al formato que consume Claude Code
   ```
3. Conecta el MCP del rol: pasa el contenido de `overlays/developer/mcp-config.json` al
   input `mcp` (JSON-encoded) del módulo `claude-code`, **o** escríbelo como settings de
   Claude en el `startup_script`. Elige uno y documéntalo.
4. Parametriza el rol con un `data "coder_parameter" "role"` (default `developer`) para
   poder probar `qa`/`architect` cambiando un valor — todavía manual (el automático es
   Nivel 3).
5. Verifica que **no** se montan secretos reales en el overlay (los tokens MCP se
   resuelven aparte; en local usa placeholders o variables de entorno).
6. Actualiza `docs/MVP.md`: Nivel 2 → ✅.

## Archivos a crear/modificar
- `templates/mvp-docker/main.tf` — montaje del overlay + copia writable + input `mcp`.
- (Opcional) `templates/mvp-docker/scripts/apply-overlay.sh` — extraer la lógica de copia.
- `docs/MVP.md` — marcar Nivel 2.

## Criterios de aceptación
- [ ] `~/.claude/CLAUDE.md` dentro del workspace es el del rol seleccionado.
- [ ] `~/.claude/skills/` lista los skills del rol (p. ej. `code-review-security`).
- [ ] `~/.claude` es **escribible** (Claude puede guardar estado sin error).
- [ ] La config MCP del rol está cargada (los servidores aparecen en Claude).
- [ ] Cambiar el parámetro `role` a `qa` monta el overlay de QA en un workspace nuevo.

## Validación
```bash
# En el Terminal del workspace:
head -1 ~/.claude/CLAUDE.md
ls ~/.claude/skills/
touch ~/.claude/.write-test && echo "writable OK"
claude -p "lista tus skills disponibles"
```

## Notas
- No implementes resolución automática de rol aquí (eso es Nivel 3).
- Mantén el overlay como **fuente de verdad**: el workspace lo copia, no lo edita.
