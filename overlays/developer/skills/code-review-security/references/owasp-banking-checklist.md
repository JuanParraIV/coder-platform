# OWASP Banking Checklist — vulnerable → fixed

Ejemplos concretos por categoría para acelerar la revisión del diff. Cada patrón trae
el mapeo OWASP/PCI y una corrección mínima. Ejemplos en Python/JS/Java; el principio aplica cross-lenguaje.

## Inyección SQL — A03:2021 / PCI-DSS 6.5.1

```python
# ❌ VULNERABLE — concatenación
cur.execute("SELECT * FROM accounts WHERE id = '" + account_id + "'")
# ✅ FIX — query parametrizada
cur.execute("SELECT * FROM accounts WHERE id = %s", (account_id,))
```

## AuthZ / IDOR — A01:2021

```python
# ❌ El endpoint confía en el id del path sin verificar ownership
def get_account(account_id, user):
    return db.accounts.find(account_id)
# ✅ FIX — chequeo de autorización en servidor
def get_account(account_id, user):
    acc = db.accounts.find(account_id)
    if acc.owner_id != user.id and not user.is_admin:
        raise Forbidden()
    return acc
```

## JWT sin verificar — A07:2021

```javascript
// ❌ decode NO verifica firma/exp
const claims = jwt.decode(token);
// ✅ FIX — verify con algoritmo, exp y audiencia
const claims = jwt.verify(token, publicKey, { algorithms: ['RS256'], audience: 'banking-api' });
```

## Criptografía débil — A02:2021 / PCI-DSS 3.5

```java
// ❌ MD5/SHA1 para passwords, ECB, key hardcodeada
MessageDigest.getInstance("MD5");
// ✅ FIX — hash adaptativo para passwords, AES-GCM para datos
// Password: bcrypt / argon2 / scrypt
// Datos sensibles: AES-256-GCM con IV aleatorio y key desde Vault
```

## Aleatoriedad insegura para tokens — A02:2021

```python
# ❌ random no es criptográfico
token = str(random.random())
# ✅ FIX
token = secrets.token_urlsafe(32)
```

## Exposición de PAN / CVV — PCI-DSS 3.2 / 3.4

```python
# ❌ PAN completo en log; CVV almacenado
logger.info(f"pago pan={pan} cvv={cvv}")
db.save(cvv=cvv)
# ✅ FIX — CVV NUNCA se almacena; PAN enmascarado
logger.info(f"pago pan=****{pan[-4:]}")   # solo últimos 4
# no persistir CVV en ningún caso
```

## Dinero con float — lógica de negocio financiera

```python
# ❌ float pierde precisión en montos
total = 0.1 + 0.2            # 0.30000000000000004
# ✅ FIX — decimal de precisión fija
from decimal import Decimal
total = Decimal("0.1") + Decimal("0.2")
```

## SSRF — A10:2021

```python
# ❌ URL construida con input del usuario → puede pegar a metadata interna
requests.get(user_supplied_url)
# ✅ FIX — allowlist de host/esquema; bloquear 169.254.169.254 y rangos privados
```

## TLS deshabilitado — A02:2021

```python
requests.get(url, verify=False)   # ❌ nunca en banca
requests.get(url)                 # ✅ verificación por defecto
```

## Deserialización insegura — A08:2021

```python
pickle.loads(data)                # ❌ RCE con input no confiable
json.loads(data)                  # ✅ formato de datos, no de código
```

## IaC / config

```hcl
# ❌ bucket público, SG abierto, cifrado off
cidr_blocks = ["0.0.0.0/0"]
# ✅ FIX — origen restringido, cifrado en reposo, IAM least-privilege (no "*:*")
```

## Mapeo de severidad (recordatorio)

| Nivel | Ejemplo | Acción |
|-------|---------|--------|
| Critical | RCE, secreto activo, PAN/CVV filtrado, auth bypass | BLOCK + alertar |
| High | Inyección explotable, IDOR, cripto rota en datos sensibles | BLOCK |
| Medium | SSRF condicionado, dep con CVE high, logging de PII | COMMENT (debe corregirse) |
| Low | Hardening, defensa en profundidad | COMMENT (recomendado) |

**Redacta siempre** el valor real de secretos/PAN en el reporte (`****`). Ante la duda: fail-closed.
