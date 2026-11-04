# SPEC-002 — Fase 3: registrar y consultar combinaciones

Registro histórico de T043–T054. El responsable confirmó el 2026-10-27:
164 pruebas seleccionadas y 68 de integración, sin fallos, errores ni omitidas;
commit `61284` (`6128494773deac25e76a4fdced539210481efefa`).
Es evidencia comunicada por el usuario, sin una nueva ejecución del agente.
La ampliación PUT posterior está documentada en
[fase 4](disponibilidad-combinaciones-put.md), con suites todavía pendientes.
Esta guía conserva el alcance y la revisión de la entrega original; no cierra SPEC-002.

## Comportamiento implementado

Base local: http://localhost:8082/catalog, cuando el responsable arranque la app.

| Operacion | Ruta relativa a /catalog | Resultado |
|---|---|---|
| POST | /restaurants/{restaurantId}/table-combinations | 201, cuerpo, Location y ETag; requiere Idempotency-Key. |
| GET | /restaurants/{restaurantId}/table-combinations | 200, items y revision; ETag comun. |
| GET | /restaurants/{restaurantId}/table-combinations/{combinationId} | 200 o 404 bajo restaurante autorizado. |

Request unico: tableIds, array de al menos dos strings UUID propios y distintos.
Sin campos extra, null, coerciones ni capacidad editable. La respuesta contiene
id, restaurantId, tableIds, capacity y revision; la lista tiene solo items/revision.
En esta entrega original, PUT no estaba registrado y la interfaz reservaba replace.
La fase 4 incorpora su implementación reutilizando estos componentes.

Se normalizan UUID y se ordenan lexicograficamente por su representacion canonica.
memberKey une esos UUID con coma. El indice unico (restaurantId,memberKey) evita
duplicados aunque se invierta el orden; combinaciones distintas pueden compartir mesas.
No se persiste capacity en table_combinations: cada GET la deriva de las mesas
vigentes dentro del snapshot comun, con suma exacta int64. Una referencia almacenada
que no se puede resolver rechaza la lectura completa con 503, sin suma parcial.
Un desbordamiento de suma devuelve VALIDATION_ERROR 422.

El recibo de idempotencia SI conserva el cuerpo historico de respuesta, incluida
su capacidad de ese momento. Replay devuelve ese cuerpo, estado, Location y ETag;
GET refleja capacidades actuales. El replay no vuelve a guardar ni cambia revision.

POST reutiliza RestaurantOperationCoordinator y guard CREATE_OPERATIONAL, con UUID
generado una sola vez fuera del callback. Las consultas a integrantes son secuenciales
con concatMap para no ejecutar operaciones paralelas en la misma sesion Mongo.
GET usa readSnapshot; no hay nueva cache ni llamadas HTTP/Redis dentro de la transaccion.
El contribuidor local crea solo su coleccion/indice usando IndexContributor existente;
no se modificaron inicializador, coordinador, seguridad, guard, build ni fixtures comunes.

## Pruebas de fase 3 — ejecución confirmada por el usuario

| Archivo | Cobertura de HU-01 |
|---|---|
| AvailabilityCombinationHttpTests | RF-02.1: permiso, ausencia de token/rol y actor ajeno; esquema, cabeceras, codigos y gate. En fase 3 se comprobaba ausencia de PUT; fase 4 amplía esta clase. |
| AvailabilityCombinationValidatorTests | RF-02.2: conjunto canonico, duplicados, UUID/cardinalidad, pertenencia; RF-02.3: suma e int64. |
| AvailabilityCombinationReadTests | RF-02.1/02.2/02.3: alta, capacidad vigente en combinaciones solapadas, vacio, aislamiento, datos invalidos y referencias no resolubles. |
| AvailabilityCombinationConcurrencyIT | RF-02.5: carrera de altas, indice real y snapshot; replay tipado despues de cambiar capacidad. |
| AvailabilityCombinationFailureIT | RF-02.6: dependencia fallida/demorada, rollback y reintento con misma clave. |
| AvailabilityCombinationLegacyIT | RF-02.7: consulta durante legado y bloqueo sin modificar reservas, UUID BSON/string y fin no verificable. |

Los RF/escenarios de modificación no formaban parte de esta validación de HU-01;
las pruebas PUT añadidas en HU-02 requieren una nueva ejecución del usuario.
FailureIT sustituye solo el lector fallido por un doble controlado, conservando
Mongo/transacciones reales. La prueba de concurrencia admite agotamiento acotado
de los tres intentos, verifica ausencia de parciales y reintenta despues de la
competidora; no aumenta presupuestos para forzar un resultado.

AvailabilityCombinationIntegrationSupport es pegamento local de SPEC-002: extiende
AvailabilityTableIntegrationSupport y sus fixtures de SPEC-001, sin otra configuracion
Mongo o coordinador. Usa restaurantes/mesas aleatorios en bases efimeras.
Los DELETE/insert directos que construyen datos de borde ocurren solo en fixtures,
nunca en la base local de 27018 ni como nuevos endpoints de negocio.

## Validacion manual — PowerShell

En la raiz del servicio, compilacion sin suites (puedes repetirla en tu terminal):

~~~powershell
Set-Location <WORKSPACE>\SpringWebFlux
~~~

~~~powershell
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
~~~

Despues ejecutar la seleccion unitaria/HTTP y regresiones compartidas:

~~~powershell
.\gradlew.bat test --tests '*Availability*' --tests '*ReservationCrudServiceImplTests'
~~~

Con Docker Desktop disponible, ejecutar integracion completa en contenedores efimeros:

~~~powershell
.\gradlew.bat integrationTest
~~~

Comprobar descubrimiento de las seis clases nuevas de pruebas (dos en test y cuatro
en integrationTest), sin failures/errors/skipped; informes en build/test-results y
build/reports/tests. AvailabilityCombinationReadTests debe descubrirse aunque su
nombre no termine en IT. Los 138/52 del cierre de SPEC-001 son historicos; los nuevos
conteos requieren una ejecucion del usuario. NO-SOURCE no acredita nada.

Revision realizada por el agente: lectura de contrato/propiedad de componentes,
parse sintactico de 19 archivos Java con el JDK, rutas y diff. Posteriormente el
comando compileJava/compileTestFixturesJava/compileTestJava/compileIntegrationTestJava
finalizo BUILD SUCCESSFUL en 17 s. Main y fixtures estaban UP-TO-DATE; las fuentes
test e integrationTest se compilaron en esa ejecucion. Esto comprueba compilacion,
no wiring Spring en ejecucion ni reglas de negocio: ninguna suite se ejecuto.
No se reutilizan XML antiguos como evidencia de HU-01 ni se afirma que las nuevas
pruebas pasen hasta que el usuario las ejecute. Esta última limitación describe
la entrega inicial: posteriormente el usuario confirmó los resultados registrados
al principio de esta guía. No acredita las ampliaciones de fase 4.

## Git Bash — solo si todo pasa

~~~bash
git add src/main/java/com/brenis/SpringWebFlux/collections/TableCombinationCollection.java src/main/java/com/brenis/SpringWebFlux/configs/TableCombinationIndexesContributor.java src/main/java/com/brenis/SpringWebFlux/dtos/requests/TableCombinationRequest.java src/main/java/com/brenis/SpringWebFlux/dtos/responses/TableCombinationResponse.java src/main/java/com/brenis/SpringWebFlux/dtos/responses/TableCombinationListResponse.java src/main/java/com/brenis/SpringWebFlux/repositories/TableCombinationRepository.java src/main/java/com/brenis/SpringWebFlux/validators/TableCombinationValidator.java src/main/java/com/brenis/SpringWebFlux/mappers/TableCombinationMapper.java src/main/java/com/brenis/SpringWebFlux/services/definitions/TableCombinationService.java src/main/java/com/brenis/SpringWebFlux/services/impls/TableCombinationServiceImpl.java src/main/java/com/brenis/SpringWebFlux/handlers/TableCombinationHandler.java src/main/java/com/brenis/SpringWebFlux/routes/TableCombinationRouter.java
git add src/test/java/com/brenis/SpringWebFlux/handlers/AvailabilityCombinationHttpTests.java src/test/java/com/brenis/SpringWebFlux/validators/AvailabilityCombinationValidatorTests.java src/integrationTest/java/com/brenis/SpringWebFlux/services/AvailabilityCombinationReadTests.java src/integrationTest/java/com/brenis/SpringWebFlux/services/AvailabilityCombinationConcurrencyIT.java src/integrationTest/java/com/brenis/SpringWebFlux/services/AvailabilityCombinationFailureIT.java src/integrationTest/java/com/brenis/SpringWebFlux/services/AvailabilityCombinationLegacyIT.java src/integrationTest/java/com/brenis/SpringWebFlux/support/AvailabilityCombinationIntegrationSupport.java
git add README.md docs/disponibilidad-combinaciones.md
git diff --cached --check
git diff --cached --stat
git commit -m "feat: register and query allowed table combinations"
~~~

Los documentos SDD permanecen fuera del repositorio; no agregar secretos ni backups.
Este commit agrupa una historia coherente y sus pruebas, no un commit artificial
por cada tarea que aun no compilaria por separado. La fase 4 no se inicia aqui.
