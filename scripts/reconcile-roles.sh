#!/usr/bin/env bash
# =============================================================================
# reconcile-roles.sh — Reconciliación periódica de rol RBAC (Decisión #18)
# -----------------------------------------------------------------------------
# Compara el rol ESTAMPADO en cada workspace vivo (label coder.com/role del
# contenedor) contra la membresía ACTUAL del usuario en la org de GitHub, y
# aplica la política ASIMÉTRICA de la Decisión #18:
#
#   - Ya NO está en la org (offboarding)   → coder stop + delete   (fail-closed)
#   - Rol actual MENOS permisivo (deny)     → coder restart         (re-resuelve)
#   - Rol actual MÁS permisivo (promoción)  → no-op (esperar rebuild natural)
#   - Iguales                               → no-op
#
# Permisividad (least-privilege): qa < developer < architect. unknown = 0.
#
# MODO DRY-RUN POR DEFECTO: solo LOGUEA lo que haría. Para ejecutar de verdad:
#   DRY_RUN=0 bash scripts/reconcile-roles.sh
#
# FAIL-SAFES:
#   - Si no se puede mintear el token de la GitHub App → ABORTA (no actúa; sin
#     token, resolve-role daría "unknown" para todos y borraría a todos).
#   - Solo hace offboarding ante un 404 EXPLÍCITO de membresía (distingue
#     "salió de la org" de "token caído / error de red").
#   - Reutiliza gh-app-token.sh + resolve-role.sh del template (misma lógica que
#     el build, un solo mint de token por corrida).
#
# Deps: coder (CLI logueado), docker, curl, jq, openssl. (No requiere `gh`.)
# =============================================================================
set -uo pipefail   # SIN -e: queremos seguir el bucle aunque falle un workspace.

# --- Config (override por entorno) -------------------------------------------
DRY_RUN="${DRY_RUN:-1}"                                   # 1 = solo loguea (default)
ORG="${RECONCILE_ORG:-juanparra-coder}"                  # org de GitHub
# Usuarios LOCALES de Coder (no identidades GitHub) que NUNCA se tocan.
# El owner local `admin` (--first-user) no existe en la org → daría 404 y sería
# un falso "offboarding". Lista separada por espacios.
IGNORE_OWNERS="${RECONCILE_IGNORE_OWNERS:-admin}"
SERVER_ENV="${SERVER_ENV:-$HOME/.config/coderv2/server.env}"   # trae GITHUB_APP_*
CODER_BIN="${CODER_BIN:-$HOME/.local/bin/coder}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TPL_SCRIPTS="${TPL_SCRIPTS:-$REPO_ROOT/templates/mvp-embedded/scripts}"
GH_APP_TOKEN_SH="$TPL_SCRIPTS/gh-app-token.sh"
RESOLVE_ROLE_SH="$TPL_SCRIPTS/resolve-role.sh"

# Rango de permisividad para comparar (mayor = más permisos).
declare -A RANK=( [unknown]=0 [qa]=1 [developer]=2 [architect]=3 )

log()  { printf '%s [reconcile] %s\n' "$(date -Is)" "$*"; }
die()  { log "ABORT: $*"; exit 1; }

# act "descripción" cmd args...  → en dry-run solo loguea; si no, ejecuta.
act() {
  local desc="$1"; shift
  if [ "$DRY_RUN" = "1" ]; then
    log "DRY-RUN | HARÍA: $desc  ->  $*"
  else
    log "EXEC   | $desc  ->  $*"
    "$@" || log "  !! el comando falló (rc=$?)"
  fi
}

# --- Pre-flight --------------------------------------------------------------
command -v jq   >/dev/null || die "falta jq"
command -v curl >/dev/null || die "falta curl"
command -v docker >/dev/null || die "falta docker"
[ -x "$CODER_BIN" ] || die "no encuentro el binario coder en $CODER_BIN"
[ -r "$GH_APP_TOKEN_SH" ] || die "no encuentro gh-app-token.sh en $GH_APP_TOKEN_SH"
[ -r "$RESOLVE_ROLE_SH" ] || die "no encuentro resolve-role.sh en $RESOLVE_ROLE_SH"

# server.env aporta GITHUB_APP_ID / _INSTALLATION_ID / _PRIVATE_KEY_PATH.
if [ -r "$SERVER_ENV" ]; then
  # shellcheck disable=SC1090
  set -a; source "$SERVER_ENV"; set +a
else
  log "aviso: no pude leer $SERVER_ENV (espero GITHUB_APP_* ya en el entorno)"
fi

# --- Mint del token de la GitHub App (una vez por corrida) -------------------
# resolve-role.sh reusa GH_TOKEN del entorno, así no re-mintea.
if ! GH_TOKEN="$(bash "$GH_APP_TOKEN_SH" 2>/dev/null)" || [ -z "$GH_TOKEN" ]; then
  die "no pude mintear el installation token de la GitHub App (fail-safe: no actúo)"
fi
export GH_TOKEN
log "token de la App minteado OK (org=$ORG, DRY_RUN=$DRY_RUN)"

# --- Helpers -----------------------------------------------------------------
# org_membership <user> → imprime: member | not_member | error:<code>
org_membership() {
  local user="$1" code
  code="$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/orgs/$ORG/members/$user")"
  case "$code" in
    204) echo member ;;
    404) echo not_member ;;
    *)   echo "error:$code" ;;
  esac
}

# stamped_role <owner> <ws> → label coder.com/role del contenedor ("" si no hay)
stamped_role() {
  docker inspect "coder-$1-$2" \
    -f '{{ index .Config.Labels "coder.com/role" }}' 2>/dev/null || true
}

# resolved_role <user> → rol actual según membresía de teams (least-privilege)
resolved_role() {
  printf '{"github_username":"%s","github_org":"%s"}' "$1" "$ORG" \
    | bash "$RESOLVE_ROLE_SH" 2>/dev/null | jq -r '.role // "unknown"'
}

rank() { echo "${RANK[$1]:-0}"; }

# --- Bucle principal ---------------------------------------------------------
# coder list --output json → owner_name + name de cada workspace.
if ! WS_JSON="$("$CODER_BIN" list --all --output json 2>/dev/null)"; then
  die "coder list falló (¿sesión del CLI expirada? 'coder login')"
fi

n_ok=0 n_offb=0 n_demote=0 n_promote=0 n_skip=0
while IFS=$'\t' read -r owner ws; do
  [ -n "$owner" ] && [ -n "$ws" ] || continue
  # Excluir usuarios locales (no-GitHub): darían 404 y un offboarding falso.
  if [[ " $IGNORE_OWNERS " == *" $owner "* ]]; then
    log "SKIP  | $owner/$ws — owner en lista de exclusión (usuario local, no GitHub)"
    n_skip=$((n_skip+1)); continue
  fi
  membership="$(org_membership "$owner")"

  case "$membership" in
    error:*)
      log "SKIP  | $owner/$ws — membresía indeterminada ($membership); no actúo"
      n_skip=$((n_skip+1)); continue ;;
    not_member)
      # Offboarding: fail-closed, terminar el workspace (no relabel).
      log "DENY  | $owner/$ws — ya NO está en la org → offboarding"
      act "offboarding stop"   "$CODER_BIN" stop   "$owner/$ws" --yes
      act "offboarding delete" "$CODER_BIN" delete "$owner/$ws" --yes
      n_offb=$((n_offb+1)); continue ;;
  esac

  # Sigue en la org → comparar rol resuelto vs estampado.
  stamped="$(stamped_role "$owner" "$ws")"
  resolved="$(resolved_role "$owner")"

  if [ -z "$stamped" ]; then
    log "SKIP  | $owner/$ws — sin contenedor vivo (rol resuelto=$resolved); nada que reconciliar"
    n_skip=$((n_skip+1)); continue
  fi

  rs="$(rank "$resolved")"; st="$(rank "$stamped")"
  if   [ "$rs" -lt "$st" ]; then
    log "DENY  | $owner/$ws — degradación $stamped→$resolved → restart (re-resuelve)"
    act "degradación restart" "$CODER_BIN" restart "$owner/$ws" --yes
    n_demote=$((n_demote+1))
  elif [ "$rs" -gt "$st" ]; then
    log "GRANT | $owner/$ws — promoción $stamped→$resolved → no-op (esperar rebuild natural)"
    n_promote=$((n_promote+1))
  else
    log "OK    | $owner/$ws — rol $stamped sin cambios"
    n_ok=$((n_ok+1))
  fi
done < <(printf '%s' "$WS_JSON" | jq -r '.[] | [.owner_name, .name] | @tsv')

log "resumen: ok=$n_ok offboard=$n_offb degradación=$n_demote promoción=$n_promote skip=$n_skip (DRY_RUN=$DRY_RUN)"
