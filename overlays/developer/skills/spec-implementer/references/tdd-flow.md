# TDD Flow

Flujo obligatorio para implementar cada archivo del spec. Multi-lenguaje: los comandos
de ejemplo se muestran para varios stacks; usa el del proyecto.

## Ciclo por archivo

```
┌─────────────────────────────────────────┐
│  1. WRITE FAILING TEST                   │
│     - Test que verifica el comportamiento│
│     - Usa el framework del proyecto      │
│     - Importa lo que aún no existe       │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  2. RUN TEST — MUST FAIL                 │
│     - Confirma: "not defined"/"not found"│
│     - Si pasa → el test no testea nada   │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  3. IMPLEMENT MINIMAL CODE               │
│     - Solo lo necesario para pasar       │
│     - Seguir el código del spec          │
│     - No anticipar features futuras      │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  4. RUN TEST — MUST PASS                 │
│     - Confirma: test verde               │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  5. RUN FULL SUITE — NO REGRESSIONS      │
│     - Si algo falla → fix before commit  │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  6. COMMIT                               │
│     - "feat: add [component]"            │
│     - One logical unit per commit        │
└─────────────────────────────────────────┘
```

## Manejo de errores y seguridad (banking)

- Manejo de error en toda llamada externa (DB, HTTP, cola, FS).
- Dinero con decimal de precisión fija, nunca `float`.
- Sin secretos/credenciales en código; sin valores hardcodeados.

## Cuándo NO escribir test primero

| Caso | Acción |
|------|--------|
| Config (`package.json`, `pom.xml`, `pyproject.toml`, `wrangler.jsonc`) | Crear/editar → verificar build → commit |
| Migraciones SQL | Solo crearlas, no ejecutar contra ningún entorno |
| Regeneración de tipos/stubs | Regenerar → verificar build → commit |

## Comandos por stack

```bash
# Node/TS
npm test                    # suite completa
npm test -- -t "nombre"     # test específico
npm run typecheck && npm run lint

# Python
pytest                      # suite completa
pytest -k "nombre"          # test específico
mypy . && ruff check .

# Java (Maven)
mvn test                    # suite completa
mvn -Dtest=ClassName#method test

# Go
go test ./...               # suite completa
go test -run TestName ./pkg
```
