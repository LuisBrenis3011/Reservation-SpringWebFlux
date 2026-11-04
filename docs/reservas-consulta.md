# Consultas autorizadas y legado — SPEC-006 fase 3

Corrección H1–H3 preparada: autorización previa a buscar el detalle y pruebas nuevas
de paginación, contrato, seguridad y conservación. Compilación/suites pendientes del
usuario; no reutilizar los resultados anteriores como aprobación de esta revisión.
[Trazabilidad y límites](reservas-consulta-validacion.md). T160 y cierre pendientes.

Actualización T158, 2026-10-30: el usuario validó compilación y suites con
BUILD SUCCESSFUL. XML inspeccionados: 259 seleccionadas y 174 de integración,
sin fallos, errores ni omitidas. El recorrido HTTP/reinicio está preparado, no
ejecutado: `scripts/dev/Test-LocalReservationQueries.ps1`. Sus pasos y prerrequisitos
están en el quickstart externo de SPEC-006, sección Estado vigente T158.
SPEC-006 14/16; T159–T160 y cierre pendientes. Lo siguiente conserva la entrega inicial.

T147–T157 implementadas o con pruebas redactadas. Compilación y suites pendientes
del usuario; no se acredita aún ejecución, HTTP real, activación ni cierre.

## Operaciones

- GET `/me/reservations`: CUSTOMER, filtro por issuer/sub y estado opcional. Una
  sola sesión snapshot por página, incluso con reservas de varios restaurantes.
- GET `/restaurants/{restaurantId}/reservations`: encargado autorizado, lista
  paginada de gestionadas y legado identificable del local.
- GET `/restaurants/{restaurantId}/reservations/{reservationId}`: cliente titular
  o encargado del local; devuelve snapshot histórico y ETag de versión.
- GET `/restaurants/{restaurantId}/reservations/legacy/{legacyRef}`: encargado del
  local; referencia Base64URL de EJSON canónico, proyección limitada y sin ETag.
- GET antiguo `/reservation/{id}`: adaptador protegido por rol y pertenencia al
  local, busca UUID BSON/string; nunca proyecta v2 mediante el DTO antiguo. Sigue
  disponible con gate nuevo apagado. Las escrituras antiguas conservan su barrera.

Listas: page>=0, size 1–100 y orden BSON por _id; sin total global ni ETag.
La proyección legado no incluye correo, customerId, identidad inferida ni campos
desconocidos. Huérfanas y documentos ajenos no se atribuyen a un local; v2 inválida
o versión no verificable no se presenta como legado. Error de lectura produce 503,
no una lista vacía artificial. No se modifican documentos ni metadata al consultar.

U2 reutiliza ReactiveMongoTemplate y TransactionalOperator de MongoConfig con una
transacción snapshot por página y presupuesto existente. No se llama a
ensureInitialized, no se usa un restaurante ficticio ni otro gestor. Las páginas
sucesivas no prometen el mismo snapshot. Fechas históricas se proyectan desde el
snapshot guardado, sin reinterpretarlas por la zona actual.

## Pruebas redactadas

| Requisito | Pruebas preparadas |
|---|---|
| RF-06.1, ESC-06.1/2 | ReservationQueryHttpTests, ReservationRestaurantQueryIT y ReservationSnapshotQueryIT: CUSTOMER/dual, dos locales, otro titular y 404. |
| RF-06.2, ESC-06.3/4 | ReservationRestaurantQueryIT: encargado local y rechazo de local ajeno. |
| RF-06.3, ESC-06.5/6 | ReservationSnapshotQueryIT: zona histórica, fixture cancelada sin ocupación; cursor de lote 1 y escritura competidora fuera de la sesión. |
| RF-06.4, ESC-06.7/8/11 | ReservationLegacyQueryIT y ReservationLegacyProjectionTests: legado local, correo no vinculado, huérfana, referencia opaca y GET antiguo UUID string. |
| RF-06.5, ESC-06.9/10 | ReservationQueryFailureIT: vacío real sin metadata/recibos, fallo Mongo y v2 inválida; conservación en ReservationRestaurantQueryIT. |

El cursor controlado usa los componentes del Mongo efímero existente y elimina
solo IDs creados por el ensayo. Los failpoints se apagan en finally. Las fixtures
canceladas son datos de prueba; no implementan el comando de SPEC-008.

## Validación y límites

No se ejecutaron compilación, suites, HTTP, servicios, Docker o Git durante esta
entrega. No se cambió OpenAPI ni se activó el gate. Las pruebas y escenarios se
consideran preparados, no aprobados; el usuario debe confirmar sus resultados.

```powershell
Set-Location '<WORKSPACE>\SpringWebFlux'
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Reservation*' --tests '*Availability*'
.\gradlew.bat integrationTest
```

SPEC-006 sigue sin cierre. T158–T160, HTTP/reinicio/gates, respaldo, reversión y
aprobación formal están pendientes. El bridge y corte requieren evidencia y
dependencias posteriores: no activar ni ejecutar el corte con esta entrega.
