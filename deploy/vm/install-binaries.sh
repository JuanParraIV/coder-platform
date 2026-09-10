#!/usr/bin/env bash
# =============================================================================
# install-binaries.sh — Instala SOLO los binarios que necesita coder-platform
# =============================================================================
# Standalone: NO depende del repo. Pásalo suelto a la VM (RustDesk / copy-paste),
# córrelo, y luego usa `gh auth login` + `gh repo clone` para traer el repo.
#
# Instala: curl jq git openssl gnupg ca-certificates · gh (GitHub CLI) ·
#          docker (+ compose) · coder (binario, versión fijada abajo).
# Idempotente: re-ejecutable; si algo ya está, no reinstala.
#
# USO (en la VM, como el usuario dueño de Coder — NO root):
#   bash install-binaries.sh
#   # luego:
#   gh auth login
#   gh repo clone JuanParraIV/coder-platform ~/coder-platform
#   cd ~/coder-platform && bash deploy/vm/bootstrap-vm.sh
# -----------------------------------------------------------------------------
set -euo pipefail

# Versión de Coder (= la del homelab, para reproducibilidad).
CODER_VERSION="${CODER_VERSION:-2.35.1}"

c_ok()   { printf '\033[0;32m[ OK ]\033[0m %s\n' "$*"; }
c_info() { printf '\033[0;36m[INFO]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[0;33m[WARN]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*" >&2; }
die()    { c_err "$*"; exit 1; }

# --- Preflight ---------------------------------------------------------------
[[ "$(id -u)" -ne 0 ]] || die "No ejecutes como root. Usa el usuario dueño de Coder (con sudo)."
command -v sudo >/dev/null || die "Se requiere sudo."
[[ -f /etc/os-release ]] && . /etc/os-release
[[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *debian* ]] \
  || c_warn "Distro '${ID:-?}' no verificada; asumo apt/Debian-like."
case "$(uname -m)" in
  x86_64)  ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  *) die "Arquitectura $(uname -m) no soportada." ;;
esac
c_ok "Preflight OK (arch=${ARCH}, Coder v${CODER_VERSION})."

# --- 1) Paquetes base --------------------------------------------------------
c_info "Instalando paquetes base (curl jq git openssl gnupg ca-certificates)…"
sudo apt-get update -qq
sudo apt-get install -y -qq curl jq git openssl ca-certificates gnupg coreutils >/dev/null
c_ok "Paquetes base listos."

# --- 2) GitHub CLI (gh) — repo oficial --------------------------------------
if command -v gh >/dev/null 2>&1; then
  c_ok "gh ya presente: $(gh --version | head -1)"
else
  c_info "Instalando GitHub CLI (gh)…"
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
  c_info "Instalando Docker (get.docker.com)…"
  curl -fsSL https://get.docker.com | sudo sh
  c_ok "Docker instalado: $(docker --version)"
fi
sudo systemctl enable --now docker >/dev/null 2>&1 || true
if ! id -nG "$USER" | grep -qw docker; then
  sudo usermod -aG docker "$USER"
  c_warn "Te añadí al grupo 'docker': cierra sesión y vuelve a entrar (o 'newgrp docker') para que aplique."
fi

# --- 4) Binario Coder (pinneado) --------------------------------------------
CODER_BIN="${HOME}/.local/bin/coder"
if [[ -x "${CODER_BIN}" ]] && "${CODER_BIN}" version 2>/dev/null | grep -q "v${CODER_VERSION}"; then
  c_ok "Coder v${CODER_VERSION} ya instalado."
else
  c_info "Descargando Coder v${CODER_VERSION} (~400 MB)…"
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
if ! grep -q "${HOME}/.local/bin" <<<"${PATH}"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${HOME}/.bashrc"
  c_warn "Añadí ~/.local/bin al PATH en ~/.bashrc. Ejecuta: source ~/.bashrc (o reabre la terminal)."
fi

# --- 5) Verificación ---------------------------------------------------------
c_info "Verificando binarios…"
MISSING=0
for bin in coder docker git gh jq curl openssl base64 sed awk; do
  if command -v "$bin" >/dev/null 2>&1 || [[ "$bin" == coder && -x "${CODER_BIN}" ]]; then
    c_ok "$(printf '%-8s' "$bin") OK"
  else
    c_err "$(printf '%-8s' "$bin") FALTA"; MISSING=1
  fi
done

cat <<EOF

$([[ "${MISSING}" == "0" ]] && c_ok "Todos los binarios instalados." || c_warn "Faltan binarios (ver arriba).")
────────────────────────────────────────────────────────────────────────────
SIGUIENTE:
  1. (si te añadió a 'docker') cierra sesión y vuelve a entrar, o: newgrp docker
  2. gh auth login                         # autentícate en GitHub
  3. gh repo clone JuanParraIV/coder-platform ~/coder-platform
  4. cd ~/coder-platform && bash deploy/vm/bootstrap-vm.sh
────────────────────────────────────────────────────────────────────────────
EOF
