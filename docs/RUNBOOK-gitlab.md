# RUNBOOK — Coder con GitLab (rama `feature/gitlab`)

> Variante de la plataforma que usa **GitLab.com** en vez de GitHub:
> login por **OIDC**, **RBAC por grupos de GitLab**, repos per-usuario por
> **external-auth tipo gitlab**. Sin GitHub App ni resolver de roles.
>
> Esta rama sólo deja la **base** lista (plantilla + overlays + server.env.example).
> El despliegue mecánico (Docker/Coder/systemd) es igual que `docs/RUNBOOK-vm-deploy.md`.

---

## Qué cambia frente a la versión GitHub

| Pieza | GitHub (main) | GitLab (esta rama) |
|---|---|---|
| Login | OAuth GitHub (`CODER_OAUTH2_GITHUB_*`) | **OIDC** (`CODER_OIDC_*`, issuer `https://gitlab.com`) |
| Rol (RBAC) | GitHub App + `resolve-role.sh` (teams) | **Grupos OIDC** → mapeo grupo→rol en la plantilla |
| Repos per-usuario | external-auth `github` | external-auth `gitlab` |
| Token en workspace | `GITHUB_TOKEN` | `GITLAB_TOKEN` |
| MCP | `@modelcontextprotocol/server-github` | `@modelcontextprotocol/server-gitlab` |
| GitHub App / `.pem` | requerido | **no se usa** |

> `templates/mvp-embedded/scripts/resolve-role.sh` y `gh-app-token.sh` quedan
> **sin usar** en esta rama (el rol sale de los grupos OIDC). Puedes ignorarlos.

---

## 1. Crear las OAuth apps en GitLab

En GitLab (de **grupo** recomendado: `https://gitlab.com/groups/<grupo>/-/settings/applications`,
o de usuario `https://gitlab.com/-/profile/applications`). Con `<URL>` = tu `CODER_ACCESS_URL`:

| Uso | Redirect URI | Scopes |
|---|---|---|
| **Login (OIDC)** | `<URL>/api/v2/users/oidc/callback` | `openid`, `profile`, `email` |
| **external-auth gitlab** | `<URL>/external-auth/gitlab/callback` | `api` (o `read_api`+`write_repository`) |

Marca **Confidential**. Puedes usar **una sola app** con ambos redirect URIs, o dos apps.

---

## 2. Rellenar `server.env`

Usa `deploy/vm/server.env.example` (ya viene en modo GitLab). Rellena:
- `CODER_OIDC_CLIENT_ID` / `CODER_OIDC_CLIENT_SECRET` (app de login)
- `CODER_EXTERNAL_AUTH_0_CLIENT_ID` / `_SECRET` (app external-auth gitlab)
- `CODER_ACCESS_URL` con tu IP/host
- Deja `CODER_OIDC_GROUP_FIELD="groups_direct"` (GitLab entrega los grupos ahí)

```bash
chmod 600 ~/.config/coderv2/server.env
systemctl --user restart coder
curl -fsS http://localhost:3000/healthz && echo "  ← OK"
```

> El bootstrap (`deploy/vm/bootstrap-vm.sh`) funciona igual (siembra este
> server.env). El helper `configure-server.sh` es **específico de GitHub** — en
> GitLab edita `server.env` directamente con esta guía.

---

## 3. Grupos de GitLab → roles

Crea (o reutiliza) estos grupos/subgrupos en GitLab y añade a cada usuario al suyo:

| Rol | Grupo (nombre por defecto en la plantilla) |
|---|---|
| developer | `platform-developers` |
| qa | `qa-engineers` |
| architect | `architects` |

- El nombre que **Coder recibe** depende del claim `groups_direct` (rutas completas,
  ej. `coder-qintess/platform-developers`). Si vienen con prefijo de grupo padre:
  - o ajusta las variables de la plantilla (`--var group_developer=coder-qintess/platform-developers` …),
  - o normaliza con `CODER_OIDC_GROUP_MAPPING` en `server.env` (ver ejemplo comentado).
- Least-privilege: si el usuario está en varios, gana el menos permisivo (qa < developer < architect).
- Fail-closed: sin grupo mapeado → rol `unknown` (no se aplica overlay).

---

## 4. Subir la plantilla

```bash
cd ~/coder-platform/templates/mvp-embedded
coder templates push mvp-embedded \
  --var overlays_host_path=$HOME/coder-platform/overlays \
  --yes
# Si tus grupos llegan con prefijo, añade p.ej.:
#   --var group_developer=coder-qintess/platform-developers
#   --var group_qa=coder-qintess/qa-engineers
#   --var group_architect=coder-qintess/architects
```

---

## 5. Verificación

- Entra a `<URL>` → **Entrar con GitLab** (OIDC).
- Crea un workspace → el rol debe corresponder a tu grupo de GitLab.
- En el workspace: `claude mcp list` → `gitlab ✔`. `git push` va con tu token.

---

## Notas

- **Atlassian/Jira** (external-auth #1) es independiente y **exige HTTPS** (no
  admite callbacks http/IP). Igual que en la versión GitHub: se conecta en Fase 2
  (dominio + TLS). Está declarado `optional` en la plantilla, no bloquea crear workspaces.
- Para **self-managed** (GitLab propio): cambia `CODER_OIDC_ISSUER_URL` y el
  `GITLAB_API_URL` de los overlays a tu dominio.
