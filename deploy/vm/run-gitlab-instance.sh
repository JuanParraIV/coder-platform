#!/usr/bin/env bash
# =============================================================================
# run-gitlab-instance.sh — Segunda instancia de Coder (variante GitLab) en 3001
# =============================================================================
# Levanta un Coder APARTE para PROBAR la variante GitLab, SIN tocar el de GitHub:
#   - Puerto 3001 (el de GitHub sigue en 3000)
#   - Config/BD propias en ~/.config/coderv2-gitlab (Postgres embebido aislado)
#   - systemd --user: coder-gitlab.service (+ linger ya habilitado)
#   - server.env de GitLab (OIDC) sembrado aquí mismo (autocontenido)
# Reutiliza el MISMO binario ~/.local/bin/coder y el MISMO Docker.
#
# USO (en la VM, como el usuario dueño de Coder — NO root):
#   bash run-gitlab-instance.sh            # detecta la IP del server de GitHub
#   IP=192.168.50.208 bash run-gitlab-instance.sh   # o fuérzala
# -----------------------------------------------------------------------------
set -euo pipefail

c_ok()   { printf '\033[0;32m[ OK ]\033[0m %s\n' "$*"; }
c_info() { printf '\033[0;36m[INFO]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[0;33m[WARN]\033[0m %s\n' "$*"; }
die()    { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

PORT="${PORT:-3001}"
CFG="${HOME}/.config/coderv2-gitlab"
CODER_BIN="${HOME}/.local/bin/coder"
ENV_FILE="${CFG}/server.env"

[[ "$(id -u)" -ne 0 ]] || die "No ejecutes como root."
[[ -x "${CODER_BIN}" ]] || die "No existe ${CODER_BIN}. Corre antes bootstrap-vm.sh."

# --- IP / ACCESS_URL --------------------------------------------------------
if [[ -z "${IP:-}" ]]; then
  # intenta reutilizar la del server de GitHub; si no, la 1ª IP de la VM
  IP="$(grep -hoE 'http://[0-9.]+:' "${HOME}/.config/coderv2/server.env" 2>/dev/null | head -1 | sed -E 's#http://([0-9.]+):#\1#')"
  [[ -z "${IP}" ]] && IP="$(hostname -I | awk '{print $1}')"
fi
[[ -n "${IP}" ]] || die "No pude determinar la IP. Pásala: IP=x.x.x.x bash run-gitlab-instance.sh"
ACCESS_URL="http://${IP}:${PORT}"
c_info "Instancia GitLab → ${ACCESS_URL}  (config: ${CFG})"

# --- Layout -----------------------------------------------------------------
mkdir -p "${CFG}"; chmod 700 "${CFG}"

# start-server: fija CODER_CONFIG_DIR propio + source del env + exec.
cat > "${CFG}/start-server-gitlab.sh" <<EOS
#!/usr/bin/env bash
set -euo pipefail
export CODER_CONFIG_DIR="${CFG}"
ENV_FILE="${CFG}/server.env"
[[ -f "\${ENV_FILE}" ]] && source "\${ENV_FILE}"
exec "${CODER_BIN}" server
EOS
chmod 750 "${CFG}/start-server-gitlab.sh"

# server.env de GitLab (autocontenido). Solo se siembra si no existe.
if [[ -f "${ENV_FILE}" ]]; then
  c_ok "server.env ya existe (no lo toco)."
else
  cat > "${ENV_FILE}" <<'EOS'
# server.env — Coder variante GitLab (OIDC). Rellena los CHANGE_ME.
export CODER_CONFIG_DIR_HINT="coderv2-gitlab"   # informativo
export CODER_ACCESS_URL="__ACCESS_URL__"
export CODER_HTTP_ADDRESS="0.0.0.0:__PORT__"

# --- Login OIDC de GitLab ---------------------------------------------------
# OAuth App en GitLab (grupo o usuario). Redirect: <URL>/api/v2/users/oidc/callback
# Scopes: openid, profile, email (marca Confidential).
export CODER_OIDC_ISSUER_URL="https://gitlab.com"
export CODER_OIDC_CLIENT_ID="CHANGE_ME"
export CODER_OIDC_CLIENT_SECRET="CHANGE_ME"
export CODER_OIDC_SCOPES="openid,profile,email"
export CODER_OIDC_SIGN_IN_TEXT="Entrar con GitLab"
# Grupos de GitLab → RBAC (claim groups_direct):
export CODER_OIDC_GROUP_FIELD="groups_direct"
# (opcional) restringir a ciertos grupos:
# export CODER_OIDC_ALLOWED_GROUPS="coder-qintess"
# (opcional) normalizar "grupo/subgrupo" → nombre corto:
# export CODER_OIDC_GROUP_MAPPING='{"coder-qintess/platform-developers":"platform-developers","coder-qintess/qa-engineers":"qa-engineers","coder-qintess/architects":"architects"}'

# --- external-auth #0: GitLab per-usuario (repos) ---------------------------
# Redirect: <URL>/external-auth/gitlab/callback  · Scopes: api
export CODER_EXTERNAL_AUTH_0_ID="gitlab"
export CODER_EXTERNAL_AUTH_0_TYPE="gitlab"
export CODER_EXTERNAL_AUTH_0_CLIENT_ID="CHANGE_ME"
export CODER_EXTERNAL_AUTH_0_CLIENT_SECRET="CHANGE_ME"
EOS
  sed -i "s#__ACCESS_URL__#${ACCESS_URL}#; s#__PORT__#${PORT}#" "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"
  SEEDED=1
  c_warn "Sembré ${ENV_FILE}. RELLENA los CHANGE_ME (OIDC + external-auth GitLab) antes de usar."
fi

# --- systemd --user unit ----------------------------------------------------
UNIT_DIR="${HOME}/.config/systemd/user"; mkdir -p "${UNIT_DIR}"
cat > "${UNIT_DIR}/coder-gitlab.service" <<EOS
[Unit]
Description=Coder server (variante GitLab, puerto ${PORT})
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=${CFG}/start-server-gitlab.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOS
systemctl --user daemon-reload
systemctl --user enable coder-gitlab.service >/dev/null 2>&1 || true
loginctl enable-linger "$USER" >/dev/null 2>&1 || true

# --- Firewall ---------------------------------------------------------------
command -v ufw >/dev/null 2>&1 && { sudo ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true; c_ok "Puerto ${PORT}/tcp permitido."; }

# --- Arranque + health ------------------------------------------------------
if [[ "${SEEDED:-0}" == "1" ]]; then
  c_warn "NO arranco todavía: rellena ${ENV_FILE} y luego:  systemctl --user start coder-gitlab"
else
  systemctl --user restart coder-gitlab.service
  c_info "Esperando health en ${ACCESS_URL}/healthz …"
  for i in $(seq 1 30); do
    curl -fsS -o /dev/null "http://localhost:${PORT}/healthz" 2>/dev/null && { c_ok "Coder GitLab responde."; H=1; break; }
    sleep 2
  done
  [[ "${H:-0}" == "1" ]] || c_warn "No respondió. Revisa: journalctl --user -u coder-gitlab -n 40 --no-pager"
fi

cat <<EOF

$(c_ok "Instancia GitLab preparada (puerto ${PORT}).")
────────────────────────────────────────────────────────────────────────────
GitHub sigue intacto en :3000. Esta es GitLab en :${PORT}, aislada.

SIGUIENTE:
  1. En GitLab.com: crea la OAuth App (redirect ${ACCESS_URL}/api/v2/users/oidc/callback
     y ${ACCESS_URL}/external-auth/gitlab/callback) y los grupos:
     platform-developers, qa-engineers, architects (mete tu usuario a uno).
  2. Rellena  ${ENV_FILE}  (CLIENT_ID/SECRET de OIDC y external-auth).
  3. systemctl --user start coder-gitlab     # (o restart)
  4. Primer admin: abre ${ACCESS_URL} y entra con GitLab (primer login = admin).
  5. Sube la plantilla A ESTA instancia (config dir propio para no pisar el CLI de GitHub):
       export CODER_CONFIG_DIR=${CFG}
       ${CODER_BIN} login ${ACCESS_URL}
       cd ~/coder-platform/templates/mvp-embedded
       ${CODER_BIN} templates push mvp-embedded \\
         --var overlays_host_path=\$HOME/coder-platform/overlays --yes
       unset CODER_CONFIG_DIR
  6. Crea un workspace en ${ACCESS_URL} → verifica rol (por grupo) y 'claude mcp list' (gitlab ✔).

Detalle: docs/RUNBOOK-gitlab.md
────────────────────────────────────────────────────────────────────────────
EOF
