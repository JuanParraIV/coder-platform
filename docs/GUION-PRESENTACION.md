# Guion para explicar el Manual Técnico

> Notas del presentador para recorrer el artefacto **Manual Técnico — Plataforma Coder + Claude Code por Rol**.
> Documento separado del artefacto (no se muestra a la audiencia).

---

## Apertura (30 seg) — qué es este documento

> "Este es el manual técnico de la plataforma. Tiene dos mitades: la primera (secciones 00–10) es **cómo
> cualquiera la levanta desde cero en su propio computador** — la ruta que ya validamos sobre Docker. La segunda
> (11–24) es la **referencia de diseño para producción**. El índice de la izquierda te lleva a cualquier sección."

---

## Recorrido por bloques (5–8 min)

### 1. El concepto — sección 00 + Fig. 1
> "Una persona entra con su cuenta, la plataforma detecta su rol y le arma un workspace en el navegador ya
> configurado. Este diagrama muestra el flujo: login → el control plane resuelve el rol → el workspace nace con
> las herramientas, integraciones y reglas de ese rol."

### 2. La parte de replicación — secciones 01–06
> "Estos son los pasos reales para montarlo: instalar Coder y Docker, crear las dos credenciales de GitHub,
> configurar el server y publicar el template. Lo importante: **corre en un solo computador, sin nube y sin
> permisos de administrador**."

- **Punto clave a subrayar** (secciones 03 y 17): las **dos credenciales GitHub** — "una es para el login, otra
  para resolver el rol. Son distintas y es el error más común."

### 3. El corazón del gobierno — secciones 13–14 + Fig. 2
> "Aquí está lo que hace esto apto para banca: el rol se resuelve automáticamente por el equipo al que perteneces.
> Fig. 2 muestra la cadena. Y la matriz (14) dice exactamente qué puede tocar cada rol. Dos reglas: en caso de
> duda gana el **menos permisivo**, y **quitar acceso es inmediato**."

### 4. El flujo de trabajo — sección 16 + Fig. 3
> "Los 3 roles colaboran sobre un mismo documento: el architect escribe el spec, QA lo convierte en pruebas BDD,
> el developer implementa. El `.feature` es el contrato."

### 5. Producción y estado — secciones 22 + 24
> "El plano de producción es la misma arquitectura sobre Kubernetes. Y la sección 24 es honesta: dice qué está
> ✅ validado y qué queda ⏳ pendiente."

---

## Las 3 frases que hay que dominar

1. **"Piloto→producción es escala e infraestructura, no rediseño."** (aparece en 00)
2. **"El aislamiento per-usuario: usuario A ve 90 repos, usuario B ve 0."** (sección 17 — la prueba más fuerte)
3. **"El rol se estampa en build-time; quitar acceso se resuelve terminando el workspace."** (Decisión #18)

---

## Preguntas probables y dónde está la respuesta

| Pregunta | Sección a abrir |
|---|---|
| "¿Cómo lo instalo?" | 01–06 |
| "¿Cómo evita que la IA vea de más?" | 13, 17, 18 |
| "¿Y con nuestro IdP corporativo?" | 21 (nivel 3) |
| "¿Qué falta?" | 24 |
| "¿Cuánto cuesta?" | 23 (budget + auto-stop) |

---

## Flancos a anticipar

- **Backend LLM (token Pro 401)** — sección 10/24: "es ajuste de credencial, no de diseño; el backend es
  intercambiable (suscripción / Vertex / Bedrock)."
- **Algunos comandos de la Parte A** se reconstruyeron de los runbooks/memoria — verificarlos contra el código
  antes de usarlos como fuente de verdad si alguien va a ejecutarlos en vivo.
