# Runbook — levantar y recuperar el entorno local

> Guía operativa para **cualquier colaborador** que retome el entorno local de
> `coder-platform`.
>
> **Desde Nivel 6 (jul-2026) el entorno se recupera solo tras un reboot** — ver
> [Persistencia automática](#persistencia-automática-nivel-6). Los "2 pasos manuales"
> de más abajo quedan como **fallback** (si el servicio no arrancó o quieres hacerlo a mano).

## Componentes y dónde viven

| Componente | Ubicación / detalle |
|---|---|
| Binario Coder | `~/.local/bin/coder` (standalone, sin sudo), v2.35.1 |
| Base de datos | PostgreSQL **embebido** en `~/.config/coderv2/postgres` (persiste) |
| Config/sesión CLI | `~/.config/coderv2/{url,session}` |
| **Env del server** | `~/.config/coderv2/server.env` (perm `600`, **NO va a git**) — binds + OAuth GitHub |
| Datos del workspace | `docker_volume` `coder-<id>-home` (persiste el `/home/coder`) |
| Templates | `templates/mvp-embedded/` (el que usamos) y `templates/mvp-docker/` (bloqueado) |

## Qué persiste y qué no tras un reboot

- ✅ **Persisten:** templates, workspaces, usuarios (Postgres) y el `/home/coder` (volumen Docker).
- ❌ **NO persisten:** el proceso `coder server` (se lanza a mano) y los contenedores de
  workspace (quedan `Exited 255`, sin restart policy). Los paquetes apt del contenedor
  (ttyd, node) tampoco — el `startup_script` los reinstala en cada arranque (idempotente).

## Persistencia automática (Nivel 6)

Tras un reboot **todo vuelve solo**, sin intervención:

| Pieza | Cómo persiste |
|---|---|
| **Datos** (`/home/coder`, código, config) | Volumen Docker named `coder-<id>-home` (siempre persistió). |
| **`coder server`** | Servicio **`systemd --user`** `coder.service` (`enabled` + **linger** activo → arranca al bootear sin login). Lanza el wrapper `~/.config/coderv2/start-server.sh`, que hace `source server.env` (binds `0.0.0.0:3000` + OAuth). Postgres embebido corre como hijo del servicio. |
| **Contenedores de workspace** | `restart = "unless-stopped"` en el template → Docker revive el **mismo** contenedor al bootear. Al *reiniciarse* (no recrearse) los paquetes apt persisten → el `startup_script` idempotente relanza code-server/ttyd en **segundos**. Respeta un `coder stop` manual. |
| **Autostop** | Desactivado (`coder templates edit mvp-embedded --default-ttl 0h`) → Coder no apaga el workspace por inactividad. |

**Gestión del servicio:**

```bash
systemctl --user status coder.service     # estado
systemctl --user restart coder.service    # reiniciar
journalctl --user -u coder.service -f     # logs en vivo
```

> **GITHUB_TOKEN (resolve-role.sh):** el wrapper NO usa `gh auth token` (en el boot
> temprano el keyring puede no estar). Para que la **resolución de rol en builds nuevos**
> sobreviva reboots, añade un **PAT** (`read:org`) a `server.env`:
> `echo 'export GITHUB_TOKEN=github_pat_xxx' >> ~/.config/coderv2/server.env && systemctl --user restart coder.service`.
> Sin él, el server arranca igual y los workspaces YA creados reviven bien; solo un
> **nuevo** build resolvería el rol a `unknown` hasta que el token esté presente.

## Recuperación manual tras reboot (fallback — 2 pasos)

### 1. Levantar el server

```bash
source ~/.config/coderv2/server.env      # binds + OAuth GitHub
export GITHUB_TOKEN="$(gh auth token)"    # para que resolve-role.sh consulte teams
nohup coder server > /tmp/coder-server.log 2>&1 &

# esperar a que abra el puerto
until ss -ltn | grep -q ':3000'; do sleep 1; done
```

> **Crítico:** el bind debe ser `0.0.0.0:3000` (está en `server.env` como
> `CODER_HTTP_ADDRESS`). Si el server escucha en loopback, el agente que corre *dentro*
> del contenedor no alcanza el host (`host.docker.internal`) y el workspace queda
> `HEALTHY=false`.

### 2. Revivir los workspaces

El contenedor murió con el reboot; hay que reconstruirlo para que el agente reconecte:

```bash
coder update dev1        # recrea el contenedor sobre la última versión del template
coder list               # esperar HEALTHY=true
```

Verificar servicios dentro del contenedor (el startup tarda ~1–2 min):

```bash
docker exec coder-admin-dev1 bash -lc \
  'curl -sf -o /dev/null -w "vscode:%{http_code} " http://localhost:8080/healthz;
   curl -sf -o /dev/null -w "claude-term:%{http_code}\n" http://localhost:7681'
# esperado: vscode:200 claude-term:200
```

## Cambio de rol y offboarding

> El rol se estampa en **tiempo de build** (`resolve-role.sh` → label `coder.com/role` +
> overlay). Un workspace ya creado **conserva su rol** aunque cambies la membresía de teams
> en GitHub; un reboot (Nivel 6, `unless-stopped`) revive el **mismo** contenedor y **tampoco**
> re-resuelve. Ver `docs/TO-BE/00-desiciones.md` → **Decisión #18**.

Aplicar los cambios de forma **asimétrica** (grant puede esperar; deny es inmediato):

### Promoción (más permisos: p.ej. qa → architect)

Bajo riesgo — basta con reconstruir para re-resolver el rol y re-aplicar el overlay:

```bash
coder restart <owner>/<ws> --yes    # recrea el contenedor → re-resuelve rol + overlay
```

> `restart` recrea el contenedor y re-corre el provisioner (a diferencia de un reboot, que
> solo revive el mismo contenedor). Los **datos** (`/home/coder`) persisten en el volumen.

### Degradación / offboarding (menos permisos o salida de la org)

**Alto riesgo — hazlo YA, no esperes al próximo rebuild.** El usuario conserva los permisos
del rol viejo (skills, MCP, persona) hasta que el contenedor muera:

```bash
# Degradación (architect → qa): primero quítalo del team en GitHub, luego reconstruye
coder restart <owner>/<ws> --yes    # re-resuelve al rol menos permisivo (least-privilege)

# Offboarding (sale de la org): NO relabel — termina el workspace (fail-closed)
coder stop   <owner>/<ws> --yes     # lo apaga de inmediato
coder delete <owner>/<ws> --yes     # elimina workspace + contenedor (destruye datos)
```

> Regla: **quitar acceso se resuelve terminando el workspace, no reetiquetándolo.** Confía en
> `stop`/`delete`, no en que el label caduque solo. Verificar que quedó abajo:
>
> ```bash
> coder list                          # el ws no debe aparecer Running
> docker ps --filter name=coder-<owner>-<ws>   # sin contenedor vivo
> ```

### Automatización (reconciliador, opcional)

En vez de hacerlo a mano, `scripts/reconcile-roles.sh` aplica la política #18 de forma
periódica (bucle de reconciliación): compara el rol **estampado** en cada contenedor vivo
contra la membresía **actual** en GitHub y actúa sobre la diferencia. No necesita endpoint
público (no es un webhook) — reutiliza `gh-app-token.sh` + `resolve-role.sh`.

**Modo DRY-RUN por defecto**: solo loguea lo que haría, no ejecuta nada. Probar a mano:

```bash
bash scripts/reconcile-roles.sh          # ensayo en seco (default)
# Para actuar de verdad (¡revisa el dry-run antes!):
DRY_RUN=0 bash scripts/reconcile-roles.sh
```

Instalar como timer `systemd --user` (corre cada 15 min; sigue en dry-run hasta que
edites `Environment=DRY_RUN=0` en el `.service`):

```bash
cp deploy/systemd/reconcile-roles.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now reconcile-roles.timer
journalctl --user -u reconcile-roles.service      # ver decisiones
```

**Fail-safes:** aborta si no puede mintear el token de la App (sin token no actúa); solo
hace offboarding ante un **404 explícito** de membresía; salta workspaces sin contenedor
vivo o con membresía indeterminada.

> ⚠️ **GOTCHA — usuarios locales.** Los owners que NO son identidades GitHub (p.ej. `admin`
> del `--first-user`, dueño de `dev1`) dan 404 en la org → el reconciliador los tomaría como
> "offboarding" y **borraría su workspace**. Por eso están en la lista de exclusión
> `RECONCILE_IGNORE_OWNERS` (default `admin`). Añade ahí cualquier otro usuario local.
> Esto lo destapó el primer dry-run — corre siempre en seco antes de `DRY_RUN=0`.

En **producción** esto se sustituye por un webhook de la org GitHub → API de Coder
(removido de la org → `stop`+`delete`; cambio de team → `restart`) para reacción instantánea
en vez de la latencia del timer. Ver Decisión #18.

## Acceso

- Dashboard: <http://localhost:3000>
- VS Code (workspace `dev1`): `http://localhost:3000/@<owner>/dev1.main/apps/vscode/`
- Claude CLI (ttyd):          `http://localhost:3000/@<owner>/dev1.main/apps/claude/`

## Parar el server (con cuidado)

`pkill -f "coder server"` **también mata el shell que ejecuta el comando** si su línea
contiene ese texto. Usa el PID:

```bash
kill "$(pgrep -f 'coder server' | head -1)"
```

## Notas de versiones (bloqueo de Terraform)

El provisioner usa el `terraform` del **PATH** = **1.5.7** (linuxbrew). Los módulos del
registry (`code-server`, `claude-code`) exigen **≥ 1.9**, por eso usamos
`templates/mvp-embedded/` que **no** usa módulos (instala todo en el `startup_script`).
Alternativa si se quieren los módulos: **OpenTofu 1.9.1** (`tofu`, ya instalado) o instalar
Terraform 1.9–1.11 y ponerlo primero en el PATH del proceso `coder server`.
