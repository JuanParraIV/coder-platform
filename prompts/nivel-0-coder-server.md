# Prompt — Nivel 0: Coder server + workspace Docker de arranque

## Rol
Eres un ingeniero de plataforma. Tu objetivo es dejar **Coder OSS corriendo en local**
y provisionar un primer workspace como contenedor Docker, sin Kubernetes.

## Contexto
- Repo: `coder-platform/`. Diseño objetivo en `docs/TO-BE/`; escalera en `docs/MVP.md`.
- Este es el nivel más básico: solo validar que Coder instala, arranca y provisiona.
- Docker debe estar instalado y corriendo en la máquina.

## Objetivo
Tener Coder server accesible en `http://localhost:3000`, con un usuario admin y un
workspace de la plantilla Docker de arranque en estado *Running*.

## Tareas
1. Verifica Docker: `docker ps` responde sin error. Si no, instala Docker Engine y añade
   tu usuario al grupo `docker`.
2. Instala Coder: `curl -L https://coder.com/install.sh | sh`.
3. Arranca el server en background: `coder server` (deja el proceso vivo; primer arranque
   imprime la URL local).
4. Abre `http://localhost:3000`, crea la cuenta admin (o GitHub) y completa el setup.
5. En la UI: **Templates → New template → Docker** (plantilla oficial de arranque).
   Nómbrala `starter-docker` y créala.
6. **Create Workspace** desde esa plantilla; nómbralo `smoke-test`.
7. Documenta en `docs/MVP.md` el Nivel 0 como ✅ y anota cualquier ajuste local
   (p. ej. `DOCKER_HOST` en macOS/Colima).

## Archivos a crear/modificar
- `docs/MVP.md` — marcar Nivel 0 como completado.
- (Opcional) `docs/notas-entorno-local.md` — prerequisitos específicos de tu máquina.

## Criterios de aceptación
- [ ] `coder server` responde en `http://localhost:3000`.
- [ ] Existe un usuario admin.
- [ ] El workspace `smoke-test` está en *Running* y abre el Terminal web.
- [ ] `coder templates list` muestra `starter-docker`.

## Validación
```bash
coder templates list
coder list                 # muestra el workspace smoke-test = Running
docker ps | grep coder     # el contenedor del workspace existe
```

## Notas
- No toques RBAC, overlays ni módulos aquí. Eso es Nivel 1+.
- Si `coder server` no debe correr en foreground, usa `coder server &` o un servicio
  systemd para desarrollo.
