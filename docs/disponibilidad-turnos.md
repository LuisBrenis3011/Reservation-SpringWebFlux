# SPEC-003 — Fase 4: registrar y consultar turnos

**Actualización posterior:** el usuario confirmó las tres validaciones; XML
224/110 sin incidencias. Fase 5 implementada y compilada, suites nuevas pendientes:
[estado y comandos vigentes](disponibilidad-turnos-edicion.md). Los párrafos siguientes
conservan la situación de entrega de fase 4, no una ausencia vigente de PUT.

T069–T080 implementadas/redactadas. SPEC-003 queda en **20/27 tareas** y el lote
en **81/88**; T081 y fase 5 sin iniciar. Compilación de main, testFixtures, test
e integrationTest exitosa. El agente no ejecutó suites, HTTP, Docker, servicios,
migraciones ni commits. La validación de este incremento espera al usuario.

## Evidencia anterior y autoría

El usuario confirmó integrationTest exitoso después de corregir el aislamiento de
AvailabilityTimeZoneIT. Los XML disponibles se leyeron antes de modificar código:
**101 casos de integración**, cero fallos/errores/omitidos, inicios de clases
2026-10-28T20:03:34.754Z–20:04:13.835Z. Es evidencia de fase 3, no de turnos nuevos.

También existe un informe de test de **202 casos sin incidencias**, con inicios
2026-10-28T19:37:20.024Z–19:37:34.185Z, anterior al informe de integración. Se
registra como informe existente, no como nueva ejecución confirmada de la selección.
Los timestamps indican inicios de clases, no duración de suites. No se suman ambos
totales ni se presentan como pruebas propias de SPEC-003 o de esta fase.
Referencia de código observada: commit `c1165` (zona inicial); el árbol estaba limpio.

## Comportamiento implementado

Rutas relativas a `/catalog`:

| Método | Ruta | Resultado |
|---|---|---|
| POST | /restaurants/{restaurantId}/shifts | 201 con cuerpo, Location y ETag; requiere Idempotency-Key. |
| GET | /restaurants/{restaurantId}/shifts | 200 con items/revision y ETag; vacío si no hay turnos. |
| GET | /restaurants/{restaurantId}/shifts/{shiftId} | 200 con snapshot y revisión; 404 para id inexistente/ajeno bajo dueño autorizado. |

Request estricto: solo localStart/localEnd strings con fecha explícita y segundos
`YYYY-MM-DDTHH:mm:ss`. No acepta null, números, zona del cliente ni campos extra.
Errores de estructura son 400; fechas/formatos/zonas/interpretaciones inválidas 422.
Es obligatorio configurar zona antes del alta; no se usa la zona del servidor.

ZoneRules debe devolver exactamente un offset en cada extremo: se rechazan horas
inexistentes y repetidas sin ajustar. Fin debe ser posterior al inicio efectivo;
inicio debe ser estrictamente posterior a Context.now (igual o pasado→409
SHIFT_ALREADY_STARTED). Medianoche exige fecha final explícita; no se infiere día.
El intervalo guardado conserva locales, zona y startInstant/endInstant UTC.

La detección de superposición usa `inicioA < finB && finA > inicioB` bajo el
coordinador existente y consulta todos los turnos del restaurante, incluida historia.
Adyacencia es válida; superposición devuelve 409 SHIFT_OVERLAP y revierte revisión,
recurso y recibo. El índice no único `(restaurantId,startInstant,endInstant)` ayuda
la consulta; la garantía concurrente procede de la revisión serializada/transacción.
GET lee snapshot y representa la zona histórica sin depender de la configuración actual.

Se reutilizan permisos, guard CREATE_OPERATIONAL, lector legacy, UUID estándar,
receipts tipados, límites de tres intentos/cinco segundos y errores comunes. El
UUID del POST se genera una sola vez fuera del callback reintentable. Replay
devuelve cuerpo/estado/Location/ETag originales sin incrementar revisión, incluso
tras otro comando o después de que el turno haya pasado a ser histórico.

No se implementa PUT de turnos ni cambio de zona con turnos persistidos. Este
último conserva la barrera temporal 503 de fase 3 hasta HU-03. No se modifica el
gate compartido ni se habilita una entrega parcial operativamente.

## Pruebas redactadas y compiladas — no ejecutadas

| Tarea / RF | Archivo | Casos preparados |
|---|---|---|
| T069 / RF-03.2 | AvailabilityShiftValidatorTests | Medianoche, fin no posterior, fecha inválida, segundos obligatorios, gap/overlap de DST, falta de zona e inicio igual/anterior/posterior al reloj fijo. |
| T070 / RF-03.3 | AvailabilityShiftOverlapIT | Adyacencia entre fechas, superposición y ausencia de parciales; zona no configurada. |
| T071 / RF-03.4 | AvailabilityShiftReadTests | Lista vacía, aislamiento por recurso/propietario, snapshot conservado con zona actual diferente y tras el fin del turno, replay histórico. |
| T072 / RF-03.6 | AvailabilityShiftConcurrencyIT | Dos altas superpuestas no se confirman ambas; agotamiento acotado admisible, reintento posterior confirma solapamiento y no deja parciales. |
| T073 / RF-03.7 | AvailabilityShiftFailureIT | Fallo/demora de comprobación, rollback y reintento con misma clave. |
| T074 / RF-03.8 | AvailabilityShiftLegacyIT | Legado string/BSON conserva consulta/historia y bloquea alta sin adaptar o borrar reservas. |
| T080 / HTTP | AvailabilityShiftHttpTests ampliada | POST/GET, Location/ETag/instantes, permisos, request estricto, cabecera requerida, errores/Retry-After y ausencia de PUT de turnos. |

AvailabilityShiftIntegrationSupport extiende el soporte existente: registra solo
componentes locales y reutiliza lector controlado de zona, reloj y Mongo efímero.
El contexto de AvailabilityTimeZoneIT incorpora el nuevo validador por wiring;
sus aserciones y limpieza exacta del huérfano se conservan. No se recrean fixtures,
coordinador, Clock, transacciones o tarea Gradle; no se toca Mongo local de 27018.

## Validación — PowerShell

Desde SpringWebFlux, cada comando en una línea; Docker disponible para integración:

```powershell
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Availability*' --tests '*ReservationCrudServiceImplTests'
.\gradlew.bat integrationTest
```

Revisar descubrimiento de las clases nuevas, incluida AvailabilityShiftReadTests
aunque no termine en IT. Los informes 202/101 anteriores no acreditan esta fase;
no se fijan conteos nuevos ni se marca aceptación hasta la ejecución del usuario.

## Git Bash — únicamente si todo pasa

```bash
git add src/main/java/com/brenis/SpringWebFlux/ src/test/java/com/brenis/SpringWebFlux/handlers/AvailabilityShiftHttpTests.java src/test/java/com/brenis/SpringWebFlux/validators/AvailabilityShiftValidatorTests.java src/integrationTest/java/com/brenis/SpringWebFlux/services/AvailabilityShift*.java src/integrationTest/java/com/brenis/SpringWebFlux/services/AvailabilityTimeZoneIT.java README.md docs/disponibilidad-turnos.md docs/disponibilidad-zona-horaria.md
git diff --cached --check
git diff --cached --stat
git commit -m "feat: register and query restaurant shifts"
```

Los archivos SDD permanecen fuera del Git del servicio. No se avanza a fase 5
ni se cierra SPEC-003 con esta entrega.
