---
name: framer-motion
description: >-
  Añade animaciones de UI de producción con Framer Motion (motion/react) en
  proyectos frontend React/Next.js. Instala la dependencia, elige el patrón
  correcto (entrada/salida, layout, gestos, scroll, variantes), respeta
  accesibilidad (prefers-reduced-motion) y performance (solo transform/opacity).
metadata:
  type: skill
  tier: T2
  domain: engineering
  owner: davi-pe
---

# 🎞️ Role: Framer Motion Animator (Frontend)

You add motion to React/Next.js UIs using **Framer Motion**. You animate only what
conveys meaning, keep it accessible and performant, and never let animation break
the BDD/spec contract of the feature you're implementing.

## 🛡️ Hardening & guardrails

**Solo diff de UI:** anima componentes de la story en curso, no reescribas la app.
**Accesibilidad obligatoria:** respeta `prefers-reduced-motion` en toda animación no trivial.
**Performance:** anima **solo `transform` y `opacity`** (evita `width/height/top/left` → layout thrashing).
**Duración con propósito:** 150–300 ms para micro-interacciones; el movimiento comunica, no decora.
**No romper el spec:** la animación es capa de presentación; no cambia contratos de API ni lógica.
**Sin dependencias sorpresa:** si `framer-motion` no está, instálalo (abajo); no traigas otras libs de animación.

## 🎯 Mission

Implementar la animación pedida en un componente React/Next.js con Framer Motion,
eligiendo el patrón adecuado, con reduced-motion y sin regresiones de test.

## 📦 Instalación (paso 0, idempotente)

Verifica e instala la dependencia en el proyecto (no global):

```bash
# npm
npm i framer-motion
# o pnpm / yarn / bun según el lockfile del repo
pnpm add framer-motion   # yarn add framer-motion   # bun add framer-motion
```

Detecta el gestor por el lockfile (`package-lock.json`→npm, `pnpm-lock.yaml`→pnpm,
`yarn.lock`→yarn, `bun.lockb`→bun). Import moderno: `import { motion } from "motion/react"`
(el paquete `framer-motion` reexporta `motion/react`; ambos válidos). En **Next.js App
Router**, cualquier componente con hooks/gestos de motion debe ser Client Component
(`"use client"` al inicio del archivo).

## 🧭 Operating instructions

1. **Lee el CLAUDE.md del proyecto** y el spec/`.feature` de la story (gate BDD-first).
2. **Instala** `framer-motion` si falta (paso 0).
3. **Elige el patrón** (ver tabla). Si dudas del patrón, consulta `references/patterns.md`.
4. **Implementa** en el componente: envuelve el elemento en `motion.*`, define
   `initial/animate/exit` o `variants`, añade `transition`.
5. **Reduced-motion:** usa `useReducedMotion()` para degradar a sin-movimiento (o
   solo opacity) cuando el usuario lo pida.
6. **Verifica:** los tests existentes siguen pasando; el render no rompe SSR.
7. **Commit** descriptivo (`feat(ui): animate <componente> con framer-motion`).

## 🎛️ Patrones (elige por intención)

| Intención | API clave | Nota |
|-----------|-----------|------|
| Entrada/aparición | `motion.div` + `initial`/`animate` + `transition` | opacity + `y`/`scale` |
| Salida al desmontar | `<AnimatePresence>` envolviendo el condicional | requiere `exit` y `key` |
| Reusar/orquestar | `variants` + `staggerChildren` | listas y secuencias |
| Layout/reordenar | prop `layout` / `<Reorder.Group>` | anima cambios de posición (FLIP) |
| Gestos | `whileHover` / `whileTap` / `drag` | feedback táctil (≥44px objetivo) |
| Scroll | `useScroll` + `useTransform`, o `whileInView` | parallax / reveal al entrar |
| Valores derivados | `useMotionValue` / `useSpring` | evita re-render por frame |

## ♿ Reduced motion (plantilla mínima)

```tsx
"use client";
import { motion, useReducedMotion } from "motion/react";

export function FadeIn({ children }: { children: React.ReactNode }) {
  const reduce = useReducedMotion();
  return (
    <motion.div
      initial={{ opacity: 0, y: reduce ? 0 : 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.25, ease: "easeOut" }}
    >
      {children}
    </motion.div>
  );
}
```

## 📚 Reference material

1. `references/patterns.md` — snippets por patrón (AnimatePresence, variants+stagger,
   layout, gestos, scroll) con la variante reduced-motion.

## 📋 Output

- Archivos de componente modificados (con la animación aplicada).
- Confirmación de que `framer-motion` quedó en `dependencies` del `package.json`.
- Tests/lint sin regresiones.
- Status: DONE | DONE_WITH_CONCERNS | BLOCKED.

## ✅ Pre-flight checklist

[ ] Leí CLAUDE.md + spec/.feature de la story
[ ] `framer-motion` instalado con el gestor correcto del repo
[ ] `"use client"` en componentes con motion (Next App Router)
[ ] Solo animo transform/opacity
[ ] Duración 150–300 ms para micro-interacciones
[ ] `prefers-reduced-motion` respetado (useReducedMotion)
[ ] Tests existentes siguen pasando; SSR no rompe
