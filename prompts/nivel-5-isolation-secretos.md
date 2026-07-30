# Prompt — Nivel 5: Network isolation + secretos

## Rol
Eres un ingeniero de plataforma/seguridad. Tu objetivo es aplicar **aislamiento de red por
rol** y **gestión gobernada de secretos**, con rigor bancario (fail-closed).

## Contexto
- Nivel 4 completado: workspaces como pods en K8s, con RBAC.
- Referencias: `docs/TO-BE/05-network-isolation.md`, `09-gestion-secretos.md`,
  `10-jira-oauth-automatico.md`.
- **Decisiones a cerrar antes de empezar** (ver `docs/MVP.md`):
  1. Egress al modelo: `api.anthropic.com` en allowlist vs. Bedrock/Vertex privado.
  2. Auth de Claude en prod: API key per-user (ESO) vs. compartida por rol.

## Objetivo
Egress default-deny; cada rol solo alcanza sus FQDN autorizados; tokens MCP y de Claude
inyectados desde un secret manager y rotados automáticamente.

## Tareas
1. **Cilium FQDN policies:** crea `network-policies/base-deny-all.yaml` (default deny) y
   `network-policies/<rol>-egress.yaml` por rol, con el allowlist del TO-BE **más** el
   endpoint de Claude elegido en la decisión #1. Inter-pod bloqueado (dev ↮ qa).
2. **External Secrets Operator:** crea `secrets/secret-store.yaml` y `ExternalSecret` por
   rol/usuario que materialicen: token GitHub (GitHub App, 1h TTL), token Jira/Sonar,
   y `ANTHROPIC_API_KEY` (según decisión #2).
3. **Inyección en el pod:** en `templates/k8s/main.tf`, reemplaza el paso de la API key por
   `value_from.secret_key_ref` al secret de ESO. Los tokens MCP → env del pod → config MCP.
4. **Jira OAuth 3LO:** implementa el flujo de `docs/TO-BE/10` (1 click por usuario, refresh
   automático) para el MCP de Atlassian.
5. **Auditoría del egress:** añade un test/comprobación de que un rol NO alcanza un FQDN de
   otro rol (p. ej. QA no llega a npm).
6. Actualiza `docs/MVP.md`: Nivel 5 → ✅.

## Archivos a crear/modificar
- `network-policies/base-deny-all.yaml`, `network-policies/<rol>-egress.yaml`.
- `secrets/secret-store.yaml`, `secrets/externalsecret-<rol>.yaml`.
- `templates/k8s/main.tf` — API key y tokens desde `secret_key_ref`.
- `docs/decisiones-egress-auth.md` — registro de las decisiones #1 y #2.
- `docs/MVP.md` — marcar Nivel 5.

## Criterios de aceptación
- [ ] Egress default-deny activo; sin política explícita no hay salida.
- [ ] Cada rol resuelve **solo** sus FQDN (incluye el endpoint de Claude).
- [ ] Inter-pod entre roles bloqueado.
- [ ] `ANTHROPIC_API_KEY` y tokens MCP provienen de ESO, no de `--var` ni del repo.
- [ ] Rotación automática verificada (el token GitHub caduca y se renueva).
- [ ] Jira OAuth 3LO funciona con refresh automático.
- [ ] Ningún secreto real aparece en Terraform, ConfigMaps ni logs.

## Validación
```bash
kubectl get cnp -n coder-workspaces
kubectl exec -n coder-workspaces <pod-dev> -- curl -sS https://registry.npmjs.org  # OK dev
kubectl exec -n coder-workspaces <pod-qa>  -- curl -sS https://registry.npmjs.org  # DENIED qa
kubectl get externalsecret -n coder-workspaces
```

## Notas
- Fail-closed en todo: ante duda, bloquea y escala. Un egress leak es incidente.
- No mezcles este nivel con operación (Nivel 6); aquí solo isolation + secretos.
