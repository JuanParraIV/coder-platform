# Test Design Patterns

Patrones y anti-patrones para tests unitarios/integración reales (con aserciones).
Ejemplos en Python y TS/JS; aplican igual a Java/Go/.NET/Rust.

## Naming Convention

```python
# Python (pytest)
def test_find_by_email_returns_user_when_email_exists(): ...
def test_find_by_email_raises_when_email_missing(): ...
```

```typescript
// TS/JS (jest/vitest)
describe('UserService', () => {
  describe('findByEmail', () => {
    it('should return user when email exists', () => {})
    it('should throw NotFound when email is missing', () => {})
  })
})
```

Respeta el naming del proyecto (`test_*.py` vs `*_test.py`, `*.spec.ts` vs `*.test.ts`).

## Patrón AAA (obligatorio)

Un comportamiento por test. Arrange → Act → Assert, visualmente separados.

```python
def test_returns_user_when_email_exists():
    # Arrange
    db = make_fake_db(rows=[{"email": "test@example.com"}])
    # Act
    result = find_by_email(db, "test@example.com")
    # Assert
    assert result == {"email": "test@example.com"}
```

## Qué testear por función

| Categoría | Ejemplo |
|-----------|---------|
| Happy path | Input válido → salida esperada |
| Input inválido | null, vacío, tipo incorrecto, fuera de rango |
| Boundary | 0, 1, MAX, array vacío, un solo elemento |
| Propagación de error | La dependencia lanza → la función lo maneja correctamente |
| Transición de estado | Antes/después de una mutación |
| Seguridad/negocio | Autorización denegada, monto negativo, idempotencia |

## Jerarquía de mocking

1. **No mockear** — usa objetos reales cuando son baratos (funciones puras, DTOs).
2. **Stub** — reemplaza el valor de retorno de una función.
3. **Spy** — observa llamadas sin cambiar comportamiento.
4. **Mock** — reemplaza un módulo entero, **solo** para I/O externo: DB, HTTP, filesystem, time, random.

Regla: si el test solo verifica que un mock fue llamado, no está testeando comportamiento.

## Anti-patrones

- ❌ Aserción única `expect(mock).toHaveBeenCalledWith(...)` sin verificar resultado.
- ❌ Testear el framework/lenguaje (`assert json.loads('{}') == {}`).
- ❌ Estado mutable compartido entre tests.
- ❌ Tests que dependen del orden de ejecución.
- ❌ Aserciones sobre `console.log`/stdout como único check.
- ❌ Tests sin aserción (pasan en silencio) o que no pueden fallar.
- ❌ Red/DB/tiempo/random reales en un unit test.
- ❌ Snapshot-everything para inflar cobertura.

## Determinismo

- Congela el tiempo (`freezegun`, `jest.useFakeTimers`) y siembra el random.
- Sin red real: usa fixtures/factories. Sin dependencia de estado global.
- Si un test falla y el test está bien → **reporta probable bug del source**, no toques el source para que pase.
