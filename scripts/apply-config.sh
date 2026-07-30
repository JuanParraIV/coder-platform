#!/usr/bin/env bash
# =============================================================================
# apply-config.sh — aplica el config central a la plataforma en UN comando.
# Empuja el template con las variables del config central (github_org, llm_*).
# SonarCloud/SAST: pendiente fase DevSecOps (ver docs/CONFIGURACION.md).
# Los secretos OAuth (server.env) NO se tocan aquí; si los cambiaste, reinicia
# el server con:  systemctl --user restart coder.service
#
# Uso:   scripts/apply-config.sh
# =============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
VARS="${VARS_FILE:-$HOME/.config/coderv2/mvp-embedded-vars.yaml}"
TEMPLATE="${TEMPLATE:-mvp-embedded}"
export CODER_URL="${CODER_URL:-http://localhost:3000}"

[ -f "$VARS" ] || { echo "✗ no existe el config: $VARS"; exit 1; }

echo "→ Aplicando config a '$TEMPLATE' desde $VARS"
grep -vE '^\s*#|^\s*$' "$VARS" | sed -E 's/(token:).*/\1 <oculto>/' | sed 's/^/    /'

coder templates push "$TEMPLATE" \
  -d "$REPO/templates/$TEMPLATE" \
  --variables-file "$VARS" \
  --yes

echo "✓ Template actualizado. Los workspaces toman el cambio al reconstruir"
echo "  (owner → Restart desde la UI para inyectar sus tokens per-usuario)."
