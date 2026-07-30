# Prompts de desarrollo por nivel

Cada archivo es un **prompt listo para pegar a un agente** (Claude Code) que implementa
un nivel de la escalera MVP → TO-BE definida en [`docs/MVP.md`](../docs/MVP.md).

Uso: abre el workspace en la raíz de `coder-platform/`, pega el prompt del nivel que
toca, y deja que el agente cree/modifique los archivos. **Ejecútalos en orden** — cada
nivel asume el anterior completo.

| Orden | Prompt | Resultado |
|------:|--------|-----------|
| 0 | [`nivel-0-coder-server.md`](./nivel-0-coder-server.md) | Coder server + workspace Docker de arranque |
| 1 | [`nivel-1-embebido.md`](./nivel-1-embebido.md) | VS Code + Claude Code embebidos (`templates/mvp-docker/`) |
| 2 | [`nivel-2-overlay-rol.md`](./nivel-2-overlay-rol.md) | Overlay de rol estático en `~/.claude` |
| 3 | [`nivel-3-rbac.md`](./nivel-3-rbac.md) | GitHub OAuth + rol por Team |
| 4 | [`nivel-4-kubernetes.md`](./nivel-4-kubernetes.md) | Migración Docker → Kubernetes |
| 5 | [`nivel-5-isolation-secretos.md`](./nivel-5-isolation-secretos.md) | Cilium + ESO + Jira OAuth |
| 6 | [`nivel-6-operacion.md`](./nivel-6-operacion.md) | Auto-create + observabilidad + CI/CD |

## Convención de cada prompt

- **Rol / Contexto** — quién eres y el estado previo asumido.
- **Objetivo** — la meta del nivel.
- **Tareas** — pasos concretos.
- **Archivos a crear/modificar** — el output esperado.
- **Criterios de aceptación** — checklist de "hecho".
- **Validación** — comandos para probarlo.

Reglas heredadas (banking): fail-closed, sin secretos hardcodeados, diff mínimo,
todo trazable. Ver `overlays/*/CLAUDE.md` y `docs/TO-BE/`.
