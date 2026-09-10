#!/usr/bin/env bash
# =============================================================================
# bootstrap-vm.sh — Instala Coder + Claude Code RBAC platform en una VM Ubuntu
# =============================================================================
# Reproduce la instancia del homelab: Coder standalone (Postgres embebido) como
# systemd --user + linger, Docker para los workspaces, overlays por bind-mount.
#
# NO baja secretos: la parte de credenciales va en ~/.config/coderv2/server.env
# (usa deploy/vm/server.env.example como plantilla). Idempotente: re-ejecutable.
#
# USO (en la VM, como el usuario que será dueño de Coder — NO root):
#   1) git clone <repo> ~/coder-platform   (o copia el repo por RustDesk)
#   2) cp deploy/vm/vm-deploy.conf.example deploy/vm/vm-deploy.conf  && edítalo
#   3) bash deploy/vm/bootstrap-vm.sh
#   4) rellena ~/.config/coderv2/server.env  (ver server.env.example)
#   5) systemctl --user restart coder   &&   sigue docs/RUNBOOK-vm-deploy.md
# -----------------------------------------------------------------------------
set -euo pipefail

# --- Colores / helpers -------------------------------------------------------
c_ok()   { printf '\033[0;32m[ OK ]\033[0m %s\n' "$*"; }
c_info() { printf '\033[0;36m[INFO]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[0;33m[WARN]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*" >&2; }
die()    { c_err "$*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${SCRIPT_DIR}/vm-deploy.conf"

# --- 0) Preflight ------------------------------------------------------------
c_info "Preflight…"
[[ "$(id -u)" -ne 0 ]] || die "No ejecutes como root. Usa el usuario dueño de Coder."
command -v sudo >/dev/null || die "Se requiere sudo para instalar paquetes."
[[ -f /etc/os-release ]] && . /etc/os-release
[[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *debian* ]] \
  || c_warn "Distro '${ID:-desconocida}' no verificada; el script asume apt/Debian-like."
case "$(uname -m)" in
  x86_64)  ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  *) die "Arquitectura $(uname -m) no soportada por este script." ;;
esac

# --- 1) Config ---------------------------------------------------------------
[[ -f "${CONF}" ]] || die "Falta ${CONF}. Copia vm-deploy.conf.example y edítalo."
# shellcheck disable=SC1090
source "${CONF}"
: "${CODER_VERSION:?falta CODER_VERSION en vm-deploy.conf}"
: "${REPO_PATH:?falta REPO_PATH}"
: "${CODER_ACCESS_URL:?falta CODER_ACCESS_URL}"
: "${CODER_HTTP_ADDRESS:?falta CODER_HTTP_ADDRESS}"
[[ "${CODER_ACCESS_URL}" == *CHANGE_ME* ]] && die "Edita CODER_ACCESS_URL en ${CONF} (no dejes CHANGE_ME)."
c_ok "Config cargada. ACCESS_URL=${CODER_ACCESS_URL}  Coder v${CODER_VERSION}  arch=${ARCH}"

# --- 2) Paquetes base --------------------------------------------------------
# Binarios del host que usan los scripts de la plataforma:
#   curl/jq/git (varios) · openssl+base64 (firma JWT del GitHub App en
#   resolve-role.sh/gh-app-token.sh) · gnupg/ca-certificates (repos apt).
# base64/sed/awk vienen en coreutils/base del sistema. gh y coder aparte (abajo).
c_info "Instalando paquetes base (curl, jq, git, openssl, ca-certificates, gnupg)…"
sudo apt-get update -qq
sudo apt-get install -y -qq curl jq git openssl ca-certificates gnupg coreutils >/dev/null
c_ok "Paquetes base listos."

# --- 2b) GitHub CLI (gh) — repo oficial -------------------------------------
# Lo usan resolve-role.sh / reconcile-roles.sh (resolución de rol RBAC).
if command -v gh >/dev/null 2>&1; then
  c_ok "gh ya presente: $(gh --version | head -1)"
else
  c_info "Instalando GitHub CLI (gh) desde el repo oficial…"
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq gh >/dev/null
  c_ok "Instalado: $(gh --version | head -1)"
fi

# --- 3) Docker ---------------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
  c_ok "Docker ya presente: $(docker --version)"
else
  c_info "Instalando Docker (script oficial get.docker.com)…"
  curl -fsSL https://get.docker.com | sudo sh
  c_ok "Docker instalado: $(docker --version)"
fi
# El usuario debe estar en el grupo docker (los workspaces son contenedores).
if ! id -nG "$USER" | grep -qw docker; then
  sudo usermod -aG docker "$USER"
  c_warn "Te añadí al grupo 'docker'. DEBES cerrar sesión y volver a entrar (o 'newgrp docker') para que aplique."
  NEED_RELOGIN=1
fi
sudo systemctl enable --now docker >/dev/null 2>&1 || true

# --- 4) Binario Coder (pinneado) --------------------------------------------
CODER_BIN="${HOME}/.local/bin/coder"
if [[ -x "${CODER_BIN}" ]] && "${CODER_BIN}" version 2>/dev/null | grep -q "v${CODER_VERSION}"; then
  c_ok "Coder v${CODER_VERSION} ya instalado."
else
  c_info "Descargando Coder v${CODER_VERSION}…"
  mkdir -p "${HOME}/.local/bin"
  TMP="$(mktemp -d)"
  TARBALL="coder_${CODER_VERSION}_linux_${ARCH}.tar.gz"
  URL="https://github.com/coder/coder/releases/download/v${CODER_VERSION}/${TARBALL}"
  curl -fsSL "${URL}" -o "${TMP}/${TARBALL}" || die "No pude descargar ${URL}"
  # El tarball contiene ./coder (+ LICENSE/README). Extraemos todo y lo ubicamos.
  tar -xzf "${TMP}/${TARBALL}" -C "${TMP}"
  CODER_SRC="$(find "${TMP}" -type f -name coder | head -1)"
  [[ -n "${CODER_SRC}" ]] || die "No hallé el binario 'coder' dentro de ${TARBALL}"
  install -m 0755 "${CODER_SRC}" "${CODER_BIN}"
  rm -rf "${TMP}"
  c_ok "Instalado: $(${CODER_BIN} version | head -1)"
fi
grep -q '.local/bin' <<<"${PATH}" || c_warn "Añade ~/.local/bin a tu PATH (~/.bashrc)."

# --- 5) Repo -----------------------------------------------------------------
if [[ -d "${REPO_PATH}/.git" ]]; then
  c_ok "Repo ya presente en ${REPO_PATH}."
elif [[ -n "${REPO_URL:-}" ]]; then
  c_info "Clonando repo en ${REPO_PATH}…"
  git clone "${REPO_URL}" "${REPO_PATH}" || die "Fallo el clone. ¿Key SSH en la VM? Copia el repo manual y re-ejecuta."
  c_ok "Repo clonado."
else
  die "No existe ${REPO_PATH} y REPO_URL está vacío. Copia el repo a esa ruta y re-ejecuta."
fi

# --- 6) Layout de config (~/.config/coderv2) --------------------------------
CFG="${HOME}/.config/coderv2"
mkdir -p "${CFG}"
chmod 700 "${CFG}"

# start-server.sh (idéntico al homelab): source server.env + exec coder server
cat > "${CFG}/start-server.sh" <<'EOS'
#!/usr/bin/env bash
# Wrapper de arranque del Coder server para systemd --user.
# source del server.env (usa `export`, que EnvironmentFile no parsea) + exec.
set -euo pipefail
ENV_FILE="${HOME}/.config/coderv2/server.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi
exec "${HOME}/.local/bin/coder" server
EOS
chmod 750 "${CFG}/start-server.sh"
c_ok "start-server.sh escrito."

# server.env: si no existe, sembrar desde la plantilla y AVISAR (no arranca sin él).
if [[ -f "${CFG}/server.env" ]]; then
  c_ok "server.env ya existe (no lo toco)."
else
  install -m 600 "${SCRIPT_DIR}/server.env.example" "${CFG}/server.env"
  # Pre-rellena las 3 líneas de red desde vm-deploy.conf (comodidad).
  sed -i "s#^export CODER_ACCESS_URL=.*#export CODER_ACCESS_URL=\"${CODER_ACCESS_URL}\"#" "${CFG}/server.env"
  sed -i "s#^export CODER_HTTP_ADDRESS=.*#export CODER_HTTP_ADDRESS=\"${CODER_HTTP_ADDRESS}\"#" "${CFG}/server.env"
  SERVER_ENV_SEEDED=1
  c_warn "Sembré ${CFG}/server.env desde la plantilla. RELLENA los CHANGE_ME (OAuth, GitHub App) antes de usar en serio."
fi

# --- 7) systemd --user unit + linger ----------------------------------------
UNIT_DIR="${HOME}/.config/systemd/user"
mkdir -p "${UNIT_DIR}"
cat > "${UNIT_DIR}/coder.service" <<EOS
[Unit]
Description=Coder server (self-hosted, coder-platform VM)
Documentation=file://${REPO_PATH}/docs/RUNBOOK-vm-deploy.md
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=%h/.config/coderv2/start-server.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOS
c_ok "coder.service instalado."

# Linger: que el servicio --user arranque en boot sin login interactivo.
if ! loginctl show-user "$USER" 2>/dev/null | grep -q 'Linger=yes'; then
  sudo loginctl enable-linger "$USER"
  c_ok "Linger habilitado (Coder arranca tras reboot)."
else
  c_ok "Linger ya habilitado."
fi

systemctl --user daemon-reload
systemctl --user enable coder.service >/dev/null 2>&1 || true

# --- 8) Arranque + health ----------------------------------------------------
if [[ "${SERVER_ENV_SEEDED:-0}" == "1" ]]; then
  c_warn "NO arranco Coder todavía: server.env tiene placeholders. Rellénalo y luego:"
  echo   "       systemctl --user start coder"
else
  c_info "Arrancando Coder…"
  systemctl --user restart coder.service
  c_info "Esperando health en http://localhost:3000/healthz …"
  for i in $(seq 1 30); do
    if curl -fsS -o /dev/null "http://localhost:3000/healthz" 2>/dev/null; then
      c_ok "Coder responde (HTTP 200 en /healthz)."; HEALTHY=1; break
    fi
    sleep 2
  done
  [[ "${HEALTHY:-0}" == "1" ]] || c_warn "No respondió aún. Revisa: journalctl --user -u coder -n 50 --no-pager"
fi

# --- 8b) Verificación de binarios del host ----------------------------------
c_info "Verificando binarios requeridos por la plataforma…"
MISSING=0
for bin in coder docker git gh jq curl openssl base64 sed awk; do
  if command -v "$bin" >/dev/null 2>&1; then
    c_ok "$(printf '%-8s' "$bin") $(command -v "$bin")"
  else
    c_err "$(printf '%-8s' "$bin") NO ENCONTRADO"; MISSING=1
  fi
done
[[ "${MISSING}" == "0" ]] && c_ok "Todos los binarios presentes." \
  || c_warn "Faltan binarios (ver arriba). Revisa errores de apt más arriba."

# --- 9) Próximos pasos -------------------------------------------------------
cat <<EOF

$(c_ok "Bootstrap mecánico COMPLETO.")
────────────────────────────────────────────────────────────────────────────
PRÓXIMOS PASOS (manuales — ver docs/RUNBOOK-vm-deploy.md):

  1. ${NEED_RELOGIN:+[!] Cierra sesión y vuelve a entrar (grupo docker), luego: }rellena  ${CFG}/server.env
        - OAuth App GitHub (login) + callback = ${CODER_ACCESS_URL}/api/v2/users/oauth2/github/callback
        - external-auth github  + callback   = ${CODER_ACCESS_URL}/external-auth/github/callback
        - external-auth atlassian + callback = ${CODER_ACCESS_URL}/external-auth/atlassian/callback
        - GitHub App (rol RBAC): copia el .pem a ${CFG}/github-app.pem  (chmod 600)
  2. Firewall: abre el puerto 3000/tcp hacia los usuarios (o pon reverse proxy).
  3. systemctl --user restart coder     # tras rellenar server.env
  4. Crea el primer admin:   ${CODER_BIN} login ${CODER_ACCESS_URL}
  5. Sube la plantilla mvp-embedded (override overlays_host_path a ${REPO_PATH}/overlays):
        cd ${REPO_PATH}/templates/mvp-embedded
        ${CODER_BIN} templates push mvp-embedded \\
          --var overlays_host_path=${REPO_PATH}/overlays --yes
  6. Configura los GitHub Teams → roles (developer/qa/architect) y prueba un workspace.
────────────────────────────────────────────────────────────────────────────
EOF
