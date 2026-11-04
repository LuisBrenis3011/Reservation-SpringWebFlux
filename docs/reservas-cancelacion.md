## H1–H3 preparados — 2026-11-02

Comparadores, continuidad/recuperación del checkpoint y conservación de nueva
confirmación corregidos. Pendientes de comprobaciones puras por el usuario:
powershell.exe -NoProfile -File .\scripts\dev\Test-ReservationCancellationAssertions.ps1
y node --check sobre ambos helpers Mongo. Solo sintaxis PowerShell 5.1 inspeccionada.
Checkpoint nuevo schema 2; cualquier checkpoint anterior se conserva/rechaza.
No ejecutar aún HTTP; T129 pendiente. T191 abierta; SPEC-008 15/16, lote 94/103.
Detalle en docs/reservas-cancelacion-validacion.md del servicio.

---

## T189 preparado — 2026-11-02

SPEC-008 **14/16** tareas; lote **93/103**. T190–T191 abiertas, sin aprobación ni cierre.
Ejecuciones comunicadas por el usuario: compilación y selección exitosas; integración
mostró BUILD SUCCESSFUL en 2m19s y después error de comunicación con daemon.
La posterior integrationTest --no-daemon terminó correctamente, con 7 up-to-date:
reutilizó resultados y no repitió pruebas. Inspección del agente: XML seleccionados
275 e integración 210, cero fallos, errores u omitidas. No atribuir al agente ejecuciones.

Script preparado: scripts/dev/Test-LocalReservationCancellation.ps1. Helper Mongo
mongo-cancellation-manifest.js de solo lectura; compara documentos ajenos, índices,
opciones, historia/asignación, revisión, versión y recibo. Transporte JSON Base64.
Checkpoint propio por modo, bloqueo exclusivo y reemplazo atómico compatible con
Windows PowerShell 5.1. Intenciones/identidades congeladas antes de escribir; JWT
solo en memoria. Un fallo se reintenta con el mismo checkpoint y clave.

### Antes de ejecutar (no están acreditados por preparar T189)

T129 sigue pendiente. Primero completar las cinco funcionalidades y sus controles,
fijar SHA/JAR de versión puente que preserve modelo v2 y retiro de escrituras antiguas,
verificar respaldo restaurable y política persistente de corte. Preparar identidades
CUSTOMER_A, CUSTOMER_B, encargado A/B y sin rol. Solo después el responsable habilita
manualmente RESERVATIONS_ENABLED=true con AVAILABILITY_ENABLED=true y reinicia
IntelliJ 8082. Apagar rutas no revierte el corte persistente. Este trabajo no activa nada.

Usar una reserva confirmada propia de cliente-a, dedicada y ausente de otros
checkpoints, con inicio a más de 2h+5min, dentro de los 90 días y capacidad para volver
a confirmar el mismo grupo. No ejecutar otros escritores durante el ensayo.
El recorrido cancela esa reserva y crea otra, sin borrar la anterior. Ambas se conservan.
NearStartReservationId opcional debe ser otra reserva dedicada, propia, entre 5min y
2h antes del inicio: verifica rechazo del cliente y aceptación del encargado. Si falta,
ese recorrido temporal queda pendiente; bordes exactos solo tienen evidencia automatizada.

Comandos de una línea desde <WORKSPACE>\SpringWebFlux, únicamente
cuando se hayan satisfecho los prerrequisitos (sustituir UUID antes de ejecutar):

```powershell
& .\scripts\dev\Test-LocalReservationCancellation.ps1 -ReservationId 'UUID-RESERVA-DEDICADA' -NearStartReservationId 'UUID-RESERVA-CERCANA' -AllowFixtureWrites -AllowDatabaseReads -DedicatedReservations -ActivationPrerequisitesConfirmed
```

Reanudar con los mismos parámetros e identidades (renovar tokens en la misma terminal
si expiran). No borrar checkpoint ni cambiar claves para superar errores.
Al terminar, reiniciar manualmente Eats Hub en IntelliJ, mantener puerto/gates y ejecutar:

```powershell
& .\scripts\dev\Test-LocalReservationCancellation.ps1 -AfterRestart -AllowDatabaseReads -ActivationPrerequisitesConfirmed
```

### Q4 independiente

No mezclar una reserva bajo bloqueo global con el recorrido de nueva confirmación:
el bloqueo impediría reservar de nuevo. Usar otra reserva dedicada de cliente-a,
verificable, cuyo turno futuro muestre UNDETERMINED por un bloqueo general real ya
preparado/autorizado por separado. El script no crea legado ni simula fallos.
Q4Only exige el mismo UUID en ambos parámetros; tiene checkpoint propio separado.

```powershell
& .\scripts\dev\Test-LocalReservationCancellation.ps1 -Q4Only -ReservationId 'UUID-RESERVA-Q4' -Q4ReservationId 'UUID-RESERVA-Q4' -AllowFixtureWrites -AllowDatabaseReads -DedicatedReservations -ActivationPrerequisitesConfirmed
```

Tras el reinicio manual de ese ensayo:

```powershell
& .\scripts\dev\Test-LocalReservationCancellation.ps1 -Q4Only -AfterRestart -AllowDatabaseReads -ActivationPrerequisitesConfirmed
```

### Límites de evidencia

Preparación y análisis de sintaxis solamente. No se ejecutaron HTTP, Docker, suites,
servicios ni acciones Git. Sin fixtures no se acredita Q4 ni el plazo cercano.
Carrera reproducible edición/cancelación cubierta por las IT ejecutadas por el usuario;
no se acredita una carrera HTTP real con este script secuencial. Cancelación repetida
fuera del plazo, corrupción propia y fallos globales inducidos tienen pruebas automatizadas;
no se provocan esos fallos en el entorno local. Recorridos, reinicio, gates,
respaldo/restauración y reversión específicos siguen pendientes de evidencia en T191.
T190 revisará trazabilidad y estas limitaciones; no se declara completada aquí.

---
# Cancelación de reservas — fase 3

## Estado vigente — fase 3 SPEC-008, 2026-11-02

T178–T188 implementadas: SPEC-008 **13/16**, lote **92/103**.
Compilación y suites pendientes del usuario. No hay aprobación ni cierre.
Se reutilizan infraestructura, Clock y fixtures. Q4 comprueba únicamente la propia
reserva, sin guard ni lector global. Cancelar conserva el historial y libera por
estado en la misma transacción del recibo. Repetir autorizadamente usa noChange:
sin nueva versión ni revisión; una clave nueva guarda solo un recibo técnico.

Se redactaron 7 pruebas unitarias/HTTP y 19 de integración, incluida la ampliación
de ReservationReplaceConcurrencyIT. Recuento estático, no resultados ejecutados.
Incluyen ambos órdenes edición/cancelación con conflicto real sincronizado,
configuración concurrente y ciclo consulta→confirmación→edición→cancelación→nueva
confirmación. No se ampliaron presupuestos/reintentos. H1–H3 de SPEC-007 no quedan
aprobados por estos cambios. T189–T191 siguen abiertas; gate sin activar.

Validación manual desde <WORKSPACE>\SpringWebFlux:

```powershell
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Reservation*' --tests '*Availability*'
.\gradlew.bat integrationTest
```

No se ejecutaron compilaciones, suites, HTTP, servicios, Docker ni acciones Git.
Recorridos HTTP, reinicio, gates, respaldo/restauración, reversión y aprobación
seguirán pendientes hasta contar con evidencia específica.

---
Trazabilidad redactada: RF-08.1/ESC-08.1–2 en ReservationCancellationHttpTests y ReservationCancellationTimeTests; RF-08.2/ESC-08.3–4 en ReservationCancellationIT; RF-08.3/ESC-08.5–6 en ReservationCancellationNoopIT; RF-08.4/ESC-08.7–8 en ReservationCancellationConcurrencyIT; RF-08.5/ESC-08.9–12 en ReservationCancellationFailureIT. ReservationCancellationContractIT verifica el endpoint con seguridad real de prueba. ReservationLifecycleIT y ReservationReplaceConcurrencyIT completan T188.

POST /restaurants/{restaurantId}/reservations/{reservationId}/cancellation no admite cuerpo y exige Idempotency-Key e If-Match. Devuelve 200 y ETag de recurso, sin Location. El replay conserva respuesta original y vuelve a comprobar permisos e integridad propia. Primera transición condicionada a CONFIRMED y versión esperada; sin borrado físico. Historia, asignación y snapshots permanecen. La actualización y el recibo son atómicos; los índices de confirmadas liberan ocupación y unicidad activa al commit.
