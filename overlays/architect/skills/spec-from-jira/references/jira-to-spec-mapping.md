# Jira to Spec Mapping

Cómo traducir campos de JIRA a secciones del spec.

## Mapping de campos

| Campo Jira | Sección del Spec | Notas |
|------------|------------------|-------|
| Summary | `# Spec NN — [Summary]` | Título del spec |
| Description | Input para `## Objetivo` | Resumir en 1-2 oraciones |
| Acceptance Criteria | `Comportamiento` + `Modelo de datos` + `API` | Cada criterio = un comportamiento a implementar |
| Labels / Components | Determina el concepto técnico | backend, database, auth, payments → qué servicio |
| Security/PII flags | `Seguridad y cumplimiento` | Dispara la sección obligatoria de controles |
| Story Points | NO se usa | El spec no estima |
| Priority | NO se usa | El spec describe, no prioriza |

## De AC a spec (ejemplo)

```
AC Jira:  "El cliente transfiere a otra cuenta y recibe confirmación"

→ Objetivo:   Permitir transferencias entre cuentas con confirmación.
→ Modelo:     tabla transfers (from_acc, to_acc, amount DECIMAL, ...)
→ API:        POST /transfers { from, to, amount } → 201
→ Restr.:     amount > 0, límite diario, idempotency-key obligatoria
→ Seguridad:  authz por ownership de la cuenta origen; monto con decimal, no float; auditoría de la operación
→ Edge:       destino inexistente → 404, límite excedido → 422, replay → idempotente
```

## Señales de que la historia necesita split (`TOO_LARGE`)

- 5+ acceptance criteria que tocan servicios distintos.
- Labels que mezclan backend + frontend + infra.
- La description dice "y también necesitamos…".
- Tiene sub-tasks en JIRA (cada sub-task = spec potencial).

## Cuándo pedir clarificación al PM (`NEEDS_CLARIFICATION`)

- AC vagos: "should handle errors appropriately" (¿cuáles errores, con qué status?).
- No hay criterios de aceptación (solo título y descripción difusa).
- Referencia a un sistema no documentado en CLAUDE.md.
- Requisitos contradictorios entre criterios.
- Toca datos sensibles pero no define authz / retención / cifrado.
