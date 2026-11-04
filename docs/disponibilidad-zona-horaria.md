# SPEC-003 — Fase 3: zona horaria inicial

**Actualización posterior:** el usuario confirmó integración completa exitosa;
se contaron 101 casos sin incidencias. Existe además un informe anterior de test
con 202 casos sin incidencias, sin atribuirle una ejecución nueva confirmada.
La fase 4 incorpora POST/GET de turnos: [estado vigente y comandos](disponibilidad-turnos.md).
Los párrafos siguientes son historial de la entrega de fase 3 y su corrección.

T063–T068 implementadas/redactadas el 2026-10-28. GET/PUT de zona están preparados;
la compilación de fuentes y pruebas pasó. No se ejecutaron suites, servicios,
HTTP real, migraciones ni commits. SPEC-003 queda en 8/27 tareas; fase 4 sin iniciar.
La ejecución y aceptación de las pruebas nuevas siguen pendientes del usuario.

Corrección de aislamiento posterior: el ensayo de huérfano elimina únicamente
su fixture por _id exacto en finally, después de comprobar que el rechazo no
modificó datos. El lector controlado se restablece tras cada prueba. El fallo
previo del usuario dejó cuatro casos bloqueados por ese huérfano; no se modifica
el guard ni se limpian colecciones completas. La corrección está pendiente de
ejecución por el usuario y solo actúa dentro de la base efímera del IT.

## Alcance implementado

- GET `/catalog/restaurants/{restaurantId}/time-zone`: 200 con restaurantId,
  zoneId y revision; zona ausente devuelve null explícito, sin default inventado.
- PUT misma ruta: requiere Idempotency-Key e If-Match fuerte. Acepta exclusivamente
  zoneId como string, comprueba ZoneId reconocido y devuelve 200/ETag sin Location.
- Identidad de configuración `_id=restaurantId` en restaurant_time_zones. No se
  modifica restaurants ni se crean turnos o snapshots históricos.
- Coordinador/guard ZONE, permisos, revisión, recibos tipados y errores existentes.
  Nueva clave válida incrementa revisión una vez; replay devuelve respuesta
  original sin incremento. Se conserva el bloqueo legacy/global y de reservas protegidas.
- Si ya existe cualquier documento de turno propio en restaurant_shifts, PUT
  rechaza con 503 DEPENDENCY_UNAVAILABLE, incluso si la zona es equivalente,
  sin cambiar datos/revisión/recibos. Esta restricción técnica temporal evita
  habilitar cambios sobre turnos antes de HU-03; no es una nueva regla de negocio.

RestaurantShiftIndexesContributor prepara solo restaurant_time_zones mediante la
interfaz propietaria. El índice _id ya garantiza una zona por restaurante.
La lectura de turnos para bloquear PUT es una consulta directa acotada por dueño;
no implementa repositorio, DTO, POST, GET ni PUT de turnos de la fase 4.

No se cambiaron OpenAPI, coordinador, guard, seguridad, inicializador, Clock,
build, fixtures compartidos ni gate. No activar un despliegue parcial para cambio
de zona con turnos existentes. El gate compartido de mesas/combinaciones queda
sin tocar; los ensayos nuevos pertenecen al entorno de desarrollo y a bases efímeras.

## Pruebas redactadas, sin resultados de ejecución aún

| Archivo | Cobertura |
|---|---|
| AvailabilityShiftHttpTests | T063/T064: RF-03.1 ESC-03.1–03.2, zona null, GET/PUT, ETag, permisos previos al cuerpo, rol ausente, estructura estricta, cabeceras obligatorias y traducción de errores incluyendo 503/Retry-After y legado. Gate de zona y ausencia de rutas de turnos. |
| AvailabilityTimeZoneIT | Persistencia real y rollback con fixtures existentes; lectura sin zona, repetición, replay histórico tras otro write, conflicto de clave y revisión; zona inválida, reserva protegida, bloqueo por turnos persistidos, legado, huérfanos y fallo/demora con reintento de la misma clave. |

El IT reutiliza AvailabilityTableIntegrationSupport solo como soporte de Mongo,
identidad, reloj y propietario; el servicio productivo no depende del servicio
de mesas. El lector controlado falla/demora solo en ese contexto de pruebas,
delegando al adaptador real en los demás casos. No se introducen fallos en Mongo local.
No se afirma cobertura completa de RF-03.7/03.8 o de SPEC-003: se cubren sus casos
de zona inicial; los escenarios de turnos/cambio de zona con turnos esperan sus fases.

## Validación — PowerShell

Desde `<WORKSPACE>\SpringWebFlux`, cada comando en una línea:

```powershell
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Availability*' --tests '*ReservationCrudServiceImplTests'
.\gradlew.bat integrationTest
```

Docker Desktop debe estar disponible para integración. Revisar los XML e informes
de build/test-results y build/reports/tests: descubrir las dos clases nuevas,
sin fallos, errores ni omitidas. Los totales anteriores 184/91 no acreditan este
incremento; se registrará el conteo nuevo después de la ejecución del usuario.
No se necesita arrancar la app en IntelliJ para estos tests de contexto aislado.

## Git Bash — únicamente si todo pasa

```bash
git add src/main/java/com/brenis/SpringWebFlux/collections/RestaurantTimeZoneCollection.java src/main/java/com/brenis/SpringWebFlux/repositories/RestaurantTimeZoneRepository.java src/main/java/com/brenis/SpringWebFlux/configs/RestaurantShiftIndexesContributor.java src/main/java/com/brenis/SpringWebFlux/dtos/requests/RestaurantTimeZoneRequest.java src/main/java/com/brenis/SpringWebFlux/dtos/responses/RestaurantTimeZoneResponse.java src/main/java/com/brenis/SpringWebFlux/mappers/RestaurantShiftMapper.java src/main/java/com/brenis/SpringWebFlux/services/definitions/RestaurantShiftService.java src/main/java/com/brenis/SpringWebFlux/services/impls/RestaurantShiftServiceImpl.java src/main/java/com/brenis/SpringWebFlux/handlers/RestaurantShiftHandler.java src/main/java/com/brenis/SpringWebFlux/routes/RestaurantShiftRouter.java
git add src/test/java/com/brenis/SpringWebFlux/handlers/AvailabilityShiftHttpTests.java src/integrationTest/java/com/brenis/SpringWebFlux/services/AvailabilityTimeZoneIT.java docs/disponibilidad-zona-horaria.md README.md
git diff --cached --check
git diff --cached --stat
git commit -m "feat: configure initial restaurant time zone"
```

La documentación SDD externa no se añade al repositorio del servicio. Falta validar
esta fase; no se inicia T069 ni se acepta o cierra SPEC-003 automáticamente.
