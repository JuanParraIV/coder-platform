#!/usr/bin/env bash
# =============================================================================
# configure-external-auth.sh — external-auth per-usuario (Fase B): GitHub + Atlassian
# =============================================================================
# Rellena en ~/.config/coderv2/server.env los client_id/secret de:
#   - external-auth #0 GitHub  (repos per-usuario del operador)
#   - external-auth #1 Atlassian (Jira/Confluence OAuth 3LO per-usuario)
# Los campos no-secretos (type/urls/scopes) ya vienen del server.env.example.
# Luego reinicia Coder. Idempotente.
#
# USO (en la VM):  bash deploy/vm/configure-external-auth.sh
# -----------------------------------------------------------------------------
set -euo pipefail

c_ok()   { printf '\033[0;32m[ OK ]\033[0m %s\n' "$*"; }
c_info() { printf '\033[0;36m[INFO]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[0;33m[WARN]\033[0m %s\n' "$*"; }
die()    { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

ENV_FILE="${HOME}/.config/coderv2/server.env"
[[ -f "${ENV_FILE}" ]] || die "No existe ${ENV_FILE}. Corre antes configure-server.sh."

set_env() {
  local key="$1" val="$2" esc
  esc="$(printf '%s' "$val" | sed -e 's/[\\|&]/\\&/g')"
  if grep -qE "^[#[:space:]]*export ${key}=" "${ENV_FILE}"; then
    sed -i "s|^[#[:space:]]*export ${key}=.*|export ${key}=\"${esc}\"|" "${ENV_FILE}"
  else
    printf 'export %s="%s"\n' "${key}" "${val}" >> "${ENV_FILE}"
  fi
}

ACCESS_URL="$(grep -E '^export CODER_ACCESS_URL=' "${ENV_FILE}" | head -1 | sed -E 's/^export CODER_ACCESS_URL="?([^"]*)"?.*/\1/')"
c_info "ACCESS_URL: ${ACCESS_URL}"

cat <<EOF

────────────────────────────────────────────────────────────────────────────
Crea 2 OAuth apps NUEVAS (para la VM):

 1) GitHub external-auth (repos per-usuario) — github.com/settings/developers
      Callback: ${ACCESS_URL}/external-auth/github/callback

 2) Atlassian OAuth 2.0 (3LO) — developer.atlassian.com/console/myapps
      Callback: ${ACCESS_URL}/external-auth/atlassian/callback
      Permisos (scopes) Jira/Confluence + offline_access (ya definidos en server.env)
      OJO multi-usuario: pon la app en Distribution=Sharing (ver docs/external-auth-oauth-pattern.md)
────────────────────────────────────────────────────────────────────────────

EOF

read -r  -p "GitHub external-auth  Client ID: "     GH_ID
read -rs -p "GitHub external-auth  Client Secret: " GH_SECRET; echo
read -r  -p "Atlassian OAuth       Client ID: "     ATL_ID
read -rs -p "Atlassian OAuth       Client Secret: " ATL_SECRET; echo
[[ -n "${GH_ID}" && -n "${GH_SECRET}" && -n "${ATL_ID}" && -n "${ATL_SECRET}" ]] || die "Algún valor quedó vacío."

cp -f "${ENV_FILE}" "${ENV_FILE}.bak.$(date +%Y%m%d%H%M%S)"
set_env CODER_EXTERNAL_AUTH_0_CLIENT_ID     "${GH_ID}"
set_env CODER_EXTERNAL_AUTH_0_CLIENT_SECRET "${GH_SECRET}"
set_env CODER_EXTERNAL_AUTH_1_CLIENT_ID     "${ATL_ID}"
set_env CODER_EXTERNAL_AUTH_1_CLIENT_SECRET "${ATL_SECRET}"
chmod 600 "${ENV_FILE}"
c_ok "external-auth GitHub + Atlassian configurados. Backup guardado."

c_info "Reiniciando Coder…"
systemctl --user restart coder
for i in $(seq 1 30); do
  curl -fsS -o /dev/null "http://localhost:3000/healthz" 2>/dev/null && { c_ok "Coder OK."; HEALTHY=1; break; }
  sleep 2
done
[[ "${HEALTHY:-0}" == "1" ]] || { c_warn "No respondió. Revisa: journalctl --user -u coder -n 40 --no-pager"; exit 1; }

cat <<EOF

$(c_ok "FASE B completa.")
Verifica: en la UI de Coder → sección "External Authentication" deberían aparecer
GitHub y Atlassian con botón "Login". Cada usuario los conecta una vez.
Siguiente (Fase C): subir la plantilla mvp-embedded (ver docs/RUNBOOK-vm-deploy.md §5).
EOF
