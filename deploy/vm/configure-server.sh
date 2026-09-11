#!/usr/bin/env bash
# =============================================================================
# configure-server.sh — Configura el login de Coder (Fase A) de forma interactiva
# =============================================================================
# Rellena ~/.config/coderv2/server.env con:
#   - la OAuth App de GitHub para LOGIN (te la pide interactivamente)
#   - los valores REUTILIZABLES ya conocidos (org, GitHub App RBAC, ruta .pem)
# Luego abre el firewall, reinicia Coder y verifica /healthz.
#
# NO crea las OAuth apps (eso es en la web). NO toca los external-auth (Fase B):
# esos quedan como estén (CHANGE_ME) hasta que corras configure-external-auth.
#
# USO (en la VM, como el usuario dueño de Coder):
#   bash deploy/vm/configure-server.sh
# -----------------------------------------------------------------------------
set -euo pipefail

c_ok()   { printf '\033[0;32m[ OK ]\033[0m %s\n' "$*"; }
c_info() { printf '\033[0;36m[INFO]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[0;33m[WARN]\033[0m %s\n' "$*"; }
die()    { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

# Valores REUTILIZABLES del homelab (identificadores, no secretos).
GH_ORG="juanparra-coder"
GH_APP_ID="4257126"
GH_APP_INSTALLATION_ID="145468308"

CFG="${HOME}/.config/coderv2"
ENV_FILE="${CFG}/server.env"
PEM_PATH="${CFG}/github-app.pem"

[[ -f "${ENV_FILE}" ]] || die "No existe ${ENV_FILE}. Corre antes deploy/vm/bootstrap-vm.sh."

# --- helper: set/replace 'export KEY="val"' preservando el resto del archivo --
set_env() {
  local key="$1" val="$2" esc
  esc="$(printf '%s' "$val" | sed -e 's/[\\|&]/\\&/g')"
  if grep -qE "^[#[:space:]]*export ${key}=" "${ENV_FILE}"; then
    sed -i "s|^[#[:space:]]*export ${key}=.*|export ${key}=\"${esc}\"|" "${ENV_FILE}"
  else
    printf 'export %s="%s"\n' "${key}" "${val}" >> "${ENV_FILE}"
  fi
}

# --- ACCESS_URL: toma el que ya sembró el bootstrap ------------------------
ACCESS_URL="$(grep -E '^export CODER_ACCESS_URL=' "${ENV_FILE}" | head -1 | sed -E 's/^export CODER_ACCESS_URL="?([^"]*)"?.*/\1/')"
[[ -n "${ACCESS_URL}" && "${ACCESS_URL}" != *CHANGE_ME* ]] || die "CODER_ACCESS_URL vacío/CHANGE_ME en ${ENV_FILE}. Arréglalo (o re-corre bootstrap)."
c_info "ACCESS_URL detectado: ${ACCESS_URL}"

cat <<EOF

────────────────────────────────────────────────────────────────────────────
Antes de seguir, crea la OAuth App de LOGIN en GitHub:
  https://github.com/settings/developers  →  New OAuth App
    Application name:            Coder VM
    Homepage URL:               ${ACCESS_URL}
    Authorization callback URL: ${ACCESS_URL}/api/v2/users/oauth2/github/callback
  Genera el client secret y ten a mano Client ID + Client secret.
────────────────────────────────────────────────────────────────────────────

EOF

# --- Prompts ----------------------------------------------------------------
read -r  -p "GitHub OAuth (login) Client ID: " GH_CLIENT_ID
[[ -n "${GH_CLIENT_ID}" ]] || die "Client ID vacío."
read -rs -p "GitHub OAuth (login) Client Secret: " GH_CLIENT_SECRET; echo
[[ -n "${GH_CLIENT_SECRET}" ]] || die "Client Secret vacío."

# --- Backup + escritura -----------------------------------------------------
cp -f "${ENV_FILE}" "${ENV_FILE}.bak.$(date +%Y%m%d%H%M%S)"
set_env CODER_OAUTH2_GITHUB_CLIENT_ID     "${GH_CLIENT_ID}"
set_env CODER_OAUTH2_GITHUB_CLIENT_SECRET "${GH_CLIENT_SECRET}"
set_env CODER_OAUTH2_GITHUB_ALLOWED_ORGS  "${GH_ORG}"
set_env CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS "true"
set_env GITHUB_APP_ID                      "${GH_APP_ID}"
set_env GITHUB_APP_INSTALLATION_ID         "${GH_APP_INSTALLATION_ID}"
set_env GITHUB_APP_PRIVATE_KEY_PATH        "${PEM_PATH}"
chmod 600 "${ENV_FILE}"
c_ok "server.env actualizado (login + GitHub App). Backup guardado."

# --- Chequeo del .pem del GitHub App ----------------------------------------
if [[ -f "${PEM_PATH}" ]]; then
  chmod 600 "${PEM_PATH}"
  c_ok ".pem del GitHub App presente."
else
  c_warn "FALTA ${PEM_PATH} — cópialo antes de crear workspaces (resolución de rol RBAC)."
  c_warn "Desde tu máquina local:  base64 -w0 ~/.config/coderv2/github-app.pem"
  c_warn "En la VM:  echo 'PEGA_BASE64' | base64 -d > ${PEM_PATH} && chmod 600 ${PEM_PATH}"
fi

# --- Firewall ---------------------------------------------------------------
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow 3000/tcp >/dev/null 2>&1 || true
  c_ok "Puerto 3000/tcp permitido (ufw)."
fi

# --- Restart + health -------------------------------------------------------
c_info "Reiniciando Coder…"
systemctl --user restart coder
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://localhost:3000/healthz" 2>/dev/null; then
    c_ok "Coder responde (HTTP 200 en /healthz)."; HEALTHY=1; break
  fi
  sleep 2
done
[[ "${HEALTHY:-0}" == "1" ]] || { c_warn "No respondió. Revisa: journalctl --user -u coder -n 40 --no-pager"; exit 1; }

cat <<EOF

$(c_ok "FASE A completa.")
────────────────────────────────────────────────────────────────────────────
CREA EL PRIMER ADMIN (el primer login queda como admin):
  Abre en un navegador de la LAN:  ${ACCESS_URL}
  Entra con GitHub (cuenta miembro de la org '${GH_ORG}').

DESPUÉS (Fase B) → external-auth GitHub + Atlassian:
  bash deploy/vm/configure-external-auth.sh
────────────────────────────────────────────────────────────────────────────
EOF
