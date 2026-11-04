# SPEC-002 — Fase 4: reemplazar integrantes de combinaciones

**Actualización de evidencia:** el usuario confirmó después compilación, 184
pruebas seleccionadas y 91 de integración exitosas; se contaron los XML (cero
fallos, errores y omitidas). Commit observado `53c0901`. El registro de fase 5 y
sus pendientes están en [la revisión de entrega](disponibilidad-combinaciones-validacion.md).
Los párrafos siguientes conservan la situación al entregar fase 4.

T055–T058 implementadas/redactadas el 2026-10-27. Se compiló main,
testFixtures, test e integrationTest con BUILD SUCCESSFUL. No se ejecutaron
suites, servicios, recorridos HTTP, migraciones ni acciones Git del agente.
Las pruebas de esta ampliación siguen pendientes del responsable.
No se inició fase 5 (T059–T060) ni se declara cerrada SPEC-002.

## Evidencia heredada de fase 3

El usuario confirmó 164 pruebas seleccionadas y 68 de integración sin fallos,
errores ni omitidas, y el commit `61284`
(`6128494773deac25e76a4fdced539210481efefa`). Esta evidencia corresponde al
estado anterior a PUT; no acredita las pruebas nuevas ni se reutilizan XML
antiguos para afirmar resultados de esta fase.

## Comportamiento y componentes

PUT `/catalog/restaurants/{restaurantId}/table-combinations/{combinationId}`
reutiliza el request estricto `tableIds`, el mapper, el soporte HTTP, la seguridad,
el guard y el coordinador transaccional existentes. Requiere `Idempotency-Key`
e `If-Match` fuerte; devuelve 200 con cuerpo y ETag, sin Location nuevo.

- `TableCombinationHandler` y `TableCombinationRouter` exponen PUT bajo el gate
  existente y autorizan antes de interpretar el cuerpo.
- `TableCombinationServiceImpl.replace` conserva id y restaurante, verifica
  integrantes propios y deriva capacidad de las mesas vigentes en la transacción.
- `TableCombinationRepository` excluye el id actual al buscar conjuntos equivalentes;
  se conserva el índice único existente y el rechazo 409 de duplicados.
- Cambios efectivos usan `COMBINATION_MEMBERS`: se protegen los integrantes
  originales comprometidos en reservas futuras o en curso hasta el fin del turno.
  No se reubican mesas ni se alteran reservas o snapshots.
- PUT equivalente, incluso con otro orden, sigue comprobando legado y dependencia
  disponible. Una nueva clave válida incrementa revisión una vez; replay devuelve
  cuerpo y ETag originales sin modificar datos ni revisión, aunque haya cambios posteriores.
- If-Match obsoleto devuelve 412; conflicto de clave o protección devuelve 409;
  integrantes inválidos 422 y comprobación indisponible 503, sin escrituras parciales.
  El coordinador mantiene tres intentos y presupuesto de cinco segundos.

No se cambiaron componentes compartidos, índices, build, OpenAPI ni caché.
`AvailabilityCombinationIntegrationSupport` solo añade la invocación de replace
sobre los fixtures de SPEC-001 ya reutilizados por SPEC-002.

## Pruebas redactadas para esta fase

| Tarea | Archivos y casos |
|---|---|
| T055 | `AvailabilityCombinationProtectionIT`: RF-02.4, ESC-02.7–02.8/02.11–02.12; cambio libre, añadir/quitar/reemplazar con reservas futuras/en curso, PUT equivalente, fin exacto y conservación histórica. |
| T056 | `AvailabilityCombinationHttpTests` y `AvailabilityCombinationValidatorTests`: permisos, cuerpo/cabeceras, errores, cardinalidad, integrantes propios y gate de PUT. |
| T056 | `AvailabilityCombinationConcurrencyIT`: duplicado excluyendo identidad, revisión obsoleta, replay histórico, dos PUT concurrentes y confirmación concurrente de reserva. |
| T056 | `AvailabilityCombinationFailureIT` y `AvailabilityCombinationLegacyIT`: fallo/demora y legado BSON/string bloquean también PUT equivalente; rechazo conserva datos/revisión/recibos y fallo recuperable permite reintentar. |

Las carreras admiten éxito o agotamiento acotado cuando corresponde; comprueban
ausencia de parciales y reintento después de la competidora. Mongo real es efímero
en integración; los datos de prueba no se escriben en Mongo local de 27018.
La tabla describe pruebas redactadas y compiladas, no resultados aprobados.

## Validación — PowerShell

Desde `<WORKSPACE>\SpringWebFlux`, cada comando en una línea:

```powershell
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Availability*' --tests '*ReservationCrudServiceImplTests'
.\gradlew.bat integrationTest
```

Integración requiere Docker Desktop. Revisar descubrimiento y los informes nuevos
de `build/test-results` y `build/reports/tests`, sin fallos, errores u omitidas.
No se fija un conteo nuevo hasta la ejecución del usuario. No se ejecutan suites
automáticamente. Recorridos reales, reinicio y gates de SPEC-002 siguen pendientes
de la fase de entrega; la evidencia de SPEC-001 no los sustituye.

## Git Bash — únicamente si las validaciones pasan

```bash
git add src/main/java/com/brenis/SpringWebFlux/services/ src/main/java/com/brenis/SpringWebFlux/repositories/TableCombinationRepository.java src/main/java/com/brenis/SpringWebFlux/handlers/TableCombinationHandler.java src/main/java/com/brenis/SpringWebFlux/routes/TableCombinationRouter.java
git add src/test/java/com/brenis/SpringWebFlux/handlers/AvailabilityCombinationHttpTests.java src/test/java/com/brenis/SpringWebFlux/validators/AvailabilityCombinationValidatorTests.java src/integrationTest/java/com/brenis/SpringWebFlux/services/AvailabilityCombination*.java src/integrationTest/java/com/brenis/SpringWebFlux/support/AvailabilityCombinationIntegrationSupport.java README.md docs/disponibilidad-combinaciones.md docs/disponibilidad-combinaciones-put.md
git diff --cached --check
git diff --cached --stat
git commit -m "feat: replace table combinations with reservation protection"
```

Los documentos SDD externos al repositorio del servicio no se añaden con estos comandos.
