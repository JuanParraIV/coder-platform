#!/usr/bin/env bash
# =============================================================================
# gh-app-token-json.sh — envuelve gh-app-token.sh para `data.external` de TF.
# Emite {"token":"<installation-token>"} por stdout. Fail-open a token vacío
# (no rompe el build si la App no está configurada / falla el mint).
# El provisioner hereda GITHUB_APP_* desde server.env.
# =============================================================================
set -uo pipefail
DIR="$(dirname "$0")"
tok=""
if [ -n "${GITHUB_APP_ID:-}" ] && [ -n "${GITHUB_APP_INSTALLATION_ID:-}" ]; then
  tok="$(bash "$DIR/gh-app-token.sh" 2>/dev/null || true)"
fi
jq -cn --arg t "$tok" '{token:$t}'
