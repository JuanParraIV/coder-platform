#!/usr/bin/env bash
# =============================================================================
# gh-app-token.sh — Mint de un GitHub App *installation token* (vida ~1 h)
# -----------------------------------------------------------------------------
# Credencial de la ORGANIZACIÓN (no un PAT personal). Reemplaza el PAT del
# servidor para que resolve-role.sh consulte membresías de team con una
# identidad de plataforma, auto-rotada, no atada a ninguna persona.
#
# Flujo: private key ─(JWT RS256, ≤10 min)→ POST /app/installations/{id}/access_tokens
#        → installation token (1 h). Se genera on-demand por invocación
#        (no queda token en disco; solo la private key de la App).
#
# Requiere en entorno (ver deploy/prod/github-app.env.example):
#   GITHUB_APP_ID                  = App ID (número)
#   GITHUB_APP_INSTALLATION_ID     = Installation ID (tras instalar la App en la org)
#   GITHUB_APP_PRIVATE_KEY_PATH    = ruta al .pem   (o)
#   GITHUB_APP_PRIVATE_KEY         = contenido PEM inline
#
# Salida: el installation token por stdout. Sale != 0 si algo falta/falla.
# Deps: openssl, curl. (No requiere `gh`.)
# =============================================================================
set -euo pipefail

: "${GITHUB_APP_ID:?falta GITHUB_APP_ID}"
: "${GITHUB_APP_INSTALLATION_ID:?falta GITHUB_APP_INSTALLATION_ID}"

# --- Resolver la private key a un archivo (perm 600) --------------------------
key_file=""
cleanup() { [ -n "${key_tmp:-}" ] && rm -f "$key_tmp" 2>/dev/null || true; }
trap cleanup EXIT
if [ -n "${GITHUB_APP_PRIVATE_KEY_PATH:-}" ]; then
  key_file="$GITHUB_APP_PRIVATE_KEY_PATH"
elif [ -n "${GITHUB_APP_PRIVATE_KEY:-}" ]; then
  key_tmp="$(mktemp)"; chmod 600 "$key_tmp"
  printf '%s\n' "$GITHUB_APP_PRIVATE_KEY" > "$key_tmp"
  key_file="$key_tmp"
else
  echo "falta GITHUB_APP_PRIVATE_KEY(_PATH)" >&2; exit 1
fi
[ -r "$key_file" ] || { echo "no puedo leer la private key: $key_file" >&2; exit 1; }

# --- base64url ---------------------------------------------------------------
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# --- JWT (RS256), iss = App ID, exp ≤ 10 min (usamos 9) ----------------------
now="$(date +%s)"
header='{"alg":"RS256","typ":"JWT"}'
payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$GITHUB_APP_ID")"
unsigned="$(printf '%s' "$header" | b64url).$(printf '%s' "$payload" | b64url)"
signature="$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$key_file" | b64url)"
jwt="$unsigned.$signature"

# --- Intercambiar JWT por installation token ---------------------------------
resp="$(curl -fsSL -X POST \
  -H "Authorization: Bearer $jwt" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens")" \
  || { echo "fallo al pedir installation token (¿App ID / installation / key correctos?)" >&2; exit 1; }

token="$(printf '%s' "$resp" | jq -r '.token // empty')"
[ -n "$token" ] || { echo "respuesta sin token: $resp" >&2; exit 1; }
printf '%s\n' "$token"
