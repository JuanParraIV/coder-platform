# Architecture Principles — checklist + smells

Guía de evaluación por principio. Para cada uno: qué buscar, el síntoma (smell) y el fix.

## Single Responsibility (SRP)

- **Buscar**: una clase/módulo/servicio con una sola razón de cambio.
- **Smell**: nombres "Manager/Utils/Helper" que hacen de todo; funciones >50 líneas con múltiples niveles de abstracción; un endpoint que valida + persiste + notifica + audita inline.
- **Fix**: extraer responsabilidades a colaboradores (servicio de validación, repositorio, notificador).

## DRY vs. duplicación

- **Buscar**: lógica de negocio repetida (no boilerplate).
- **Smell**: la misma regla (ej. cálculo de comisión) copiada en 3 sitios; drift entre copias.
- **Fix**: centralizar en una función/servicio único. Ojo: no abstraer coincidencias accidentales (eso acopla de más).

## YAGNI

- **Buscar**: solo lo que la historia pide.
- **Smell**: flags de configuración "por si acaso", capas de plugin sin segundo caso de uso, generalización especulativa.
- **Fix**: borrar lo especulativo; introducir la abstracción cuando llegue el segundo caso real.

## Acoplamiento y dependencias

- **Buscar**: dependencias explícitas, inyectadas, mínimas.
- **Smell**: `new` de dependencias pesadas dentro de la lógica; singletons globales; import ciclos; una capa que conoce detalles internos de otra.
- **Fix**: inyección de dependencias; depender de interfaces/puertos, no de implementaciones; invertir la dependencia.

## Escalabilidad

- **Buscar**: comportamiento a 10x carga.
- **Smell**: N+1 queries; estado mutable en memoria compartido entre requests; trabajo síncrono que debería ser async (waitUntil/cola); ausencia de paginación/rate limit; locks de grano grueso.
- **Fix**: batch/índices, statelessness, colas para trabajo diferido, idempotencia en operaciones repetibles.

## Seguridad (banking)

- **Buscar**: authz por recurso, manejo de datos sensibles, superficie de ataque.
- **Smell**: authz en cliente; PAN/CVV en logs; montos en `float`; secretos en config; input del usuario en URLs salientes (SSRF); ausencia de auditoría en operaciones de dinero.
- **Fix**: authz server-side por ownership; PAN enmascarado/tokenizado, CVV nunca persistido; `decimal` para dinero; secretos desde Vault; allowlist de egress; traza de auditoría. (Ver skill `dev/code-review-security`.)

## Testabilidad

- **Buscar**: se puede testear en aislamiento.
- **Smell**: efectos secundarios ocultos (I/O en constructores), tiempo/random sin inyectar, dependencias no mockeables, lógica pegada al framework.
- **Fix**: puertos/adaptadores, inyectar reloj y fuentes de aleatoriedad, separar lógica pura de I/O.

## Consistencia con CLAUDE.md

- **Buscar**: mismos patrones/convenciones que el resto del proyecto.
- **Smell**: nuevo estilo de manejo de errores, naming divergente, un segundo mecanismo para algo ya resuelto.
- **Fix**: alinear con el patrón documentado; si el patrón existente es peor, proponerlo como hallazgo aparte, no divergir en silencio.

## Mapeo severidad

| Severidad | Ejemplos |
|-----------|----------|
| **Critical** | Race condition en transacción de dinero, authz ausente, dato sensible expuesto, punto único de fallo sin fallback |
| **Important** | N+1 en path caliente, acoplamiento fuerte que bloquea tests, duplicación de regla de negocio |
| **Suggestion** | Nombre poco claro, extracción menor, mejora de legibilidad estructural |
