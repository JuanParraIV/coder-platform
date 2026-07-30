# Cambiar de organización (GitHub / Jira) — guía breve

Todo lo que cambia por org/cliente está en **2 sitios**, y se aplica con **1 comando**:

| Sitio | Qué contiene | Sensible |
|-------|--------------|----------|
| **Config central**: `~/.config/coderv2/mvp-embedded-vars.yaml` | `github_org`, `llm_backend` + backend LLM | git-ignored, 600 |
| **Secretos OAuth**: `~/.config/coderv2/server.env` | client id/secret de las OAuth Apps + GitHub App | git-ignored, 600 |

**Aplicar cambios del config central:**
```bash
scripts/apply-config.sh
```
**Si cambiaste `server.env`:**
```bash
systemctl --user restart coder.service
```

---

## Cambiar la ORG de GitHub

1. **Config central** → `github_org: "<nueva-org>"`.
2. **server.env** → `CODER_OAUTH2_GITHUB_ALLOWED_ORGS=<nueva-org>` (quién puede entrar).
3. **GitHub App** `coder-rbac-resolver` (resuelve el rol): instálala en la **nueva org**
   y actualiza `GITHUB_APP_INSTALLATION_ID` en server.env (ver `docs/github-app-config.md`).
4. Crea en la nueva org los **teams** `platform-developers`, `qa-engineers`, `architects`.
5. Aplicar:
   ```bash
   scripts/apply-config.sh && systemctl --user restart coder.service
   ```

> El acceso a **repos** (github MCP) es per-usuario vía external-auth y no depende de
> `github_org` — cada usuario ve sus repos automáticamente.

## Cambiar la instancia de JIRA / Confluence

Jira/Confluence van por **OAuth per-usuario** (external-auth `atlassian`), no por
variables. Dos escenarios:

- **Mismo OAuth App, otro sitio Atlassian**: no cambias nada aquí — el usuario, al
  hacer *Connect*, **elige el sitio** (Resource-level). El cloud id se autodetecta.
- **Otra OAuth App** (otro tenant/cliente): en **server.env** cambia
  `CODER_EXTERNAL_AUTH_1_CLIENT_ID` y `..._CLIENT_SECRET` (crea la app en
  developer.atlassian.com con callback `.../external-auth/atlassian/callback`), luego:
  ```bash
  systemctl --user restart coder.service
  ```
  Cada usuario re-hace *Connect* (Account → External Authentication).

> Para que un usuario tenga acceso, debe ser **miembro del sitio Atlassian** con
> permisos en Jira/Confluence (se controla en admin.atlassian.com, no en Coder).

## SonarCloud / SAST — PENDIENTE fase DevSecOps

> **No configurado a propósito.** El MCP de Sonar y sus variables se retiraron para
> no dejar un *quality gate* fantasma (server placeholder `@mcp/sonarcloud-server`, sin
> token real). Se abordará cuando entre la parte **DevSecOps** de la plataforma.

**Cuando llegue esa fase, para activarlo:**
1. **MCP** → añadir el server real de Sonar en `overlays/developer/mcp-config.json`
   (reemplaza el placeholder `@mcp/sonarcloud-server` por el server oficial), con
   `env: { SONAR_TOKEN, SONAR_ORG }`.
2. **Template** `templates/mvp-embedded/main.tf` → reañadir las variables
   `variable "sonar_org"` y `variable "sonar_token"` (sensitive) y volver a exponerlas
   en el `agent env` (`SONAR_ORG = var.sonar_org`, `SONAR_TOKEN = var.sonar_token`).
3. **Config central** `~/.config/coderv2/mvp-embedded-vars.yaml` → descomentar y
   rellenar `sonar_org` / `sonar_token`.
4. Aplicar: `scripts/apply-config.sh` y el owner reinicia su workspace.

> Alternativa DevSecOps más robusta: mover el análisis Sonar/SAST al **pipeline de CI**
> (quality gate en el PR) en lugar de un MCP en el workspace del developer.

## Cambiar el BACKEND LLM de Claude Code

> **Paso a paso detallado + troubleshooting: `docs/RUNBOOK-llm-backend.md`.**

Config central → `llm_backend` + los campos del backend. Precedencia:
**vertex > bedrock > subscription (token) > api_key**.

**Ahora — Claude Pro/Max (tu suscripción):**
1. Genera el token (una vez, interactivo, con tu cuenta Claude):
   ```bash
   claude setup-token
   ```
2. Config central:
   ```yaml
   llm_backend: "subscription"
   claude_code_oauth_token: "<token de setup-token>"
   ```
3. `scripts/apply-config.sh`

**Futuro — Vertex AI (GCP):**
```yaml
llm_backend: "vertex"
vertex_project: "mi-proyecto-gcp"
vertex_region: "us-east5"
```
+ el workspace necesita credenciales GCP (ADC). Luego `scripts/apply-config.sh`.
> `CLAUDE_CODE_USE_VERTEX=1` + `ANTHROPIC_VERTEX_PROJECT_ID` + `CLOUD_ML_REGION`
> se setean solos según `llm_backend`.

**Alternativas:** `bedrock` (AWS) o `api_key` (pago por token, campo `anthropic_api_key`).

> El token/suscripción es **compartido** por ahora (tu Pro). Para multi-usuario real,
> Vertex/Bedrock (billing central) o un token por usuario. Diseño model-agnostic
> (Decisión #5).

---

## Resumen (lo más frecuente)

```bash
# 1) editar el config central
nano ~/.config/coderv2/mvp-embedded-vars.yaml
# 2) aplicar
scripts/apply-config.sh
# 3) (solo si tocaste server.env) reiniciar
systemctl --user restart coder.service
# 4) cada usuario: Restart de su workspace desde la UI (inyecta sus tokens)
```

Modelo per-usuario: **tú configuras la org una vez**; el acceso real (repos, Jira,
Confluence) lo determina la identidad de cada usuario en GitHub/Atlassian, reflejado
solo en su workspace. Ver `docs/external-auth-oauth-pattern.md`.
