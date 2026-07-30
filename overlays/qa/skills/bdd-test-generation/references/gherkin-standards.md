# Gherkin Standards (Banking-grade)

Referencia de sintaxis, naming y calidad para los `.feature`. El `.feature` es el
contrato inmutable QA↔Dev: describe el **qué**, nunca el **cómo**.

## Naming

- Archivo: `<JIRA-KEY>-<slug>.feature` (ej: `PROJ-123-user-registration.feature`).
- `Feature:` = resumen de la historia. Tag de la JIRA key a nivel Feature: `@PROJ-123`.
- Nombre de `Scenario:` = el **resultado** esperado, no la acción ("Registro rechazado por email duplicado", no "El usuario envía el formulario").
- Un `Feature` por historia, un archivo por historia, 1:1 escenario↔AC.

## Estructura canónica

```gherkin
@PROJ-123
Feature: Registro de cliente
  As a cliente nuevo
  I want to registrarme con mi correo
  So that pueda operar en la banca digital

  Background:
    Given el servicio de registro está disponible

  @positive @smoke
  Scenario: Registro exitoso con email válido
    Given no existe cuenta para "test@example.com"
    When el cliente envía el email "test@example.com"
    Then el sistema responde 201
    And se envía un correo de confirmación

  @negative
  Scenario: Registro rechazado por email duplicado
    Given ya existe una cuenta para "existing@example.com"
    When el cliente envía el email "existing@example.com"
    Then el sistema responde 409
    And el mensaje de error dice "Email already registered"

  @edge-case
  Scenario Outline: Registro rechazado por email inválido
    When el cliente envía el email "<invalid_email>"
    Then el sistema responde 400

    Examples:
      | invalid_email    |
      | not-an-email     |
      | @missing-local   |
      | missing@.domain  |
      |                  |
```

## Reglas

1. Un `Feature` por archivo, un archivo por historia.
2. Escenarios **independientes**: sin estado compartido, sin dependencia de orden.
3. `Scenario Outline` + `Examples` para casos parametrizados; no copiar-pegar escenarios.
4. `Background` solo para precondiciones **realmente** compartidas (raro).
5. Steps en presente declarativo ("el cliente envía", no "el cliente hizo click en").
6. **Sin mecánica de UI**: nada de selectores, URLs, SQL, sleeps ni "calls API".
7. Tags: `@positive`, `@negative`, `@edge-case`, `@smoke`, más la JIRA key.

## Cobertura mínima por AC

| Tipo | Debe existir |
|------|--------------|
| Happy path | ≥1 escenario positivo por AC |
| Error path | duplicado, no autorizado, no encontrado, input inválido |
| Boundary | 0, 1, máximo, máximo+1, vacío |
| Seguridad/negocio | límites de monto, autorización, idempotencia (si el AC los menciona) |

Si la historia solo trae happy path → generar lo que se pueda y **marcar el gap en JIRA**
("Story needs refinement"), no inventar escenarios.

## Datos de prueba (banking)

- Datos **fake** siempre: `test@example.com`, PAN de test (`4111 1111 1111 1111`), nunca reales.
- Nunca CVV, PAN o PII reales en `Examples`. Redactar cualquier dato sensible.
