# RUNBOOK — Coder con GitHub + GitHub Copilot (rama `github-copilot`)

> Variante que mantiene **GitHub** (login OAuth + RBAC por Teams + external-auth
> github, igual que `main`) pero cambia el asistente de **Claude Code** a
> **GitHub Copilot CLI (`gh copilot`)**.

---

## Qué cambia frente a `main` (GitHub + Claude Code)

| Pieza | main (Claude) | esta rama (Copilot) |
|---|---|---|
| Asistente | Claude Code (ttyd `claude`) | **`gh copilot`** (ttyd, terminal) |
| App | `/apps/claude` | **`/apps/copilot`** |
| Backend IA | Anthropic (subscription/vertex/bedrock/api_key) | **GitHub Copilot** (suscripción del usuario) |
| Overlay por rol | `CLAUDE.md` + skills + MCP | **`copilot-instructions.md`** (sin skills ni MCP) |
| Login / RBAC | GitHub OAuth + GitHub App (teams) | **igual** (sin cambios) |
| external-auth | github + atlassian | **solo github** (atlassian removido) |

---

## Requisitos
- Todo lo de la versión GitHub (login OAuth, GitHub App resolver, teams, external-auth github) — ver `docs/RUNBOOK-vm-deploy.md`.
- **Cada usuario necesita suscripción a GitHub Copilot** en su cuenta (el `gh copilot` usa su `GITHUB_TOKEN`).

## Limitaciones (honestas) de Copilot CLI vs Claude Code
- `gh copilot` **no es un REPL** ni un agente: son comandos `gh copilot suggest "..."` y `gh copilot explain "..."`.
- **No hay "skills" ni MCP** (esas son capacidades de Claude Code). El rol solo aporta `copilot-instructions.md`.
- `copilot-instructions.md` lo consume Copilot **en el editor** (VS Code); el `gh copilot` CLI no lo lee — se coloca igualmente para cuando se use Copilot en code-server.
- La extensión oficial de Copilot para VS Code **no está en Open VSX** (que usa code-server); por eso esta variante usa la **CLI**, no la extensión.

## Uso en el workspace
- App **VS Code** (`/apps/vscode`) para editar.
- App **GitHub Copilot** (`/apps/copilot`) → terminal con:
  ```bash
  gh copilot suggest "crea un script bash que haga X"
  gh copilot explain "comando o fragmento a explicar"
  ```

## Subir la plantilla
```bash
cd ~/coder-platform/templates/mvp-embedded   # rama github-copilot
coder templates push mvp-embedded \
  --var github_org=<tu-org> \
  --var overlays_host_path=$HOME/coder-platform/overlays --yes
```

> Nota: `prod-oidc` y `mvp-docker` en esta rama siguen apuntando a Claude (no se
> convirtieron). Esta variante toca solo `mvp-embedded`.
