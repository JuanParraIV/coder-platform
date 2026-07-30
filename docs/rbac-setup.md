# RBAC setup — GitHub OAuth + resolución de rol por Team (Nivel 3)

> Cómo Coder resuelve **automáticamente** el rol de cada usuario (`developer`, `qa`,
> `architect`) a partir de su membresía en GitHub Teams, sin selección manual.
> Diseño de referencia: [`docs/TO-BE/02-rbac-mapping-roles.md`](./TO-BE/02-rbac-mapping-roles.md).

## Arquitectura de la resolución

```
GitHub OAuth login ─▶ Coder (owner = github username)
                              │
     Terraform (provisioner)  ▼
        data.external.user_role  ──▶ scripts/resolve-role.sh
              query: {github_username, github_org, role_override}
                              │  (gh api orgs/<org>/teams/<t>/memberships/<u>)
                              ▼
                        {"role": "developer|qa|architect|unknown"}
                              │
              local.role ─────┴─▶ label coder.com/role  +  metadata "Rol"
```

Implementado en [`templates/mvp-embedded/main.tf`](../templates/mvp-embedded/main.tf) y
[`templates/mvp-embedded/scripts/resolve-role.sh`](../templates/mvp-embedded/scripts/resolve-role.sh).

## Mapping de teams → rol

| GitHub Team (org `juanparra-coder`) | Rol Coder |
|---|---|
| `platform-developers` | `developer` |
| `qa-engineers`        | `qa` |
| `architects`          | `architect` |

**Prioridad multi-team — LEAST-PRIVILEGE (2026-07-09):** si el usuario está en
varios teams gana el rol **MENOS permisivo**. Permisividad `qa < developer <
architect` → orden de selección `qa → developer → architect` (el primero que
matchea gana). Si el usuario no está en ningún team → `unknown` (fail-closed).

> ✅ **Discrepancia reconciliada:** política única = least-privilege
> (`qa < developer < architect`). Alineados `resolve-role.sh`,
> `prod-oidc/main.tf`, `docs/TO-BE/02`, `prompts/nivel-3-rbac.md`.

## Modos de operación del template

`main.tf` expone dos variables que controlan la resolución:

| Variable | Efecto |
|---|---|
| `github_org=""` (vacío) | **Modo override** (local): usa `default_role` sin consultar GitHub. |
| `github_org="juanparra-coder"` | **Modo real**: `resolve-role.sh` consulta membresías vía `gh`. |
| `default_role="developer"` | Rol en modo override, o fallback. |

Push en cada modo:

```bash
cd templates/mvp-embedded
# Override (local, sin GitHub):
coder templates push mvp-embedded -d . --var github_org="" --var default_role="developer" --yes
# Real (por Team):
coder templates push mvp-embedded -d . --var github_org="juanparra-coder" --yes
```

## Configurar el GitHub OAuth App (login en Coder)

Necesario para que el **owner del workspace** sea el usuario de GitHub (y no un user local
como `admin`), de modo que `resolve-role.sh` reciba un `github_username` real.

1. **Org → Settings → Developer settings → OAuth Apps → New OAuth App**
   (`https://github.com/organizations/<org>/settings/applications`).
2. Valores:
   - **Application name:** `Coder Local`
   - **Homepage URL:** `http://localhost:3000`
   - **Authorization callback URL:** `http://localhost:3000/api/v2/users/oauth2/github/callback`
   - **Enable Device Flow:** *desmarcado* (no se usa para el login web).
3. **Register** → copia **Client ID** → **Generate a new client secret** → copia el secret.
4. Ponlos en `~/.config/coderv2/server.env` (perm `600`, **fuera de git**):
   ```bash
   export CODER_OAUTH2_GITHUB_CLIENT_ID=<client_id>
   export CODER_OAUTH2_GITHUB_CLIENT_SECRET=<client_secret>
   export CODER_OAUTH2_GITHUB_ALLOWED_ORGS=juanparra-coder
   export CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS=true
   ```
5. Relanza el server (ver [`RUNBOOK.md`](./RUNBOOK.md)) y verifica:
   ```bash
   curl -s http://localhost:3000/api/v2/users/authmethods | jq .github
   # → { "enabled": true, ... }
   ```
   El botón **"GitHub"** aparece en <http://localhost:3000/login>.

## Token del provisioner (para leer los teams)

`resolve-role.sh` hace `gh api` en modo real. El proceso `coder server` debe tener acceso a
un token con scope **`read:org`** (o superior). Se exporta al lanzar el server:

```bash
export GITHUB_TOKEN="$(gh auth token)"   # el gh local debe estar autenticado
```

Para **crear/administrar teams** por API se necesita `write:org`:

```bash
gh auth refresh -h github.com -s write:org
gh api -X POST orgs/juanparra-coder/teams -f name=platform-developers -f privacy=closed
gh api -X PUT  orgs/juanparra-coder/teams/platform-developers/memberships/<user> -f role=member
```

## Pruebas

**Unitaria del script (sin Coder):**

```bash
S=templates/mvp-embedded/scripts/resolve-role.sh
echo '{"github_username":"JuanParraIV","github_org":"juanparra-coder"}' | bash "$S"  # {"role":"developer"}
echo '{"github_username":"ghost","github_org":"juanparra-coder"}'       | bash "$S"  # {"role":"unknown"}
echo '{"github_username":"x","role_override":"qa"}'                       | bash "$S"  # {"role":"qa"} (override)
```

**Del workspace (label resuelta):**

```bash
docker inspect coder-admin-dev1 --format '{{ index .Config.Labels "coder.com/role" }}'  # developer
```

## Gotchas conocidos

1. **Owner = todos los teams.** Un **owner** de la org es miembro/maintainer *implícito* de
   TODOS los teams (tanto en `.../memberships/{u}` como en `.../members`). Con una cuenta
   owner la resolución siempre devuelve el rol de mayor prioridad → **no sirve para probar
   la diferenciación** qa/architect. Para un E2E real hace falta una **segunda cuenta
   NO-owner** invitada a un solo team.
2. **Owner del workspace.** `data.coder_workspace_owner.me.name` es el usuario de *Coder*.
   El workspace `dev1` pertenece al user local `admin` (creado con `--first-user`), que **no**
   es un github username → en modo real resolvería `unknown`. Por eso hasta tener login
   GitHub, `dev1` se mantiene en **modo override**. Con OAuth, crea el workspace tras entrar
   como tu usuario de GitHub.

## Estado actual (2026-07-09)

- ✅ OAuth App creada; login GitHub habilitado en Coder (`authmethods.github.enabled=true`).
- ✅ Teams `platform-developers`, `qa-engineers`, `architects` creados en `juanparra-coder`.
- ✅ `resolve-role.sh` validado en modo real (`developer` / `unknown`) y override.
- ✅ Mecánica cableada en `main.tf`: `data.external` → `local.role` → label + metadata.
- ⏳ Pendiente: crear workspace como usuario GitHub (post-login) para E2E real; 2ª cuenta
  para probar diferenciación de roles; inyectar `ANTHROPIC_API_KEY` (Nivel 1 al 100%).
