# Spec Template — Contrato de Comportamiento (banking)

Estructura canónica. Un spec es un **contrato** que sirve a la vez para:
- **Architect**: documenta las decisiones técnicas.
- **QA**: extrae los escenarios de prueba (`.feature` BDD).
- **Developer**: implementa el código.

Todas las secciones son obligatorias. La de **Seguridad y cumplimiento** es obligatoria
cuando el spec toca datos financieros, PII o PAN.

---

```markdown
# Spec NN — [Nombre de la feature]   (Jira: PROJ-XXX)

## Objetivo
[1-2 oraciones: QUÉ puede hacer el usuario/sistema después de esto que no podía antes.
El resultado visible, no el cómo.]

## Comportamiento esperado
[Perspectiva del usuario/consumidor de la API, formato "Cuando X → entonces Y".
Este es el input principal para que QA genere el .feature.]

| Cuando... | Entonces... | Status |
|-----------|-------------|--------|
| Cliente envía transferencia válida | Se registra y confirma | 201 |
| Monto excede el límite diario | Rechazo por política | 422 |
| Cuenta destino no existe | Error de validación | 404 |

> **Regla de negocio**: [reglas relevantes explícitas]

## Modelo de datos
[Schema real. Solo si introduce/modifica datos persistentes. Marca columnas sensibles.]

## Contratos de API
[Endpoints con request/response exactos: el contrato que Dev implementa y QA verifica.]

### `POST /transfers`
Request / Response (2xx) / tabla de errores (status, cuándo, body).

## Restricciones y límites
[Lo que el sistema NO debe hacer: payload máx, rate limit, validaciones, normalización.
Input para boundaries de QA y validaciones de Dev.]

## Integraciones
| Servicio | Binding/Config | Uso | Fallback si falla |
|----------|----------------|-----|-------------------|

## Seguridad y cumplimiento   ← obligatoria si toca datos financieros/PII/PAN
- AuthN/AuthZ requeridos por endpoint (rol, ownership).
- Datos sensibles: PAN enmascarado/tokenizado, CVV nunca se almacena, cifrado en reposo/tránsito.
- Auditoría: qué eventos dejan traza; retención de datos.
- Controles regulatorios que aplican (PCI-DSS / SOX / GDPR / DORA).

## Archivos a crear / modificar
[Paths exactos. Solo Dev consume esta sección directamente.]

## Conceptos destacados
[El POR QUÉ de las decisiones. Máx 5 bullets.]

## Criterios de aceptación (checklist)
[Resumen verificable. QA valida cada punto, PM acepta la historia.]
- [ ] ...

## Al finalizar
Actualizar CLAUDE.md: nuevos bindings/servicios, endpoints, patterns, constraints.
```

---

## Cómo cada rol consume el spec

| Sección | Architect | QA | Developer |
|---------|:---------:|:--:|:---------:|
| Objetivo | ✍️ escribe | 📖 contexto | 📖 contexto |
| Comportamiento esperado | ✍️ escribe | 🎯 **genera .feature** | 📖 qué testear |
| Modelo de datos | ✍️ escribe | 📖 valida | 🎯 **crea schema** |
| Contratos de API | ✍️ escribe | 🎯 **valida responses** | 🎯 **implementa endpoints** |
| Restricciones | ✍️ escribe | 🎯 **boundary tests** | 🎯 **validaciones** |
| Integraciones | ✍️ escribe | 📖 mock setup | 🎯 **conecta servicios** |
| Seguridad y cumplimiento | ✍️ escribe | 🎯 **tests negativos/authz** | 🎯 **controles** |
| Archivos | ✍️ escribe | ❌ | 🎯 **crea/modifica** |
| Criterios de aceptación | ✍️ escribe | 🎯 **valida cada uno** | 📖 sabe cuándo terminó |
| Al finalizar | ✍️ escribe | ❌ | 🎯 **actualiza CLAUDE.md** |
