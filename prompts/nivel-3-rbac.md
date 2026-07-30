# Prompt — Nivel 3: RBAC (GitHub OAuth + rol por Team)

## Rol
Eres un ingeniero de plataforma. Tu objetivo es que el **rol se resuelva automáticamente**
por membresía de GitHub Team, sin selección manual.

## Contexto
- Nivel 2 completado: overlay de rol montado, pero el rol se elige a mano.
- Diseño de referencia: `docs/TO-BE/02-rbac-mapping-roles.md` y `docs/TO-BE/01-arquitectura-general.md`.
- Mapping objetivo: `platform-developers → developer`, `qa-engineers → qa`,
  `architects → architect`. Prioridad si multi-team (least-privilege, gana el
  MENOS permisivo): **qa < developer < architect**.

## Objetivo
Que al crear un workspace, Coder determine el rol del usuario por sus GitHub Teams y monte
el overlay correcto automáticamente.

## Tareas
1. **GitHub OAuth en Coder:** crea la OAuth App (callback
   `.../api/v2/users/oidc/callback`), configura `CODER_OAUTH2_GITHUB_*` en el server y
   habilita login con GitHub. Documenta las variables (sin secretos en el repo).
2. **Script de resolución:** crea `templates/mvp-docker/scripts/resolve-role.sh` que
   recibe `{github_username, github_org}` por stdin (JSON), consulta los Teams vía `gh`/API
   y devuelve `{"role":"developer|qa|architect"}` aplicando la prioridad. Fail-closed: si
   no hay team válido → rol mínimo o error claro (`role: unknown`).
3. **Terraform:** añade `data "external" "user_role"` que ejecute el script con
   `github_username = data.coder_workspace_owner.me.name`. Usa `local.role` para elegir el
   overlay y la label `coder.com/role` del contenedor.
4. Sustituye el `coder_parameter "role"` manual del Nivel 2 por `local.role`.
5. Prueba con dos usuarios de Teams distintos (o mockea el script) y confirma overlays
   distintos.
6. Actualiza `docs/MVP.md`: Nivel 3 → ✅. Actualiza `docs/TO-BE/TODO.md` si aplica.

## Archivos a crear/modificar
- `templates/mvp-docker/scripts/resolve-role.sh` — resolución Team → rol (con prioridad).
- `templates/mvp-docker/main.tf` — `data "external"` + `local.role` + label.
- `docs/rbac-setup.md` — pasos de la OAuth App y variables del server.
- `docs/MVP.md` — marcar Nivel 3.

## Criterios de aceptación
- [ ] Login con GitHub funciona en Coder.
- [ ] Un usuario de `platform-developers` obtiene overlay `developer` sin intervención.
- [ ] Un usuario de `qa-engineers` obtiene overlay `qa`.
- [ ] Usuario multi-team → rol MENOS permisivo (least-privilege; owner-en-todos → qa).
- [ ] Usuario sin team válido → fail-closed (`unknown`, no un rol al azar).
- [ ] El contenedor lleva la label `coder.com/role=<rol>`.

## Validación
```bash
# Prueba unitaria del script:
echo '{"github_username":"alice","github_org":"qintess"}' \
  | bash templates/mvp-docker/scripts/resolve-role.sh
# → {"role":"developer"}   (según los teams de alice)

coder show <workspace>      # metadata role = el esperado
docker inspect <container> --format '{{ index .Config.Labels "coder.com/role"}}'
```

## Notas
- Este nivel **no** requiere Kubernetes todavía.
- No hardcodees tokens de `gh` en el script: usa el token del entorno del provisioner.
