# Prompt — Nivel 6: Operación Day-2

## Rol
Eres un ingeniero de plataforma/SRE. Tu objetivo es hacer la plataforma **operable en
producción**: onboarding automático, observabilidad, CI/CD y control de costos.

## Contexto
- Nivel 5 completado: isolation + secretos gobernados sobre K8s.
- Referencias: `docs/TO-BE/07-observabilidad-audit.md`, `08-deployment-operacion.md`,
  y la sección "CI/CD" y "Administración" del `README.md`.
- Con esto se alcanza el **TO-BE completo**.

## Objetivo
Que agregar un operador a un GitHub Team baste para provisionar su entorno, con
dashboards de adopción/costo/gobernanza y despliegues automáticos.

## Tareas
1. **Auto-create:** implementa el `deploy/cronjob-auto-create.yaml` (+ `onboard-controller`)
   que detecta usuarios sin workspace y lo crea; y el `onboard-controller` que genera
   tokens/secrets per-user (encadena con ESO del Nivel 5).
2. **Bootstrap:** crea `deploy/bootstrap.sh` que orquesta namespaces, secrets, Helm de
   Coder, ConfigMaps de overlays, network policies y push del template (idempotente).
3. **Helm values:** crea `helm/values.yaml` (dominio, wildcard, OAuth, DB) parametrizado.
4. **Observabilidad:** `observability/prometheus-rules.yaml`,
   `observability/alerts/cost-budget.yaml`, `observability/dashboards/adoption.json`
   (KPIs: adopción, tokens/usuario/día, violaciones de gobernanza → 0, costo/usuario/día).
5. **CI/CD:** `.github/workflows/build-workspace-image.yml` (build+push imagen) y
   `push-template.yml` (push template + update ConfigMaps al merge en main).
6. **Auto-stop y backups:** auto-stop de workspaces idle (2h), backup diario de PostgreSQL.
7. **Tests:** `tests/test-full-integration.sh` + tests de rol, overlay y network policy.
8. Actualiza `docs/MVP.md`: Nivel 6 → ✅ y marca el TO-BE como alcanzado.

## Archivos a crear/modificar
- `deploy/bootstrap.sh`, `deploy/cronjob-auto-create.yaml`, `deploy/cronjob-onboard-controller.yaml`.
- `helm/values.yaml`.
- `observability/` (rules, alerts, dashboards).
- `.github/workflows/build-workspace-image.yml`, `.github/workflows/push-template.yml`.
- `tests/` (integración + unitarios de plataforma).
- `docs/MVP.md` — marcar Nivel 6 y TO-BE completo.

## Criterios de aceptación
- [ ] Agregar un usuario al GitHub Team → workspace + tokens creados sin admin.
- [ ] `bootstrap.sh` reconstruye el entorno desde cero de forma idempotente.
- [ ] Dashboards de Grafana muestran adopción, tokens y costo por usuario.
- [ ] Alertas de presupuesto y de violaciones de gobernanza activas.
- [ ] CI publica la imagen y CD sube el template al merge en main.
- [ ] Workspaces idle se detienen a las 2h; backup de DB diario verificado.
- [ ] `tests/test-full-integration.sh` pasa en verde.

## Validación
```bash
bash tests/test-full-integration.sh
kubectl get cronjob -n coder
# Alta de un usuario de prueba en el Team → esperar ~1 min → coder list muestra su workspace
```

## Notas
- Este nivel cierra el TO-BE: revisa `docs/TO-BE/SPEC-coder-claude-rbac-platform.md` §8 y
  §10 (rollout y riesgos) y confirma que cada mitigación tiene su control implementado.
- Revisa que ningún workflow imprima secretos y que el audit log de Coder esté activo.
