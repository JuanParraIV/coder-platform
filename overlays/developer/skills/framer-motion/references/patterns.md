# Framer Motion — patrones de referencia

Import moderno: `import { motion, AnimatePresence, useReducedMotion } from "motion/react";`
En Next.js App Router, todo componente con estos hooks/gestos necesita `"use client"`.
Anima **solo `transform` (x/y/scale/rotate) y `opacity`**. Duración 0.15–0.3s para micro-interacciones.

---

## 1. Entrada simple (fade + slide)

```tsx
<motion.div
  initial={{ opacity: 0, y: 12 }}
  animate={{ opacity: 1, y: 0 }}
  transition={{ duration: 0.25, ease: "easeOut" }}
>
  {content}
</motion.div>
```

## 2. Salida al desmontar — AnimatePresence

`exit` solo funciona dentro de `<AnimatePresence>`, y cada hijo condicional necesita `key`.

```tsx
<AnimatePresence>
  {open && (
    <motion.aside
      key="drawer"
      initial={{ x: "100%" }}
      animate={{ x: 0 }}
      exit={{ x: "100%" }}
      transition={{ type: "spring", stiffness: 300, damping: 30 }}
    />
  )}
</AnimatePresence>
```

## 3. Variants + stagger (orquestar listas)

```tsx
const list = {
  hidden: {},
  show: { transition: { staggerChildren: 0.06 } },
};
const item = {
  hidden: { opacity: 0, y: 8 },
  show: { opacity: 1, y: 0 },
};

<motion.ul variants={list} initial="hidden" animate="show">
  {rows.map((r) => (
    <motion.li key={r.id} variants={item}>{r.label}</motion.li>
  ))}
</motion.ul>
```

## 4. Layout animations (reordenar / cambio de tamaño)

La prop `layout` anima automáticamente cambios de posición/tamaño (técnica FLIP, sin animar width/height).

```tsx
<motion.div layout transition={{ type: "spring", stiffness: 400, damping: 40 }}>
  {expanded ? <FullCard /> : <MiniCard />}
</motion.div>
```

`layoutId` compartido entre dos componentes crea una transición "magic move" (shared element).

## 5. Gestos — hover / tap / drag

```tsx
<motion.button
  whileHover={{ scale: 1.03 }}
  whileTap={{ scale: 0.97 }}
  transition={{ duration: 0.15 }}
>
  Guardar
</motion.button>

<motion.div drag dragConstraints={{ left: 0, right: 200 }} dragElastic={0.2} />
```

## 6. Scroll — reveal al entrar y parallax

```tsx
// Reveal cuando entra en viewport (una sola vez)
<motion.section
  initial={{ opacity: 0, y: 24 }}
  whileInView={{ opacity: 1, y: 0 }}
  viewport={{ once: true, amount: 0.3 }}
  transition={{ duration: 0.3 }}
/>

// Parallax con useScroll + useTransform
const { scrollYProgress } = useScroll();
const y = useTransform(scrollYProgress, [0, 1], [0, -120]);
<motion.div style={{ y }} />
```

## 7. Motion values / spring (sin re-render por frame)

```tsx
const x = useMotionValue(0);
const smooth = useSpring(x, { stiffness: 300, damping: 30 });
<motion.div style={{ x: smooth }} />
```

---

## Reduced motion (aplica a todos los patrones)

```tsx
const reduce = useReducedMotion();
// Degradar: sin desplazamiento, a lo sumo opacity.
const initial = reduce ? { opacity: 0 } : { opacity: 0, y: 12 };
const animate = { opacity: 1, y: 0 };
```

Alternativa global: envolver la app en `<MotionConfig reducedMotion="user">` para que
Framer Motion respete la preferencia del sistema automáticamente en transiciones de transform.

## Gotchas

- **SSR/Next:** falta de `"use client"` → error "useContext is not a function" o hidration mismatch.
- **`exit` no dispara:** el nodo no está dentro de `<AnimatePresence>` o le falta `key` estable.
- **Salto en layout animations:** el elemento cambia de `display` (none↔block); usa condicional dentro de AnimatePresence, no `display:none`.
- **Jank:** estás animando `width/height/margin`; cámbialo a `scale`/`transform` + `layout`.
- **Import:** `motion/react` (nuevo) y `framer-motion` (clásico) son equivalentes; no mezcles ambos en el mismo archivo.
