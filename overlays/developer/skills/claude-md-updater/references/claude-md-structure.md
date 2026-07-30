# CLAUDE.md Structure

Estructura canónica de un CLAUDE.md de proyecto. Las secciones pueden variar,
pero esta es la base recomendada.

---

markdown
# CLAUDE.md

## Project structure

[Directorios principales y su propósito]

## Commands

[Comandos para dev, test, build, deploy, format, typegen]

### From the root
- `npm run dev` — ...
- `npm test` — ...

### Backend (`cd backend`)
- `npm run dev` — ...
- `npm test` — ...

## Architecture

**Entry**: [punto de entrada principal]

**Routers/Routes**:
- `path/to/route.ts` — [endpoints que expone]

**Service layer**:
- `path/to/service.ts` — [qué hace, qué binding usa]

**Middleware**:
- `path/to/middleware.ts` — [qué aplica y dónde]

## Bindings & Infrastructure

[Lista de todos los bindings con nombre, tipo y binding name]

| Binding | Type | Wrangler key | Purpose |
|---------|------|-------------|---------|
| DB | D1 | `d1_databases` | Persistencia principal |
| BUCKET | R2 | `r2_buckets` | File storage |

## Key constraints

[Gotchas, limitaciones, decisions no obvias. Formato bullet:]

- constraint 1: explicación
- constraint 2: explicación

---

## Reglas de actualización

1. **Agregar en la sección correcta** — no crear secciones duplicadas.
2. **Mantener tablas** — si ya hay una tabla de bindings, agregar filas.
3. **Constraints al final** — nuevos gotchas van en "Key constraints".
4. **No reescribir** — agregar info, no reformatear todo el doc.