# Mutation Testing Patterns

La cobertura dice qué se **ejecuta**; la mutación dice qué se **verifica**.
Un mutante superviviente = un cambio que rompe el código y ningún test lo detecta.

## Operadores de mutación comunes

| Operador | Original → Mutante | Qué revela si sobrevive |
|----------|--------------------|-------------------------|
| Relacional | `a > b` → `a >= b` | Falta test de boundary (igualdad) |
| Aritmético | `a + b` → `a - b` | No se verifica el valor calculado |
| Condicional | `if (x && y)` → `if (x \|\| y)` | Rama lógica sin aserción distinta |
| Booleano | `return true` → `return false` | Resultado no verificado |
| Constante | `limit = 1000` → `limit = 1001` | Falta test en el límite exacto |
| Return | `return x` → `return null` | La salida no se asegura |
| Negación | `if (a)` → `if (!a)` | Ambas ramas colapsan al mismo assert |

## Cómo matar un superviviente

1. Localiza la línea mutada y el operador.
2. Pregúntate: *¿qué input haría que original y mutante devuelvan distinto?*
3. Añade/refuerza el test con ese input y una **aserción sobre el resultado** (no sobre un mock).
4. Re-ejecuta la mutación sobre ese módulo; confirma que el mutante muere.

Ejemplo — sobrevive `amount >= 0` mutado a `amount > 0`:
el caso `amount == 0` no está testeado. Añade un test con `amount = 0` y asserta el comportamiento esperado (aceptar o rechazar según el AC).

## Mutantes equivalentes

Un mutante equivalente no cambia el comportamiento observable (ej: mutar código muerto,
o `x * 1` → `x + 0`). **No se pueden matar**: documéntalos con su razón en vez de forzar
tests artificiales. No cuentan contra el score.

## Alcance (coste)

- Ejecutar **solo sobre el módulo crítico objetivo** (lógica financiera, auth, validación).
- La mutación global del repo es cara en tiempo/CI: nunca a ciegas.
- Objetivo: subir el **mutation score**, no la cobertura de línea.

## Herramientas

| Lenguaje | Herramienta | Nota |
|----------|-------------|------|
| Python | mutmut, cosmic-ray | `mutmut run --paths-to-mutate <módulo>` |
| JS/TS | Stryker | `stryker run` con `mutate` acotado |
| Java | PIT (pitest) | `targetClasses` acotado al paquete crítico |
| Go | go-mutesting | por paquete |
| .NET | Stryker.NET | |
| Ruby / PHP | mutant / Infection | |

## Anti-patrones

- ❌ Correr mutación sobre todo el repo a ciegas.
- ❌ Matar mutantes con aserciones triviales que no reflejan comportamiento real.
- ❌ Modificar el source para reducir mutantes.
- ❌ Ignorar supervivientes en código de seguridad/dinero.
