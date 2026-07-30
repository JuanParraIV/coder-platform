#!/usr/bin/env bash
# =============================================================================
# resolve-role.sh — Resolución de rol para Coder (protocolo data.external)
# -----------------------------------------------------------------------------
# Lee JSON por stdin: { github_username, github_org, role_override }
# Escribe JSON por stdout: { "role": "developer|qa|architect|unknown" }
#
# LEAST-PRIVILEGE multi-team: si el usuario está en varios teams gana el rol
# MENOS permisivo. Permisividad: qa < developer < architect. Orden de selección
# (primer match) = del menos al más permisivo → qa, developer, architect.
# - Sin `github_org` → usa `role_override` (modo local / cuenta sin teams).
# - Con `github_org` → consulta membresía de team vía `gh` (requiere read:org).
# - Fail-closed → si nada resuelve, devuelve el override o "unknown".
#
# Credencial para el lookup (precedencia):
#   1) GH_TOKEN/GITHUB_TOKEN ya en entorno  → PAT (homelab / atajo).
#   2) GitHub App configurada (GITHUB_APP_*) → mint installation token on-demand
#      (credencial de la ORG, auto-rotada, no atada a una persona) — recomendado prod.
#   3) Nada → se apoya en el `gh` ambiente (keyring interactivo; vacío en boot).
# =============================================================================
set -euo pipefail

# --- Asegurar auth de GitHub para el lookup (fail-open a gh ambiente) ---------
ensure_gh_auth() {
  # (1) Ya hay token en entorno → se usa tal cual.
  [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ] && return 0
  # (2) GitHub App configurada → mint installation token (vía bash: no depende de +x).
  if [ -n "${GITHUB_APP_ID:-}" ] && [ -n "${GITHUB_APP_INSTALLATION_ID:-}" ] \
     && { [ -n "${GITHUB_APP_PRIVATE_KEY:-}" ] || [ -n "${GITHUB_APP_PRIVATE_KEY_PATH:-}" ]; }; then
    local tok
    if tok="$(bash "$(dirname "$0")/gh-app-token.sh" 2>/dev/null)" && [ -n "$tok" ]; then
      export GH_TOKEN="$tok"
    fi
  fi
  # (3) Si nada de lo anterior aplicó, se usa el gh ambiente. Fail-closed si falla.
  return 0
}
ensure_gh_auth

IN="$(cat)"
username="$(printf '%s' "$IN" | jq -r '.github_username // empty')"
org="$(printf '%s' "$IN" | jq -r '.github_org // empty')"
override="$(printf '%s' "$IN" | jq -r '.role_override // empty')"

# Orden de prioridad (least-privilege: menos→más permisivo) y mapeo team -> rol.
PRIORITY=(qa developer architect)
declare -A TEAM=(
  [developer]="platform-developers"
  [qa]="qa-engineers"
  [architect]="architects"
)

emit() { jq -cn --arg role "$1" '{role:$role}'; exit 0; }

# 1) Sin org → override (local / sin teams)
if [ -z "$org" ]; then
  [ -n "$override" ] && emit "$override"
  emit "unknown"
fi

# 2) Con org → resolver por membresía de team (primer match por prioridad).
# Consulta con curl+token si hay token (App/PAT); si no, cae a `gh` (keyring
# interactivo). Usar curl evita depender de que `gh` esté en el PATH del
# provisioner (systemd --user no siempre lo tiene).
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
is_member() { # $1 = team slug → 0 si el usuario es miembro
  local url="https://api.github.com/orgs/$org/teams/$1/memberships/$username"
  if [ -n "$TOKEN" ]; then
    curl -fsS -o /dev/null \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" "$url"
  elif command -v gh >/dev/null 2>&1; then
    gh api "orgs/$org/teams/$1/memberships/$username" >/dev/null 2>&1
  else
    return 1
  fi
}
for role in "${PRIORITY[@]}"; do
  if is_member "${TEAM[$role]}"; then
    emit "$role"
  fi
done

# 3) Fail-closed
[ -n "$override" ] && emit "$override"
emit "unknown"
