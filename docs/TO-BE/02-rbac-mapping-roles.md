# Sección 2: RBAC y Mapping de Roles

## Estado: ✅ Aprobada

## Modelo de Roles

GitHub Org: qintess
│
├── Team: tech-leads           →  Coder Role: architect  (activo)
├── Team: platform-developers  →  Coder Role: developer  (activo)
├── Team: qa-engineers         →  Coder Role: qa         (activo)
├── Team: devops-sre           →  Coder Role: devops     (futuro)
├── Team: cybersecurity        →  Coder Role: security   (futuro)
└── Team: product-managers     →  Coder Role: product    (futuro)

## Norma: ONE-ROLE-PER-USER (2026-07-09)

**Regla de diseño:** cada persona pertenece a **un solo** team de rol. El
multi-team es una **excepción**, no el modo normal. Diseñar los teams para que
nadie acumule roles → el conflicto prácticamente no existe.

## Prioridad de resolución (si multi-team) — LEAST-PRIVILEGE (red de seguridad)

Cuando SÍ ocurre multi-team (excepción), gana el rol **MENOS permisivo**
(anti-escalada, deny-by-default para banca): falla-seguro y obliga a que un
humano conceda más acceso explícitamente si de verdad hace falta.

Permisividad: **qa < developer < architect** → orden de selección (primer match)
del menos al más permisivo: **qa → developer → architect**. Fail-closed: sin team
válido → `unknown`.

## Flujo de Resolución del Rol

┌──────────────┐     ┌─────────────────┐     ┌──────────────────┐
│ GitHub OAuth │────▶│ Coder Auth Hook  │────▶│ Terraform var.role│
│   Login      │     │ (team lookup)    │     │   = "developer"  │
└──────────────┘     └─────────────────┘     └────────┬─────────┘
                                                       │
                              ┌─────────────────────────┘
                              ▼
                     ┌─────────────────┐
                     │ Overlay Selector │
                     │  if developer:  │
                     │   mount dev/    │
                     │  if qa:         │
                     │   mount qa/     │
                     └─────────────────┘

## Resolución Automática de Rol

El rol se asigna **automáticamente** sin intervención del usuario.

**Regla de prioridad (multi-team) — least-privilege:**
qa < developer < architect (gana el MENOS permisivo)

Si un usuario pertenece a múltiples teams, se asigna el rol **menos** permisivo.
El usuario NO selecciona rol — Coder lo detecta y provisiona sin preguntar.

## Implementación en Coder Template (Terraform)

hcl
# El rol se resuelve automáticamente via external data source
data "external" "user_role" {
  program = ["bash", "${path.module}/scripts/resolve-role.sh"]
  query = {
    github_username = data.coder_workspace_owner.me.name
    github_org      = "qintess"
  }
}

locals {
  role = data.external.user_role.result.role

  role_config = {
    developer = {
      claude_md    = "overlays/developer/CLAUDE.md"
      mcp_config   = "overlays/developer/mcp-config.json"
      skills_path  = "overlays/developer/skills/"
      egress_cidrs = ["api.github.com", "api.anthropic.com", "registry.npmjs.org"]
    }
    qa = {
      claude_md    = "overlays/qa/CLAUDE.md"
      mcp_config   = "overlays/qa/mcp-config.json"
      skills_path  = "overlays/qa/skills/"
      egress_cidrs = ["api.github.com", "api.anthropic.com", "jira.atlassian.net"]
    }
  }

  active_config = local.role_config[local.role]
}

### Script: resolve-role.sh

bash
#!/bin/bash
# Lee stdin (JSON query de Terraform external)
eval "$(jq -r '@sh "USERNAME=\(.github_username) ORG=\(.github_org)"')"

# Consulta teams del usuario via GitHub API
TEAMS=$(gh api "/orgs/$ORG/members/$USERNAME/teams" --jq '.[].slug' 2>/dev/null)

# Prioridad least-privilege: qa < developer < architect (gana el menos permisivo)
if echo "$TEAMS" | grep -q "platform-developers"; then
  ROLE="developer"
elif echo "$TEAMS" | grep -q "qa-engineers"; then
  ROLE="qa"
elif echo "$TEAMS" | grep -q "product-managers"; then
  ROLE="product"
else
  ROLE="developer"  # fallback
fi

jq -n --arg role "$ROLE" '{"role": $role}'

## Matriz de Permisos por Rol

| Recurso | Developer | QA |
|---------|-----------|-----|
| **Skills** | code-review-security, feature-implementation, jira-dev-sync | bdd-test-generation, coverage-gap-analysis, unit-test-generation |
| **MCP Servers** | GitHub (read/write), SonarCloud, Docker Registry | GitHub (read), Jira (read/write), Test Infra |
| **Sub-agentes** | explore, task, code-review, security-review | explore, task, rubber-duck |
| **Repos accesibles** | Todos los repos del team | Repos del team + test repos |
| **Egress network** | GitHub API, npm, PyPI, Docker Hub, Anthropic | GitHub API, Jira, Selenium Grid, Anthropic |
| **IDE extensions** | Full marketplace | Full marketplace |
| **Claude tools** | bash, edit, create, view, grep, glob | bash, edit, create, view, grep, glob |
| **Governance gates** | BDD-first (no code sin .feature), scope limits | Coverage threshold, test quality gates |