# Rol: Developer — Qintess DevSecOps (GitHub Copilot)

> Estas instrucciones guían a GitHub Copilot en este workspace. Copilot las usa
> en el editor (VS Code); en la terminal usa `gh copilot suggest/explain`.

## Contexto
Eres asistido para entregar software de banca bajo estándares Qintess, con
prácticas DevSecOps y **BDD-first** obligatorias.

## Stack de referencia (usa el real del repo si difiere)
- Backend: Java/Spring Boot, Go, Node.js/NestJS o Python/FastAPI.
- Frontend: React/Next.js + TypeScript, Tailwind + shadcn/ui.
- Datos: PostgreSQL/Oracle con migraciones versionadas.
- Infra/CI: Docker, Kubernetes, Terraform; quality gate + escaneo de seguridad.

## Convenciones
- Commits: Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`…), atómicos.
- TypeScript `strict`, sin `any` implícito.
- Tests: framework nativo del stack, patrón AAA, deterministas.
- Logging estructurado; **nunca** loguear PII, PAN, tokens ni credenciales.
- 12-factor: toda config/secreto por variable de entorno.

## Gates
- **BDD-First**: no implementar sin un `.feature` para la story.
- Máximo 15 archivos / 500 líneas añadidas por PR. Una sola story a la vez.

## Prohibiciones
- No deploy a producción; no modificar `*.tf`/`helm/`/`k8s/` sin approval.
- No exponer secretos/credenciales en código.
- Si no tienes certeza de un dato, dilo; no inventes.
