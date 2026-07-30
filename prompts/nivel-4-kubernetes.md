# Prompt — Nivel 4: Salto a Kubernetes

## Rol
Eres un ingeniero de plataforma. Tu objetivo es migrar el workspace de **contenedor Docker
a pod de Kubernetes**, conservando el agente, los módulos y la resolución de rol.

## Contexto
- Nivel 3 completado: VS Code + Claude + overlay + RBAC funcionan sobre Docker.
- Cambio estructural acotado: `docker_container`/`docker_volume` → `kubernetes_pod`/PVC.
  El `coder_agent`, los módulos `code-server`/`claude-code` y `resolve-role.sh` **no
  cambian**.
- Referencias: `docs/TO-BE/03-template-terraform.md` (HCL K8s) y
  `docs/TO-BE/06-imagen-base-docker.md` (imagen base).

## Objetivo
Provisionar el mismo workspace del Nivel 3 como pod en el clúster, con imagen base propia y
overlays vía ConfigMap.

## Tareas
1. **Imagen base:** crea `docker/workspace/Dockerfile` a partir de
   `docs/TO-BE/06-imagen-base-docker.md`, con las correcciones ya identificadas:
   instala `claude-code`, `code-server` y `ttyd` **en el stage final** (evita el
   cross-stage copy frágil); usuario no-root `coder` (UID 1000). Publica a
   `ghcr.io/<org>/coder-workspace:latest` (CI en Nivel 6).
2. **Template K8s:** crea `templates/k8s/main.tf` copiando `templates/mvp-docker/main.tf` y
   sustituyendo:
   - `docker_container` → `kubernetes_pod` (namespace `coder-workspaces`, labels
     `coder.com/role` y `coder.com/owner`, `resources` requests/limits).
   - `docker_volume` → `persistent_volume_claim` para `/home/coder`.
   - imagen → la de GHCR.
   - overlay → `config_map` `overlay-${local.role}` montado y copiado a `~/.claude`.
3. Conserva `variable "anthropic_api_key"`, los dos módulos y `data "external" user_role`.
4. Sube el template a Coder (`coder templates push k8s -d templates/k8s`) y crea un
   workspace de prueba.
5. Actualiza `docs/MVP.md`: Nivel 4 → ✅.

## Archivos a crear/modificar
- `docker/workspace/Dockerfile` — imagen base (correcciones aplicadas).
- `docker/workspace/scripts/startup.sh` — arranque (code-server + ttyd/claude + overlay).
- `templates/k8s/main.tf`, `variables.tf`, `outputs.tf` — template Kubernetes.
- `docs/MVP.md` — marcar Nivel 4.

## Criterios de aceptación
- [ ] La imagen se construye y publica a GHCR; `claude`, `code-server` y `git` presentes.
- [ ] `coder templates push k8s` OK; workspace en *Running* como pod.
- [ ] El pod lleva labels `coder.com/role` y `coder.com/owner`.
- [ ] VS Code y Claude funcionan igual que en el Nivel 3.
- [ ] El home persiste vía PVC entre stop/start.

## Validación
```bash
kubectl get pods -n coder-workspaces --show-labels
kubectl exec -n coder-workspaces <pod> -- which claude code-server
coder templates list | grep k8s
```

## Notas
- Aún **sin** NetworkPolicy ni ESO (eso es Nivel 5): en este nivel el pod puede tener
  egress abierto para validar el salto.
- Mantén `templates/mvp-docker/` como camino de desarrollo local.
