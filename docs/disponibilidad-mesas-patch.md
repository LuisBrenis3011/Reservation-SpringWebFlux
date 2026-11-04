# Fase 4 — Actualización de mesas (SPEC-001)

Implementadas T030–T037. PATCH bajo
/catalog/restaurants/{restaurantId}/tables/{tableId} completa la historia HU-02.
La fase 5 (T038–T040) permanece pendiente.

## Evidencia recibida de la fase 3

El responsable confirmó compilación, selección unitaria e integrationTest exitosas y
creó el commit d7958 (feat: register and query restaurant tables).
Los XML conservados de esa ejecución registran 76 casos seleccionados de test y
30 de integrationTest, sin fallos, errores ni omitidos. Sus timestamps UTC son
2026-10-24T04:27–04:28Z (23 de octubre en America/Lima).
El agente solo leyó esos informes; no repitió las suites.
Esta evidencia pertenece al código de fase 3, no acredita las pruebas nuevas.

## Actualización entregada

- Cuerpo TablePatch con al menos label o capacity. Omitido conserva el valor actual;
  null explícito, campos extra y tipos incompatibles producen 400. El deserializador
  rechaza fracciones y números fuera de int64; vacío o capacidad no positiva producen
  422 por validación semántica.
- Se conservan identidad y restaurante. Etiqueta con trim y clave lowercase ROOT;
  no hay autoasignación, eliminación ni adaptación de reservas.
- El servicio exige If-Match y usa el coordinador existente: recibo/fingerprint
  antes de comparar revisión, guard y escritura secuenciales, recibo en la misma
  transacción. Una colisión, protección o fallo conserva ambos campos y la revisión.
- Capacidad omitida o presente con el mismo valor usa LABEL_ONLY: renombrar no consulta
  compromisos y funciona con reservas antiguas o lector caído.
- Cambio efectivo de capacidad usa TABLE_CAPACITY: protección directa e indirecta
  mediante tableIds capturados en reservas, mientras endInstant > ahora. El fin exacto
  libera esa protección temporal. Legado o incertidumbre bloquean el cambio.
- Se comprueba la suma exacta de las otras mesas más la capacidad nueva; no se usa el
  aforo antiguo como límite. Overflow revierte el PATCH completo con 422.
- Respuesta 200 con revisión/ETag, sin Location. Replay devuelve cuerpo y revisión
  originales incluso después de otra operación, sin incremento persistente.
  Cambio de payload, ruta o If-Match con la misma clave produce 409; clave nueva con
  revisión obsoleta produce 412. Indisponibilidad/commit incierto conserva su 503 y
  Retry-After. Permisos y gate existentes se aplican también a PATCH.

El contrato OpenAPI no cambió: la operación ya estaba definida. No se modificaron
los componentes compartidos, los límites de tres intentos/5 segundos ni los
writers productivos de reservas de la fase 2.

## Trazabilidad de pruebas nuevas

| Tareas / RF | Escenarios preparados | Archivos principales |
|---|---|---|
| T030, T035–T036 / RF-01.4 | ESC-01.7–01.8: omitidos, identidad, actualización completa, colisión y overflow | AvailabilityTablePatchTests, AvailabilityTableValidatorTests; rollback real en AvailabilityTableConcurrencyIT |
| T031 / RF-01.5 | ESC-01.9–01.10, 01.13–01.14: futuro/en curso, directa/combinación, renombrado y fin exacto | AvailabilityTableProtectionTests |
| T032 / RF-01.7 | ESC-01.17–01.18: fallo/demora revierte PATCH; reintento con misma clave; renombrado con lector caído | AvailabilityTableFailureIT |
| T033 / RF-01.8 | ESC-01.19–01.20: renombrado permitido, cambio operativo bloqueado, datos antiguos conservados | AvailabilityTableLegacyIT |
| T034 / RF-01.6 | ESC-01.11–01.12: confirmación coordinada y actualización legacy real frente a PATCH, sin escrituras parciales | AvailabilityTableConcurrencyIT |
| T037 / RF-01.1 y contrato | PATCH propio, 401/403/404, body y headers estrictos, ETag, errores y gate | AvailabilityTableHttpTests |

La confirmación futura se representa con la fixture T004 dentro de writeLegacy
real, sin crear una API de reservas nueva. La otra carrera usa
ReservationCrudServiceImpl.updateReservation real. Si hay agotamiento de reintentos,
se exige ausencia de cambios parciales y solo se reintenta tras terminar la operación
competidora. No se agregan intentos internos ni se relajan protecciones.
Las reservas/snapshots se comparan antes y después de PATCH; el test del writer
legacy distingue los cambios de ese writer de los cambios de configuración.

**Conteos previstos tras esta entrega:** 127 casos en la selección unitaria/HTTP
(incluye los 7 de ReservationCrudServiceImplTests) y 52 de integración.
Se añaden 51 casos unitarios/HTTP y 22 de integración respecto a fase 3.
Son conteos de casos redactados, incluidos parámetros; no resultados de ejecución.

## Validación a cargo del usuario

Desde PowerShell o la terminal de IntelliJ:

```powershell
Set-Location D:\proyectosIntellij\SpringWebFlux
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Availability*' --tests '*ReservationCrudServiceImplTests'
.\gradlew.bat integrationTest
```

IntegrationTest requiere Docker y usa Mongo efímero de los fixtures, sin tocar datos
locales. Comprobar descubrimiento, cero fallos/errores/omitidos y conteos.
Informes: build/reports/tests/test/index.html y
build/reports/tests/integrationTest/index.html. La suite completa test conserva
contextLoads y sus requisitos locales; la selección anterior no equivale a esa suite.

El agente comprobó compilación, sin ejecutar suites, Docker, migraciones ni commits.
La aceptación de HU-02 queda pendiente del resultado aportado por el usuario.
Las listas de calidad/completitud funcional conservan sus casillas; T038–T040 no
se consideran realizadas por actualizar este seguimiento.

## Dos commits sugeridos, después de validar

El primer grupo agrega el modelo parcial y sus validaciones puras; el segundo
lo conecta al servicio/API e incorpora las pruebas de protección/concurrencia.
Cada archivo pertenece a un solo grupo; no separar cada tarea si deja dependencias
de compilación incompletas. Revisar siempre el diff preparado.

Git Bash, primer grupo:

```bash
cd /d/proyectosIntellij/SpringWebFlux
git add src/main/java/com/brenis/SpringWebFlux/dtos/requests/TablePatchRequest.java
git add src/main/java/com/brenis/SpringWebFlux/validators/TableConfigurationValidator.java
git add src/test/java/com/brenis/SpringWebFlux/validators/AvailabilityTableValidatorTests.java
git diff --cached --stat
git commit -m "feat: model and validate partial table updates"
```

Después, segundo grupo:

```bash
git add src/main/java/com/brenis/SpringWebFlux/services/definitions/TableConfigurationService.java
git add src/main/java/com/brenis/SpringWebFlux/services/impls/TableConfigurationServiceImpl.java
git add src/main/java/com/brenis/SpringWebFlux/handlers/TableConfigurationHandler.java
git add src/main/java/com/brenis/SpringWebFlux/routes/TableConfigurationRouter.java
git add src/test/java/com/brenis/SpringWebFlux/services/AvailabilityTablePatchTests.java
git add src/test/java/com/brenis/SpringWebFlux/handlers/AvailabilityTableHttpTests.java
git add src/integrationTest/java/com/brenis/SpringWebFlux/services/
git add src/integrationTest/java/com/brenis/SpringWebFlux/support/AvailabilityTableIntegrationSupport.java
git add docs/disponibilidad-mesas.md docs/disponibilidad-mesas-patch.md
git diff --cached --stat
git commit -m "feat: protect table updates with reservation checks"
```

Los artefactos SDD en D:/proyectosIntellij/specs permanecen fuera del Git del servicio.

## Validación confirmada de fase 4

El usuario confirmó 127 casos seleccionados y 52 de integración sin fallos, errores
ni omitidos. Los XML existentes coinciden; commits 4c421 y 81f0e.
Esta evidencia no incluye la instrumentación posterior de T038. Ver el
[estado de cierre](disponibilidad-cierre.md) para las verificaciones aún pendientes.

