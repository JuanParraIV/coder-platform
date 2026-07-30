# TODO List — Coder + Claude RBAC Platform

## Estado General

| # | Fase | Estado |
|---|------|--------|
| 1 | Brainstorming + Diseño | ✅ done |
| 2 | Spec consolidado | ✅ done |
| 3 | Plan de implementación | ✅ done |
| 4 | Implementación (8 tasks) | ✅ done |
| 5 | Roles y Skills (Architect, Developer, QA) | ✅ done |
| 6 | Gestión de Secretos (ESO + OAuth) | ✅ done |
| 7 | Jira OAuth automático | ✅ done |
| 8 | Análisis specs Waitly | ✅ done |
| 9 | Rediseño spec template (contrato comportamental) | ✅ done |

---

## Documentación

| # | Archivo | Contenido | Estado |
|---|---------|-----------|--------|
| 0 | 00-decisiones.md | Registro de decisiones | ✅ |
| 1 | 01-arquitectura-general.md | Diagrama y componentes | ✅ |
| 2 | 02-rbac-mapping-roles.md | RBAC, GitHub Teams, matriz | ✅ |
| 3 | 03-template-terraform.md | Template HCL completo | ✅ |
| 4 | 04-skills-mcp-por-rol.md | Skills y MCP configs | ⚠️ Actualizar con 3 roles |
| 5 | 05-network-isolation.md | Cilium policies | ✅ |
| 6 | 06-imagen-base-docker.md | Dockerfile multi-stage | ✅ |
| 7 | 07-observabilidad-audit.md | Prometheus + Grafana | ✅ |
| 8 | 08-deployment-operacion.md | Helm, rollout, Day-2 | ✅ |
| 9 | 09-gestion-secretos.md | ESO + per-user tokens | ✅ |
| 10 | 10-jira-oauth-automatico.md | OAuth 3LO para Jira | ✅ |
| 11 | 11-analisis-specs-waitly.md | Análisis de specs Waitly | ✅ |
| 12 | 12-roles-y-skills.md | 3 roles, skills, flujo specs | ✅ |
| 13 | 13-authz-a-escala.md | AuthZ a escala: PAT → GitHub App → IdP group sync | ✅ NEW |

---

## Decisiones clave desde el inicio

1. Cloud: Agnostic
2. IdP: GitHub OAuth
3. Mapping: GitHub Teams → Coder Roles (automático)
4. Roles: Architect + Developer + QA (3 roles)
5. LLM: Claude ahora, model-agnostic
6. Interfaz: code-server + Claude Code CLI (2 botones)
7. Template: Híbrido (base + overlay por rol)
8. Network: Cilium FQDN isolation
9. Secretos: External Secrets Operator, per-user, OAuth para Jira
10. Specs: Un solo spec unificado (contrato de comportamiento), 3 consumidores
11. Skills: Arquitectura SKILL.md + README.md + references/

---

## Progreso de implementación (homelab) — 2026-07-09

| Área | Estado | Notas / docs |
|------|--------|--------------|
| RBAC Nivel 3 (rol por GitHub Team) | ✅ E2E | GitHub App = AuthZ; qa/developer/architect validados con cuentas reales. `docs/rbac-setup.md`, `docs/github-app-config.md` |
| Prioridad de rol | ✅ | Least-privilege (qa<developer<architect) + one-role-per-user. `02-rbac-mapping-roles.md` |
| Persistencia Nivel 6 (reboot) | ✅ | systemd+linger + `unless-stopped`. `docs/RUNBOOK.md` |
| Overlays por rol (Nivel 2) | ✅ E2E | skills+MCP+persona auto al entrar. bind-mount `overlays/`→`/opt/overlays` |
| MCP **github** | ✅ conecta | external-auth OAuth per-usuario (solo repos del user) |
| MCP **atlassian** (Jira) | ✅ conecta | `uvx mcp-atlassian` + API token; ve proyecto SCRUM |
| MCP **playwright** | ✅ conecta | `@playwright/mcp` (browser local); startup instala Node 20 + chromium |
| MCP Confluence | ✅ conecta | provisionado; `CONFLUENCE_URL=.../wiki`; ve spaces (rol architect) |
| MCP sonar / SAST | ⏳ fase DevSecOps | **retirado del template y overlays** (era gate fantasma). Receta de re-activación en `docs/CONFIGURACION.md` → "SonarCloud / SAST — PENDIENTE". Evaluar Sonar en CI vs MCP en workspace. |
| Template prod-oidc: MCP/secretos | ✅ replicado | node20/uv/github-token/JIRA/chromium igual que mvp-embedded |
| Secretos MCP per-usuario | ✅ | github + **atlassian (Jira/Confluence) OAuth per-usuario** (external-auth). Sonar shared pendiente token. |
| Cambiar de org (GitHub/Jira/Sonar) | ✅ fácil | config central + `scripts/apply-config.sh`. `docs/CONFIGURACION.md` |
| Template prod-oidc (N3 OIDC) | 🟩 scaffold | bloqueado por IdP real + Coder Premium. `13-authz-a-escala.md` |

Docs nuevos fuera de TO-BE: `docs/RUNBOOK-github-app.md`, `docs/RUNBOOK-prod-oidc.md`,
`docs/github-app-config.md`, **`docs/external-auth-oauth-pattern.md`** (patrón reutilizable
MCP per-usuario vía external-auth: GitHub + Atlassian), **`docs/CONFIGURACION.md`**
(cambiar de org GitHub/Jira/Sonar en 1 edición + 1 comando) + `scripts/apply-config.sh`,
**`docs/RUNBOOK-llm-backend.md`** (configurar backend LLM de Claude Code paso a paso:
Claude Pro `setup-token` / API key / Vertex + troubleshooting 401).

## Última actualización: 2026-07-09