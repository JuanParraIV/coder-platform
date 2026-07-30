# Configuración GitHub App — valores reales (homelab `juanparra-coder`)

## Estado: ✅ ACTIVADA Y VALIDADA (2026-07-09)
`devbox` resuelve `coder.com/role=developer` vía la GitHub App (sin PAT personal,
sin `gh`). Registro concreto del AuthZ por GitHub App (Camino A / N2).
Procedimiento genérico en `docs/RUNBOOK-github-app.md`.

> **Sensibilidad:** el **App ID** y el **Installation ID** NO son secretos (son
> identificadores; sin la private key no autentican nada) → OK documentarlos.
> El **único secreto** es la private key `.pem`, que va al host con perm `600` y
> **nunca** a git ni al chat.

---

## Valores de la App (ya creados)

| Dato | Valor | Estado |
|------|-------|--------|
| GitHub App | `coder-rbac-resolver` (org `juanparra-coder`) | ✅ creada |
| Permiso | Organization → **Members: Read-only** | ✅ |
| **App ID** | `4257126` | ✅ |
| **Installation ID** | `145468308` | ✅ instalada en la org |
| **Private key `.pem`** | `~/.config/coderv2/github-app.pem` (perm 600) | ✅ colocada |

> **Ya aplicado:** vars en `server.env`, server reiniciado, template pusheado y
> `devbox` reconstruido → label `developer`. Los pasos de abajo quedan como
> referencia/reproducción.

## ⚠️ Dos gotchas que descubrimos al activar (imprescindibles)

1. **Cambiar los scripts NO basta: hay que `coder templates push`.** Coder ejecuta
   el template desde la versión **subida**, no desde los archivos del repo. Tras
   editar `resolve-role.sh`/`gh-app-token.sh` → `coder templates push mvp-embedded
   -d templates/mvp-embedded --yes` y luego `coder update <ws>` (queda OUTDATED).
2. **En el provisioner (systemd --user) `gh` NO está en el PATH.** La consulta de
   membresía se hace con **`curl`** (bearer token), no con `gh api`. El mint del
   token (`gh-app-token.sh`) ya usaba curl/openssl y por eso funcionaba; el fallo
   estaba en el lookup con `gh`. `resolve-role.sh` ya usa curl si hay token
   (App/PAT) y solo cae a `gh` si no hay token (keyring interactivo).

---

## Pasos para activar (los 3 que faltan)

### 1. Colocar la private key en el host (TÚ — no por chat)
Descarga el `.pem` desde la página de la App (*Private keys → Generate*) si aún
no lo hiciste, y muévelo:
```bash
mv ~/Descargas/*.private-key.pem ~/.config/coderv2/github-app.pem
chmod 600 ~/.config/coderv2/github-app.pem
```

### 2. Añadir las vars al entorno del server (bloque exacto)
Append a `~/.config/coderv2/server.env` (git-ignored):
```bash
export GITHUB_APP_ID="4257126"
export GITHUB_APP_INSTALLATION_ID="145468308"
export GITHUB_APP_PRIVATE_KEY_PATH="/home/jotamario/.config/coderv2/github-app.pem"
```
Luego recargar el server:
```bash
systemctl --user restart coder.service
```
> Nota: NO va ningún `GITHUB_TOKEN=<PAT>` personal. Precedencia en
> `resolve-role.sh`: **PAT env > GitHub App > gh ambiente**. Si dejas el PAT
> también, el PAT gana (útil para migrar sin romper; luego lo quitas).

### 3. Validar y re-estampar el rol
```bash
cd /home/jotamario/Documents/DevOps/coder-platform/templates/mvp-embedded/scripts
set -a; source ~/.config/coderv2/server.env; set +a

# a) el mint del installation token funciona:
./gh-app-token.sh | head -c 12; echo '...'          # → ghs_....

# b) resuelve el rol con ESE token (sin keyring):
env -u GH_TOKEN -u GITHUB_TOKEN bash -c '
  set -a; source ~/.config/coderv2/server.env; set +a
  echo "{\"github_username\":\"JuanParraIV\",\"github_org\":\"juanparra-coder\"}" | ./resolve-role.sh'
# → {"role":"developer"}

# c) reconstruir el workspace para re-estampar el label:
coder update JuanParraIV/devbox --yes
docker inspect coder-JuanParraIV-devbox --format '{{index .Config.Labels "coder.com/role"}}'
# → developer   (ya no unknown)
```

---

## Verificación de que la App quedó bien (opcional, sin tocar Coder)
Con el `.pem` colocado y las vars cargadas, un mint exitoso confirma que
App ID + Installation ID + private key son coherentes. Si `gh-app-token.sh`
devuelve un `ghs_...`, la App está lista.

## Archivos relacionados
- `docs/RUNBOOK-github-app.md` — procedimiento genérico + por qué App vs PAT.
- `deploy/prod/github-app.env.example` — plantilla de las vars.
- `templates/mvp-embedded/scripts/gh-app-token.sh` — minter del token.
- `templates/mvp-embedded/scripts/resolve-role.sh` — consumidor (precedencia PAT>App>ambiente).
- `docs/TO-BE/13-authz-a-escala.md` — dónde encaja en la escalera N0→N3.
