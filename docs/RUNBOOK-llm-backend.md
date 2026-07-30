# RUNBOOK — Configurar el backend LLM de Claude Code (paso a paso)

Cómo dejar `claude` autenticado dentro de los workspaces. Backend **swappable**
desde el config central. Precedencia: **vertex > bedrock > subscription > api_key**.

- Config central (git-ignored, 600): `~/.config/coderv2/mvp-embedded-vars.yaml`
- Aplicar: `scripts/apply-config.sh`
- Variables del template: `llm_backend`, `claude_code_oauth_token`, `anthropic_api_key`,
  `vertex_project`, `vertex_region` (ver `templates/mvp-embedded/main.tf` → `local.llm_env`).

> El template arma solo las env vars del backend elegido (`local.llm_env`), evitando
> un `ANTHROPIC_API_KEY` vacío que dejaba a claude sin autenticar.

---

## Opción A — Claude Pro/Max (tu suscripción)  ← lo que usas hoy

### A1. Generar el token (una vez, interactivo)
```bash
claude setup-token
```
- **No lo interrumpas.** Abre la URL que imprime, inicia sesión con tu cuenta Claude
  Pro/Max y **autoriza**.
- Al terminar imprime el token en **una sola línea**. Empieza por **`sk-ant-oat01-`**.
- **Copia el token COMPLETO** (suele ser ~100+ chars; si lo cortas, dará 401).

### A2. Pegarlo en el config central
```bash
nano ~/.config/coderv2/mvp-embedded-vars.yaml
```
```yaml
llm_backend: "subscription"
claude_code_oauth_token: "sk-ant-oat01-...."   # solo el token, dentro de las comillas
```
> Pega SOLO el token entre las comillas. Nada de comentarios ni espacios en esa línea.

### A3. VERIFICAR que autentica (ANTES de aplicar)
Evita pushear un token malo. Test contra un workspace corriendo (ej. devbox):
```bash
C=coder-JuanParraIV-devbox
VF=~/.config/coderv2/mvp-embedded-vars.yaml
TOKEN=$(python3 -c 'import sys,re
for l in open(sys.argv[1]):
 if l.strip().startswith("claude_code_oauth_token"):
  m=re.search(r"\"([^\"]*)\"",l); print(m.group(1) if m else ""); break' "$VF")
echo "len=${#TOKEN} prefijo=${TOKEN:0:12}"
docker exec -e CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" "$C" bash -lc \
  'export PATH="$HOME/.local/bin:$PATH"; timeout 45 claude -p "di: AUTH_OK"' 2>&1 | head -4
```
- **OK** = responde algo (p.ej. `AUTH_OK`).
- **Falla** = `401 Invalid bearer token` → ver Troubleshooting.

### A4. Aplicar
```bash
scripts/apply-config.sh
```
Luego el **owner reinicia su workspace** desde la UI → `claude` dentro ya usa tu Pro.

---

## Troubleshooting (lo que nos pasó)

| Síntoma | Causa | Fix |
|---|---|---|
| Valor no empieza por `sk-ant-oat01-` (ej. `bngyd3r…`) | Se pegó algo que NO es el token (flujo interrumpido / clipboard equivocado) | Re-correr `claude setup-token` completo |
| Token con un `#` o texto extra pegado | Se copió junto al comentario de la línea o basura | Pegar SOLO el token; la línea del comentario va aparte |
| Formato correcto pero **401 Invalid bearer token** | Token **incompleto** (cortado al copiar) o flujo no completado | Regenerar y copiar COMPLETO (una línea) |
| 401 aún con token correcto | Credencial guardada en `~/.claude.json` pisando | Probar en HOME limpio: `export HOME=/tmp/h` antes de `claude -p` |
| API len=10 al inspeccionar la variable en Coder | Es el **enmascarado** de secretos de Coder, no el largo real | Ignorar; validar por el auth test, no por la API |

---

## Opción B — API key (plan B, robusto)

Si `setup-token` sigue fallando. Es **pago por token** (no tu Pro), pero seguro.
1. console.anthropic.com → **API Keys** → crea una (`sk-ant-api03-...`).
2. Config central:
   ```yaml
   llm_backend: "api_key"
   anthropic_api_key: "sk-ant-api03-..."
   ```
3. `scripts/apply-config.sh` + Restart del workspace.

---

## Opción C — Vertex AI (futuro, GCP)

Cuando tengas proyecto GCP. Model-agnostic (Decisión #5).
1. Config central:
   ```yaml
   llm_backend: "vertex"
   vertex_project: "mi-proyecto-gcp"
   vertex_region: "us-east5"
   ```
2. El workspace necesita **credenciales GCP (ADC)** — service account con acceso a
   Vertex AI (montar la key o usar Workload Identity en K8s).
3. `scripts/apply-config.sh` + Restart.
> El template setea solo `CLAUDE_CODE_USE_VERTEX=1` + `ANTHROPIC_VERTEX_PROJECT_ID`
> + `CLOUD_ML_REGION`. (Bedrock/AWS = `llm_backend: "bedrock"` + creds AWS.)

---

## Notas

- **Multi-usuario:** el token/suscripción es **compartido** (una cuenta). Para
  multi-user real → Vertex/Bedrock (billing central) o token por usuario.
- **Dónde vive el secreto:** `~/.config/coderv2/mvp-embedded-vars.yaml` (600,
  git-ignored). En prod → secret manager (ver `docs/TO-BE/09-gestion-secretos.md`).
- **Reconfigurar desde cero:** repetir A1–A4 (o B/C). Nada más depende de esto.
