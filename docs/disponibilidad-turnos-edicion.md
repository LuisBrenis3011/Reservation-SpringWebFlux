# SPEC-003 — Fase 5: editar turnos y cambiar zona

**Actualización 2026-10-28:** usuario confirmó compilación, 225 pruebas seleccionadas
y 120 de integración exitosas, XML sin fallos, errores ni omitidas. Commit actual
8612b2ed84df70aa733e49a4f8595d42ef29c1f5; árbol limpio al comenzar la revisión.
T086 revisada, T087 parcial; 26/27 y lote 87/88. [Estado vigente, matriz y hallazgos
de cobertura H1–H3](disponibilidad-turnos-validacion.md). Los apartados inferiores
conservan el historial de preparación, previo a recibir estos resultados. SPEC-003
no está cerrada ni aprobada.

T081–T085 implementadas/redactadas. SPEC-003: 25/27 tareas; lote 86/88, dos
pendientes (T086/T087). Compilación exitosa, suites de este incremento pendientes
del usuario. No se ejecutaron suites, servicios, Docker, HTTP ni commits.

## Evidencia de fase 4

El usuario confirmó compilación, selección e integración exitosas. Los XML
disponibles anteriores a esta ampliación contienen 224 casos de test y 110 de
integrationTest, cero fallos, errores y omitidas. Son ejecuciones del usuario;
el agente solo leyó los informes y compiló el código nuevo, sin repetir suites.

HEAD observado: c116536483763a6aa517e019c54effce491b8d22 (zona inicial).
Los cambios de fase 4 estaban preparados en el índice, aún sin un commit nuevo
visible. No se modificó ese índice ni se asume un hash de commit no observado.

## Cambios implementados

- PUT `/catalog/restaurants/{restaurantId}/shifts/{shiftId}` exige permisos,
  Idempotency-Key e If-Match; conserva id/restaurante y devuelve 200/ETag sin Location.
- Inicio original y propuesto deben ser estrictamente futuros según Context.now.
  Igual al instante actual o pasado produce 409 SHIFT_ALREADY_STARTED. Se valida
  la zona configurada, offsets únicos y duración; al buscar superposición se
  excluye únicamente el propio id y se consulta el mismo restaurante.
- Guard SHIFT protege referencias comprometidas; legacy/global y fallo de consulta
  bloquean sin alterar datos. No se cancelan ni reubican reservas ni snapshots.
- PUT de zona ya admite turnos: guard ZONE, separación por inicio efectivo,
  conservación completa de iniciados y recálculo de futuros manteniendo locales.
  Se rechazan gap/overlap estacional, fin inválido, inicio recalculado no futuro
  o superposición con cualquier otro turno futuro o histórico conservado.
- Se valida todo antes de guardar; los futuros se escriben con concatMap y la
  zona en la misma frontera transaccional. Un fallo revierte recursos, revisión
  y recibo. GET sigue usando snapshots históricos, sin reinterpretarlos.
- Replay conserva respuesta histórica y revisión del recibo, sin ejecutar otra
  modificación. Concurrencia, presupuestos y metadatos siguen siendo del coordinador
  compartido; no se cambian OpenAPI, guard, lector, Clock o infraestructura común.

## Pruebas redactadas, no ejecutadas

AvailabilityShiftZoneChangeIT cubre conservación de historia/locales, recálculo,
rechazo del conjunto por un turno inválido, inicio recalculado no futuro,
superposición con historia, reserva en curso, edición/replay e inicio original
igual al reloj. Las ampliaciones de OverlapIT comprueban exclusión de identidad,
revisión obsoleta y conflicto; FailureIT comprueba fallo/demora, rollback de edición
y zona y reintento; LegacyIT comprueba PUT de turno/zona sin alterar legado.
ConcurrencyIT enfrenta edición con confirmación coordinada de reserva y verifica
rechazo sin cambios, manteniendo agotamiento acotado como resultado admisible.
HTTP comprueba PUT/ETag/cabeceras y gate; las pruebas anteriores se conservan.

El antiguo caso de barrera temporal por turnos incompletos se actualizó: el caso
sigue rechazando, ahora por COMMITMENT_CHECK_UNAVAILABLE debido a datos no fiables,
sin debilitar conservación. La barrera temporal de HU-01 se sustituye por la
implementación completa; no se habilitaron servicios ni se modificó el gate.

## Validación — PowerShell

Desde SpringWebFlux, cada comando en una línea; Docker disponible para integración:

```powershell
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Availability*' --tests '*ReservationCrudServiceImplTests'
.\gradlew.bat integrationTest
```

Revisar XML nuevos y descubrimiento de ZoneChangeIT. Los conteos 224/110 son
anteriores y no acreditan las pruebas nuevas. No se declara aceptación sin resultados.

## Git Bash — únicamente si las validaciones pasan

El índice ya contenía fase 4. Antes de añadir fase 5, revisar `git diff --cached --stat`.
Si se desea conservar un commit por fase, registrar primero el contenido ya
preparado de fase 4; después añadir la ampliación. El agente no hizo ninguna de esas acciones.

```bash
git add src/main/java/com/brenis/SpringWebFlux/ src/test/java/com/brenis/SpringWebFlux/handlers/AvailabilityShiftHttpTests.java src/integrationTest/java/com/brenis/SpringWebFlux/services/ README.md docs/disponibilidad-turnos.md docs/disponibilidad-turnos-edicion.md docs/disponibilidad-zona-horaria.md
git diff --cached --check
git diff --cached --stat
git commit -m "feat: edit shifts and atomically change restaurant time zone"
```

Documentos SDD externos fuera del Git del servicio. T086/T087 y fase 6 pendientes;
SPEC-003 no está cerrada ni aprobada.
