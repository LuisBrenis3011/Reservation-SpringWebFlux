# Consulta pública de disponibilidad — SPEC-004 fase 3

T133–T141 implementadas/pruebas redactadas, pendientes de compilación y suites del
usuario. No se ejecutaron recorridos HTTP ni se activó el gate; fase 4 pendiente.

GET `/catalog/restaurants/{restaurantId}/availability?date=YYYY-MM-DD&partySize=2`
devuelve restaurante, fecha, grupo, observedAt e items del contrato. No muestra
mesas, titulares, reservas, recibos, revisión global ni ETag de una reserva.
Solo lista turnos cuyo inicio es estrictamente futuro y cuya fecha local de inicio
coincide, aunque terminen al día siguiente. Fuera de la ventana de reserva siguen
visibles. Solo OPEN+AVAILABLE permite reservable=true.

Usa selector, plazos y lector de ocupación existentes de 005. Ocupación bloqueada
produce UNDETERMINED; oferta comprobada sin opción produce UNAVAILABLE. Un error
de ocupación sale de la transacción y se espera su rollback antes de una segunda
lectura snapshot de oferta, sin volver a consultar ocupación. Si esa oferta falla,
se responde 503; nunca lista vacía para ocultar el fallo.

Decisión de integración: `readSnapshot` del coordinador llama ensureInitialized y
puede hacer upsert de metadatos. Para cumplir GET sin escrituras se reutiliza
directamente el TransactionalOperator existente, su aislamiento snapshot y presupuesto,
con Clock UTC y repositorios reactivos. No se creó otro coordinador ni gestor de
transacciones. La existencia del restaurante se lee dentro de la sesión; no se
crea restaurant_operations al consultar. Esta diferencia respecto al plan inicial
queda registrada expresamente, sin cambiar el contrato ni los componentes compartidos.

## Trazabilidad de las pruebas redactadas

| RF / escenarios | Prueba |
|---|---|
| RF-04.1, ESC-04.1/2 | ReservationAvailabilityTests y ReservationAvailabilityIT: grupo, fecha local y medianoche |
| RF-04.2, ESC-04.3/4 | ReservationAvailabilityIT: mesa frente a combinación compartida |
| RF-04.3, ESC-04.5/6/11/12 | Pruebas de ventana inclusiva, visibles fuera de plazo y HTTP público con parámetros estrictos |
| RF-04.4, ESC-04.7/8 | ReservationAvailabilityFailureIT: matriz U1; ReservationAvailabilityFallbackTests: segunda transacción después de rollback |
| RF-04.5, ESC-04.9/10 | ReservationAvailabilityConcurrencyIT: no crea metadata ni recibos; otro cliente confirma y el primero debe reevaluar |

Las IT reutilizan el contexto efímero de reservas, sin conexión al Mongo local.
Fixtures ajenas creadas por la matriz U1 se eliminan por ID exacto en finally;
el soporte existente limpia únicamente el restaurante propio del ensayo.
Los comandos, XML y resultados de SPEC-005 son evidencia heredada, no validación
automática de estos archivos. No se consultó Git ni se ejecutó compilación o suites.

## Validación manual

```powershell
Set-Location '<WORKSPACE>\SpringWebFlux'
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Reservation*' --tests '*Availability*'
.\gradlew.bat integrationTest
```

Después de recibir resultados se prepara T142; no ejecutar ahora identidad, corte
o activación para validar estas suites. SPEC-004 permanece abierta.
