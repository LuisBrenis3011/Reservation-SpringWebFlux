# Fase 3 — Registro y consulta de mesas (SPEC-001)

Implementadas T018–T029. El alcance comprende POST de colección y GET de colección/recurso.
PATCH, cambios de capacidad, renombrados y sus pruebas pertenecen a la fase 4.

## Comportamiento entregado

- Rutas bajo /catalog/restaurants/{restaurantId}/tables y /{tableId}; el router usa
  rutas relativas porque Spring WebFlux aplica la base /catalog.
- Solo el encargado autorizado accede. El handler comprueba permiso antes de leer
  el cuerpo y el servicio también protege su frontera de acceso.
- Alta con UUID estable durante los reintentos internos. Etiqueta visible con trim,
  clave en minúsculas ROOT e índice único (restaurantId,labelKey).
- JSON sin coerciones: label string y capacity entero int64 obligatorios; campos
  extra, null, tipos incorrectos y fracciones se rechazan con 400. Etiqueta vacía y
  capacidad no positiva producen 422.
- Alta coordinada con CREATE_OPERATIONAL; legado o comprobación fallida revierten
  mesa, revisión y recibo. Las consultas siguen disponibles con reservas antiguas.
- Capacidad física sumada con Math.addExact dentro del snapshot. No se consulta
  aforo antiguo ni combinaciones para sumar. Vacío devuelve cero. El alta verifica
  también que el nuevo total sea representable; desbordamiento produce 422.
- POST devuelve 201, Location y ETag. GET devuelve 200, revisión y ETag coherentes.
  El replay mantiene cuerpo, identidad, estado, Location y revisión originales.
- No se cachean estas lecturas, no se editan reservas y no se activa el feature gate.
  Las dependencias de seguridad, transacciones y límites de la fase 2 se reutilizan.

## Pruebas y trazabilidad

| Tarea / RF | Casos preparados | Archivo |
|---|---|---|
| T018 / RF-01.1, ESC-01.1–01.2 | 401/403, permiso propio, JSON estricto, errores, headers, gate y ausencia de PATCH | AvailabilityTableHttpTests |
| T019 / RF-01.2, ESC-01.3–01.4 | Etiqueta normalizada, ausentes, no positivos y overflow; fracciones en HTTP | AvailabilityTableValidatorTests |
| T020 / RF-01.3, ESC-01.5–01.6, 01.15–01.16 | Mapeo, vacío, suma y revisión; persistencia, aislamiento, aforo antiguo y combinaciones en IT | AvailabilityTableReadTests + AvailabilityTableLegacyIT |
| T021 / RF-01.6, ESC-01.11–01.12 | Índice único, carrera de POST, snapshot concurrente y replay tipado | AvailabilityTableConcurrencyIT |
| T022 / RF-01.7, ESC-01.17–01.18 (POST) | Fallo/demora del lector, rollback, reintento con misma clave y overflow | AvailabilityTableFailureIT |
| T023 / RF-01.8, ESC-01.20 | Legado bloquea POST, permite GET y conserva reservas | AvailabilityTableLegacyIT |

Los IT reutilizan AvailabilityIntegrationConfiguration y las fixtures T004 mediante
AvailabilityTableIntegrationSupport. El fallo/demora se inyecta únicamente en un
decorador del lector de pruebas: coordinador, guard, repositorio, Mongo e índices
siguen siendo reales. No se modifica ningún presupuesto productivo.
La carrera de duplicados admite rechazo por etiqueta o agotamiento acotado de
reintentos, exige una sola mesa/recibo/revisión y comprueba el conflicto definitivo
después de terminar ambas solicitudes.

**Conteo esperado de casos nuevos:** 35 en test (22 HTTP, 10 validador, 3 lectura)
y 9 en integrationTest (4 concurrencia, 3 fallos, 2 legado/lectura).
Es un conteo de casos redactados, incluidos parámetros; no evidencia de ejecución.
Los casos de PATCH de RF-01.4/01.5 y las ampliaciones de RF-01.6–01.8 permanecen pendientes.

## Validación para PowerShell o terminal de IntelliJ

Compilación, sin ejecutar suites:

```powershell
Set-Location D:\proyectosIntellij\SpringWebFlux
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
```

Unitarias/HTTP seleccionadas, sin Mongo local ni Docker:

```powershell
.\gradlew.bat test --tests '*Availability*' --tests '*ReservationCrudServiceImplTests'
```

Integración completa con Docker disponible: usa Mongo replica set efímero, sin
conectarse a los datos locales ni usar credenciales de .env.

```powershell
.\gradlew.bat integrationTest
```

Informes: build/reports/tests/test/index.html y
build/reports/tests/integrationTest/index.html.
Confirmar descubrimiento y cero fallos/omitidos. UP-TO-DATE significa reutilización
del resultado previo; si necesitas una ejecución nueva explícita, añade --rerun-tasks.
No usar NO-SOURCE como validación. La suite test completa contiene contextLoads y
mantiene sus requisitos reales de infraestructura, descritos en la guía de fase 2.

## Estado de verificación

Compilación de main, fixtures, unitarias e integración comprobada por el agente.
No se ejecutaron suites, Docker, migraciones ni commits.
La aceptación de HU-01 queda pendiente de los resultados del usuario.
Los contratos OpenAPI y el esquema de reservas antiguas no se modificaron.
La firma de PATCH se aplaza junto con su DTO a HU-02 para evitar introducir
componentes de fase 4. No hay métodos productivos incompletos ni rutas PATCH.

## Validación confirmada y continuación

La entrega descrita arriba corresponde a fase 3. El usuario confirmó compilación,
selección unitaria e integración exitosas y creó el commit d7958. Los informes XML
de esa ejecución registran 76 pruebas seleccionadas y 30 de integración, sin fallos,
errores ni omitidas. El agente leyó los informes sin ejecutar suites.
PATCH se incorpora ahora en [fase 4](disponibilidad-mesas-patch.md), con validación
nueva pendiente; las notas anteriores de ausencia de PATCH son históricas.

