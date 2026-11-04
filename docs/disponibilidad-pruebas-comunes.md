# Pruebas comunes — T005 y T006

Las pruebas comunes ya compilan con los componentes de la fase 2. No se ejecutaron suites. Ver [guía vigente](disponibilidad-fase2.md) para entorno y comandos.

## Archivos y cobertura

| Archivo | Verifica | Componentes de fase 2 |
|---|---|---|
| AvailabilitySecurityTests | Pertenencia/roles y validación issuer, audiencia, exp/nbf, sub con Clock fijo | RestaurantAccessPolicy, AvailabilitySecurityConfig (T014) |
| AvailabilityHttpSupportTests | Clave, If-Match fuerte, 503/Retry-After y error sin secretos | AvailabilityException, CommandMetadata, AvailabilityHttpSupport (T008/T015) |
| AvailabilityCommitmentReaderTests | UUID string/binario, estados por case, legado sin fin fiable, huérfanos, fin exacto y timeout de comprobación | CommitmentSummary y LegacyReservationCommitmentAdapter (T012) |
| AvailabilityCoordinatorIT | Mongo real: rollback, snapshot coherente, replay/concurrencia, revisión obsoleta, tres intentos, presupuesto total y commit incierto | T007–T011, T016 y preparación T088 |
| AvailabilityLegacyWriterIT | create/update/delete del servicio real, conservación de revisión ante rechazo, carrera con configuración y condiciones de arranque | Coordinador, inicializador/guard y writer integrado (T013/T016/T017) |

AvailabilityIntegrationConfiguration es exclusivamente configuración de pruebas:
template, factory y manager comparten Mongo aislado; snapshot/majority/primary;
repositorios reales y solo Planner simulado (no HTTP/Redis). No carga la aplicación
principal ni su CommandLineRunner. Cada contexto dispone de su propia base y
contenedor. Los fallos de commit se inyectan con configureFailPoint en ese contenedor,
nunca en el Compose o Mongo local. El fixture mantiene el comportamiento anterior
por defecto y agrega modo standalone para comprobar el rechazo del entorno.

## Firmas de colaboración fijadas por las pruebas

Estas firmas concretan las interfaces generales del plan para la siguiente fase;
no constituyen endpoints ni un contrato público adicional. Mantenerlas o adaptar
los tests justificadamente al concretar T008/T010, preservando todas las aserciones.

- RestaurantAccessPolicy.requireManager(JwtAuthenticationToken, UUID) retorna Mono<Void>.
  El rechazo conserva el código FORBIDDEN en el mensaje de la excepción de dominio.
- AvailabilitySecurityConfig.jwtValidator(AvailabilityProperties, Clock) retorna
  OAuth2TokenValidator<Jwt>. El test valida claims directamente, no verifica firmas;
  la verificación criptográfica se añade al decoder en T014, sin usar mockJwt para ella.
- AvailabilityHttpSupport(Clock): metadata(ServerRequest, boolean update) devuelve
  CommandMetadata; error(Throwable) devuelve Mono<ServerResponse>. La extracción
  inicial de headers no necesita un fingerprint calculado antes de leer el body.
- AvailabilityException(String code, String message) conserva un código reconocible
  en getMessage(), sin exponer errores inesperados en el JSON de respuesta.
- CommandMetadata(String idempotencyKey, String fingerprint, Long expectedRevision,
  int httpStatus, String location) es record anidado en AvailabilityHttpModels.
  expectedRevision=null en POST. HttpStatus/Location representan el éxito original.
- RestaurantOperationCoordinator.write(UUID, Class<T> responseType, CommandMetadata, Function<Context,Mono<T>>)
  y readSnapshot(UUID, Function<Context,Mono<T>>) retornan Mono<Result<T>>; Result
  tiene body() y revision(), conserva estado/Location y usa igualdad por valor para replay.
  El callback usa el template vinculado al contexto Reactor de la misma sesión.
- LegacyReservationCommitmentAdapter(ReactiveMongoTemplate).read(UUID,Instant)
  retorna Mono<CommitmentSummary>, con legacyBlocked(), globalBlocked(),
  protectedTableIds() y protectedShiftIds(). Consulta Document crudo en reservations;
  los mocks no filtran por restaurante: el lector debe aislar/normalizar y detectar
  huérfanos globales. Timeout de la comprobación: 3 s, error COMMITMENT_CHECK_UNAVAILABLE.
- El inicializador valida infraestructura al refrescar el contexto: standalone se
  rechaza incluso con gate=false; replica set con gate=false no exige emisor;
  gate=true sin issuer se rechaza. No conectar estos contextos a datos reales.

## Ejecución por el usuario

Componentes implementados y compilados; no se ejecutaron suites ni se eliminaron aserciones para obtener verde. Desde PowerShell en SpringWebFlux:

```powershell
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*AvailabilitySecurityTests' --tests '*AvailabilityHttpSupportTests' --tests '*AvailabilityCommitmentReaderTests'
.\gradlew.bat integrationTest --tests '*AvailabilityCoordinatorIT' --tests '*AvailabilityLegacyWriterIT'
.\gradlew.bat test
```

Integración requiere Docker y puede tardar por los contextos adicionales de arranque.
Los casos de presupuesto total/commit incierto admiten hasta 8/15 segundos; no usar
un filtro vacío o NO-SOURCE como evidencia. Los tests HTTP de rutas reales y firmas
JWT se completan con T014/T015 y las historias; estas pruebas comunes no acreditan
endpoints implementados ni los 60 escenarios funcionales del lote.
