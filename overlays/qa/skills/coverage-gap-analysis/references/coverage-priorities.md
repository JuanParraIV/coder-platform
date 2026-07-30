# Coverage Priorities

Marco para priorizar gaps de cobertura por **criticidad de negocio**, no por % faltante.
Calidad sobre vanity metrics.

## Framework de prioridad

| Prioridad | Criterio | Ejemplos (banking) | Threshold |
|-----------|----------|--------------------|-----------|
| **P0 — Crítico** | Auth, dinero, integridad de datos, PAN/PII | Login, validación de token, transferencias, escritura de saldo | 95% line+branch |
| **P1 — Alto** | Lógica de negocio core | CRUD de cuentas, máquinas de estado, workflows de aprobación | 90% |
| **P2 — Medio** | Puntos de integración | Rutas API, middleware, llamadas a servicios | 80% |
| **P3 — Bajo** | Utilidades, helpers | Formatters, validadores, funciones puras | 80% |
| **Skip** | No testeable | Type defs, config, código generado, migraciones | — |

## Excluir del análisis

```
*.d.ts / *.pyi            # type definitions
**/node_modules/**
**/generated/**           # código autogenerado
*.config.*                # config de build
migrations/*.sql          # declarativo
```

## Reglas de threshold

- Archivos nuevos: **80%** mínimo (line **y** branch).
- Archivos modificados: **no pueden bajar** la cobertura existente.
- Paths P0 (auth/dinero/PAN): **95%** mínimo.
- Si un path no se puede cubrir sin tests triviales → dejarlo sin cubrir y **explicar por qué** en el reporte.

## Formato del reporte

```
Cobertura global: XX% (antes) → YY% (después)

| Archivo            | Actual | Target | Prioridad | Funciones/ramas a cubrir      |
|--------------------|--------|--------|-----------|-------------------------------|
| auth/token.py      | 62%    | 95%    | P0        | verify_signature(), expired() |
| accounts/crud.py   | 74%    | 90%    | P1        | update_balance() rama negativa|

Plan de tests (ordenado por prioridad): 1) … 2) …
Gaps residuales (con motivo): …
```

## Anti-patrones

- ❌ Perseguir 100% con tests triviales/tautológicos.
- ❌ Snapshots masivos para inflar el número.
- ❌ Modificar el source para "facilitar" la cobertura.
- ❌ Reportar cobertura sin haber ejecutado la suite.
