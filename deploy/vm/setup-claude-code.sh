#!/usr/bin/env bash
# =============================================================================
# setup-claude-code.sh — Instala Claude Code "potente" en la VM (como el local)
# =============================================================================
# Deja Claude Code igual que la máquina de referencia:
#   - Node.js LTS (20)
#   - Claude Code CLI (@anthropic-ai/claude-code) — trae las skills integradas
#     (code-review, dataviz, artifact-design, simplify, run, verify, etc.)
#   - Marketplace oficial de plugins (anthropics/claude-plugins-official) para
#     instalar skills extra con /plugin
#   - Tema: dark
# NO automatiza el login (es OAuth interactivo): al final te dice cómo.
#
# USO (en la VM, como el usuario que usará Claude Code — NO root):
#   bash setup-claude-code.sh
# -----------------------------------------------------------------------------
set -euo pipefail

c_ok()   { printf '\033[0;32m[ OK ]\033[0m %s\n' "$*"; }
c_info() { printf '\033[0;36m[INFO]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[0;33m[WARN]\033[0m %s\n' "$*"; }
die()    { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -ne 0 ]] || die "No ejecutes como root. Usa tu usuario normal (con sudo)."
command -v sudo >/dev/null || die "Se requiere sudo."

# --- 1) Node.js LTS (20) -----------------------------------------------------
NODE_OK=0
if command -v node >/dev/null 2>&1; then
  NMAJ="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  [[ "${NMAJ}" -ge 18 ]] && NODE_OK=1
fi
if [[ "${NODE_OK}" == "1" ]]; then
  c_ok "Node ya presente: $(node --version)"
else
  c_info "Instalando Node.js 20 LTS (NodeSource)…"
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
  c_ok "Node instalado: $(node --version)"
fi

# --- 2) Claude Code CLI ------------------------------------------------------
# Instalación global sin sudo: prefijo npm en el HOME (evita EACCES).
NPM_PREFIX="${HOME}/.npm-global"
mkdir -p "${NPM_PREFIX}"
npm config set prefix "${NPM_PREFIX}" >/dev/null 2>&1 || true
case ":${PATH}:" in
  *":${NPM_PREFIX}/bin:"*) : ;;
  *) echo "export PATH=\"${NPM_PREFIX}/bin:\$PATH\"" >> "${HOME}/.bashrc"
     export PATH="${NPM_PREFIX}/bin:${PATH}"
     c_warn "Añadí ${NPM_PREFIX}/bin al PATH (~/.bashrc). Si 'claude' no aparece luego, ejecuta: source ~/.bashrc" ;;
esac

c_info "Instalando/actualizando Claude Code…"
npm install -g @anthropic-ai/claude-code
hash -r 2>/dev/null || true
c_ok "Claude Code: $(claude --version 2>/dev/null || echo '(reabre la terminal / source ~/.bashrc)')"

# --- 3) Config ~/.claude (tema + carpetas) -----------------------------------
mkdir -p "${HOME}/.claude/plugins/marketplaces"
SETTINGS="${HOME}/.claude/settings.json"
if [[ -f "${SETTINGS}" ]]; then
  tmp="$(mktemp)"; jq '.theme = "dark"' "${SETTINGS}" > "${tmp}" && mv "${tmp}" "${SETTINGS}"
else
  printf '{\n  "theme": "dark"\n}\n' > "${SETTINGS}"
fi
c_ok "settings.json (theme=dark) listo."

# --- 4) Marketplace oficial de plugins --------------------------------------
MKT_REPO="anthropics/claude-plugins-official"
MKT_DIR="${HOME}/.claude/plugins/marketplaces/claude-plugins-official"
if [[ -d "${MKT_DIR}/.git" ]]; then
  c_info "Actualizando marketplace oficial…"
  git -C "${MKT_DIR}" pull --ff-only >/dev/null 2>&1 || c_warn "No pude actualizar el marketplace (sigo)."
else
  c_info "Clonando marketplace oficial (${MKT_REPO})…"
  git clone --depth 1 "https://github.com/${MKT_REPO}" "${MKT_DIR}" || c_warn "No pude clonar el marketplace (lo puedes añadir luego con /plugin)."
fi
# Registrar el marketplace para que Claude lo reconozca.
cat > "${HOME}/.claude/plugins/known_marketplaces.json" <<EOF
{
  "claude-plugins-official": {
    "source": { "source": "github", "repo": "${MKT_REPO}" },
    "installLocation": "${MKT_DIR}",
    "lastUpdated": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  }
}
EOF
c_ok "Marketplace oficial registrado."

# --- 5) Próximos pasos -------------------------------------------------------
cat <<EOF

$(c_ok "Claude Code instalado.")
────────────────────────────────────────────────────────────────────────────
1. Si 'claude' no responde aún:   source ~/.bashrc
2. Inicia sesión (OAuth interactivo):
      claude            # dentro, escribe:  /login
   (o directamente:     claude   y sigue el flujo de autenticación)
3. Ver skills disponibles dentro de claude:   /help   o   escribe "/"
4. Instalar skills extra del marketplace:     /plugin
────────────────────────────────────────────────────────────────────────────
Las skills integradas (code-review, dataviz, artifact-design, simplify, run,
verify, security-review, etc.) ya vienen con esta versión de Claude Code.
EOF
