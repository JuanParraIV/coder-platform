# Patrón reutilizable — MCP/servicio per-usuario vía Coder external-auth (OAuth)

Guía general para dar a cada usuario acceso **con su propia identidad** a un
servicio (GitHub, Atlassian, GitLab, etc.) desde su workspace, con **un solo clic**
("Login with X") y **sin URLs manuales**. Aplicable a cualquier proveedor OAuth 2.0.

> Ejemplos ya implementados: **GitHub** (repos per-usuario) y **Atlassian**
> (Jira/Confluence per-usuario). Ver `docs/github-app-config.md` y la sección
> Atlassian de abajo.

---

## Concepto: 3 piezas

```
┌ 1. OAuth App (en el proveedor) ┐   ┌ 2. Coder external-auth ┐   ┌ 3. Template + MCP ┐
│  client_id + secret            │──▶│  hace el OAuth por      │──▶│ data.coder_external│
│  callback a Coder              │   │  usuario (1 clic)       │   │ _auth.<id>.access_ │
│  scopes                        │   │  guarda/refresca token  │   │ token → env → MCP  │
└────────────────────────────────┘   └─────────────────────────┘   └────────────────────┘
```

- El **usuario** solo pulsa un botón que Coder muestra (form de creación de
  workspace, página del workspace, o Account → External Authentication).
- El **token es de cada usuario** → el servicio aplica SU acceso (aislamiento real).
- No es "cero pasos": OAuth per-usuario exige **1 consentimiento único** por usuario
  (no por login). Cero-pasos solo se logra con token de plataforma (compartido),
  que pierde el per-usuario — ver trade-off en `docs/TO-BE/09-gestion-secretos.md`.

---

## Pieza 1 — OAuth App (en el proveedor)

- **Callback URL** (crítico, exacto): `${CODER_ACCESS_URL}/external-auth/<ID>/callback`
  (ej. `http://localhost:3000/external-auth/atlassian/callback`). `<ID>` = el id
  que le des al provider en Coder.
- **Scopes**: los mínimos para lo que el MCP hará (least-privilege).
- Guarda **Client ID** (no secreto) y **Client Secret** (secreto → va a server.env).

> GOTCHA callback: algunos proveedores (GitHub OAuth App) exigen que el callback
> registrado **cubra** la ruta. Si la app se reusa para login + external-auth,
> pon el callback en la **raíz** (`http://host:3000/`) para cubrir ambos.

## Pieza 2 — Coder external-auth (en `server.env`)

Bloque por proveedor (índice `N` = 0,1,2…). Client ID no es secreto; **el secret
lo pega el dueño del server, nunca en git/chat**:

```bash
export CODER_EXTERNAL_AUTH_N_ID="<id>"                 # = el <ID> del callback
export CODER_EXTERNAL_AUTH_N_TYPE="<id-o-tipo>"        # github/gitlab/... o custom
export CODER_EXTERNAL_AUTH_N_DISPLAY_NAME="Etiqueta del botón"
export CODER_EXTERNAL_AUTH_N_CLIENT_ID="<client-id>"
export CODER_EXTERNAL_AUTH_N_CLIENT_SECRET="<secret>"  # ← lo pega el usuario
export CODER_EXTERNAL_AUTH_N_AUTH_URL="https://.../authorize"     # custom: requerido
export CODER_EXTERNAL_AUTH_N_TOKEN_URL="https://.../oauth/token"  # custom: requerido
export CODER_EXTERNAL_AUTH_N_SCOPES="scope1 scope2 offline_access"  # separados por espacio
```
Recargar: `systemctl --user restart coder.service`. Verificar:
`curl -s -H "Coder-Session-Token: $TOK" $CODER_URL/api/v2/external-auth` (aparece el provider).

- **Tipos built-in** (github, gitlab, azure-devops, bitbucket-*, gitea): no hace
  falta AUTH_URL/TOKEN_URL. **Custom** (Atlassian, etc.): sí, obligatorios.
- **`offline_access`** (refresh token) va en `SCOPES`, **NO** en la OAuth App.

## Pieza 3 — Template Terraform + MCP

```hcl
data "coder_external_auth" "<id>" { id = "<id>" }

resource "coder_agent" "main" {
  env = {
    # el token per-usuario se inyecta como la env var que el MCP espera
    SERVICE_TOKEN = data.coder_external_auth.<id>.access_token
  }
}
```
El overlay `.mcp.json` referencia `${SERVICE_TOKEN}`. Como el `coder_agent.env`
llega al proceso del agente, el `claude` lanzado por él (ttyd) hereda la env → el
MCP conecta con el token del usuario.

---

## Ejemplo A — GitHub (implementado)

- OAuth App "coder local" (reusa la de login; callback en raíz).
- `CODER_EXTERNAL_AUTH_0_{ID=github,TYPE=github,CLIENT_ID,CLIENT_SECRET}` (built-in → sin AUTH/TOKEN_URL).
- Template: `GITHUB_TOKEN = data.coder_external_auth.github.access_token`; overlay usa `${GITHUB_TOKEN}`.
- Resultado: cada user ve SOLO sus repos (validado: Juan 90 repos, susanacarolina 0).
- La **GitHub App** `coder-rbac-resolver` es OTRA cosa (AuthZ/rol, org-level) — no confundir.

## Ejemplo B — Atlassian Jira/Confluence (en curso)

**OAuth App** (developer.atlassian.com/console/myapps → OAuth 2.0 integration):
- **Access type: Resource-level** (least-privilege; 1 sitio).
- Scopes: Jira (`read:jira-work write:jira-work read:jira-user`) + Confluence
  (`read:confluence-content.all write:confluence-content read:confluence-space.summary`).
- `offline_access` NO se marca aquí (va en Coder SCOPES).
- Callback: `http://localhost:3000/external-auth/atlassian/callback`.

**Coder external-auth** (custom OAuth2, en server.env):
```bash
export CODER_EXTERNAL_AUTH_1_ID="atlassian"
export CODER_EXTERNAL_AUTH_1_TYPE="atlassian"
export CODER_EXTERNAL_AUTH_1_DISPLAY_NAME="Atlassian (Jira/Confluence)"
export CODER_EXTERNAL_AUTH_1_CLIENT_ID="<client-id>"
export CODER_EXTERNAL_AUTH_1_CLIENT_SECRET="<secret>"   # lo pega el usuario
export CODER_EXTERNAL_AUTH_1_AUTH_URL="https://auth.atlassian.com/authorize?audience=api.atlassian.com&prompt=consent"
export CODER_EXTERNAL_AUTH_1_TOKEN_URL="https://auth.atlassian.com/oauth/token"
export CODER_EXTERNAL_AUTH_1_SCOPES="read:jira-work write:jira-work read:jira-user read:confluence-content.all write:confluence-content read:confluence-space.summary offline_access"
```
- **Quirk Atlassian 3LO**: el authorize necesita `audience=api.atlassian.com`
  (y `prompt=consent` para forzar refresh) → van como query en `AUTH_URL`.

**mcp-atlassian en modo OAuth (BYOT — bring your own token):**
- El servidor consume el token OAuth inyectado en vez del API token.
- Env: `ATLASSIAN_OAUTH_ACCESS_TOKEN` (= `data.coder_external_auth.atlassian.access_token`)
  + `ATLASSIAN_OAUTH_CLOUD_ID`. El **cloud id** (UUID) se obtiene de
  `https://api.atlassian.com/oauth/token/accessible-resources` con el token
  (con basic auth da 401; es OAuth-only). Sitio: `jotamario.atlassian.net`.
- Overlays `atlassian`: cambiar de `JIRA_URL/JIRA_USERNAME/JIRA_API_TOKEN` (API token
  compartido) a las env `ATLASSIAN_OAUTH_*` (per-usuario).

---

## Gotchas transversales (aprendidos)

1. **El dueño debe iniciar el build**: `coder restart <owner>/<ws>` como ADMIN NO
   inyecta el token de otro usuario (protección). El owner reinicia desde la UI.
2. **Workspaces existentes** creados antes de añadir el external-auth no pasan por
   el botón del form → el usuario conecta en **Account → External Authentication**.
3. **`docker exec` NO hereda el env del agente** (donde vive el token). Verificar
   por efectos (`~/.git-credentials`) o leyendo `/proc/<agentpid>/environ`.
4. **Token compartido vs per-usuario**: si inyectas una credencial de plataforma
   (App token, service account) tienes cero-pasos pero identidad compartida; el
   per-usuario (external-auth) cuesta 1 clic único. Elegir según auditoría requerida.
