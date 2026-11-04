# SPEC-007 — Modificación y reasignación de reservas

## Correcciones preparadas tras T174 — 2026-11-02

H1–H3 implementadas, pendientes de validación manual; ver
[detalle y comandos](reservas-modificacion-validacion.md).
NearStart conserva la intención aunque avance el tiempo; etapas ligadas a issuer/sub.
Pruebas concurrentes exigen conflicto Mongo real antes de liberar el primer callback.
PUT aceptados verifican invariantes, delta BSON permitido y conservación de datos
ajenos. Script sintético nuevo sin dependencias del entorno ni credenciales reales.
No se ejecutó ningún recorrido ni suite. Los XML anteriores no validan estos cambios.

Checkpoint con comparisonVersion=2; versiones antiguas con evidencia se conservan
y detienen para revisión explícita, sin sobrescritura ni reinicio automático.
La sintaxis válida no equivale a comprobar transporte, concurrencia o recuperación.
T175, activación integral, carrera con cancelación y cierre siguen pendientes.

## Resultado vigente de T174 — 2026-11-02

Revisión completada con tres brechas, detalladas en
[reservas-modificacion-validacion.md](reservas-modificacion-validacion.md): H1
reanudación de NearStart tras avanzar el tiempo, H2 solapamiento no demostrado en
concurrencia y H3 conservación insuficiente tras PUT aceptados en el script.
No ejecutar el recorrido antes de corregirlas y cumplir los prerrequisitos integrales.
Se conservan 268/191 XML exitosos, con ejecución atribuida al usuario; no se
repitieron suites. No hay evidencia HTTP operativa ni aprobación/cierre de SPEC-007.

## T173 — recorrido preparado, no ejecutado — 2026-11-02

El usuario confirmó prueba HTTP aislada, selección e integración exitosas tras
corregir las identidades. Inspección del agente de XML: **268 seleccionadas y 191
de integración**, cero fallos, errores y omitidas. Incluyen 8 unitarias/HTTP y 15 IT
nuevas de SPEC-007. Son ejecuciones del usuario; el agente no repitió suites.

Script preparado: `scripts/dev/Test-LocalReservationReplacement.ps1`. No se ha
ejecutado ningún recorrido. Checkpoint propio en
`secrets/local-identity/reservation-replacement-http-checkpoint.json`, sin JWT;
no reemplaza checkpoints de otros ensayos. Conserva claves/intenciones antes de
enviar, usa bloqueo exclusivo y guardado atómico; repetir tras respuesta perdida
usa la misma intención. No borrar el checkpoint, generar otra clave ni repetir
escrituras manualmente si aparece una discrepancia. Evitar otros escritores.

Validación del agente: análisis de sintaxis con el parser de Windows PowerShell
5.1.26100.9711, sin errores. Solo se analizó el archivo; no se invocó el script,
HTTP, Docker, servicios, suites ni acciones Git. No acredita comportamiento operativo.

### Prerrequisitos de ejecución futura

Primero completar/verificar las cinco funcionalidades del lote y T129 de 005:
corte persistente, versión puente compatible identificada, respaldo/restauración
aislada acreditados y activación integral autorizada. No activar el gate ahora.
El script exige `-ActivationPrerequisitesConfirmed`; es una declaración del
operador, no evidencia automática de cumplimiento ni permiso para cambiar gates.

Después de esa preparación, con Eats Hub en 8082, Mongo replica local 27018 y
Keycloak disponibles por ejecución manual, obtener en la misma PowerShell tokens
de cliente-a, cliente-b, encargado-a, encargado-b y cliente-dual mediante
Get-LocalToken.ps1. El script no renueva tokens ni configura usuarios.

Proporcionar tres UUID reales preparados durante el ensayo integral:

- ReservationId: confirmada v2 propia de cliente-a en A, dedicada a este recorrido,
  con inicio a más de 2h + 5min. No usar una reserva ligada a otro checkpoint.
- FreeShiftId: otro turno OPEN con disponibilidad suficiente para su grupo,
  sin otra confirmada de ese titular en destino.
- OccupiedShiftId: tercer turno OPEN cuya disponibilidad para ese mismo grupo
  sea UNAVAILABLE por ocupación conocida, sin duplicado del titular. Si el POST/PUT
  devuelve otro conflicto, revisar las fixtures; no declarar probado destino lleno.

El script lee oferta/disponibilidad antes de su primera escritura y rechaza
UNDETERMINED o datos inesperados. No crea mesas, turnos, reservas ni cambia zona.
Con permiso explícito modifica y conserva la reserva dedicada: notas y traslado
al turno libre. No restaura su turno anterior silenciosamente ni elimina datos.

Comando futuro, una línea (solicita UUID reales sin valores inventados):

```powershell
& .\scripts\dev\Test-LocalReservationReplacement.ps1 -ReservationId ([guid](Read-Host 'UUID reserva dedicada')) -FreeShiftId ([guid](Read-Host 'UUID turno libre')) -OccupiedShiftId ([guid](Read-Host 'UUID turno ocupado')) -AllowFixtureWrites -AllowDatabaseReads -DedicatedReservations -ActivationPrerequisitesConfirmed
```

Reanudación del mismo ensayo sin cambiar sus parámetros:

```powershell
& .\scripts\dev\Test-LocalReservationReplacement.ps1 -AllowFixtureWrites -AllowDatabaseReads -DedicatedReservations -ActivationPrerequisitesConfirmed
```

Prepara 401/403/404, PUT por titular y encargado, Q1, If-Match ausente/obsoleto,
destino ocupado, conflicto de clave, replay estricto de respuesta original después
de otra escritura y conservación de configuración. Rechazos/replay comparan
manifiestos completos antes/después. La revisión de oferta que cambia por escrituras
no se confunde con alteraciones materiales de configuración.

Opcional: indicar desde la primera invocación `-NearStartReservationId` con otra
confirmada propia/dedicada que empiece en más de 2min y menos de 2h. Prepara rechazo
del cliente y aceptación de la cuenta dual como encargado, conservando esa edición.
Sin esta fixture, el checkpoint deja temporalNearStart=false: ese caso HTTP queda
pendiente. Los extremos exactos 2h/90 días permanecen acreditados solo por pruebas
automatizadas; el script no manipula el reloj productivo ni inventa evidencia.

Una vez terminado el recorrido, detener/arrancar manualmente Eats Hub en IntelliJ
con la misma configuración y puerto 8082. En la misma PowerShell:

```powershell
& .\scripts\dev\Test-LocalReservationReplacement.ps1 -AfterRestart -AllowDatabaseReads -ActivationPrerequisitesConfirmed
```

Compara reserva final completa, asignación, snapshot, versión y ETag, y manifiesto
Mongo guardado. El reinicio es declarado por el usuario, no inferido por un GET.
Gates, respaldo/restauración, reversión, carrera con cancelación T188 y aprobación
siguen pendientes. T174 y T175 no se completan al preparar este script.

## Corrección de identidades de prueba — 2026-11-02

El usuario reportó 268 pruebas seleccionadas, con cuatro fallos de
ReservationReplaceHttpTests. El agente inspeccionó el XML: todos recibían 401
en lugar del estado esperado. La inspección del bytecode instalado confirmó que
el constructor JwtAuthenticationToken(Jwt) no establece authenticated=true;
el constructor con autoridades sí lo hace.

Se corrigieron cliente y encargado ajeno de esas pruebas y la identidad del
encargado con permiso retirado en ReservationReplaceReplayIT. Esta última conserva
issuer/sub y solo perfil/autoridad CUSTOMER, para comprobar rechazo por titularidad.
Se mantienen las aserciones, incluido 401 sin identidad. No se modificaron backend,
OpenAPI ni gates. Corrección pendiente de validación del usuario; el agente no
ejecutó compilación ni suites. T173 y entrega operacional siguen pendientes.

## Entrega de fase 3 — 2026-11-02

T163–T172 implementadas/pruebas redactadas. **Pendiente de compilación y ejecución
por el usuario**. No se ejecutaron suites, HTTP, Docker, servicios ni comandos Git.
El gate productivo y OpenAPI se conservan; no hay aprobación ni cierre de la spec.

PUT `/restaurants/{restaurantId}/reservations/{reservationId}` reutiliza el servicio
de comandos de SPEC-005. Exige identidad CUSTOMER titular o encargado del local,
Idempotency-Key y If-Match fuerte numérico. Permisos de perfil/local antes de buscar;
titular/local antes de recuperar un recibo y de nuevo en la sesión de escritura.
No recibe cambios de titular, restaurante ni mesas desde el cuerpo. Notes omitidas
se vacían, como indica el contrato de sustitución completa.

Una intención nueva comprueba versión, CONFIRMED, plazo original/destino por actor,
corte persistente, oferta, ocupación U1 y duplicado de titular excluyendo solo su
propia reserva. Q1 conserva asignación válida en el mismo turno; cambiar notas no
optimiza mesas. Si cambia turno o no alcanza, aplica el asignador existente.
Reserva, revisión local y recibo se confirman juntos o se revierten juntos.
Conserva id, restaurante, titular y createdAt. Un PUT equivalente nuevo incrementa
versión; un replay devuelve cuerpo/estado/ETag originales sin otra edición.
La versión del recurso y la revisión global del local son controles distintos.

## Trazabilidad de pruebas redactadas

| RF / escenarios | Archivos y comprobaciones preparadas |
|---|---|
| RF-07.1, ESC-07.1/2 | ReservationReplaceHttpTests: campos, notas, cabeceras, ETag y errores. ReservationReplaceRollbackIT: ajena, cancelada y legado; comparación de estado sin cambios. ReservationReplaceContractIT: cadena/router/handler/servicio reales en contexto efímero, 401/403/404, conservación. |
| RF-07.2, ESC-07.3/4 | ReservationReplaceTimeTests: 2h/90 días inclusivos y casos fuera de límite, inicio exacto del encargado, grupo 1–20. RollbackIT: cliente rechazado dentro de 2h, dual como encargado y rechazo al inicio. Clock se restaura en finally. |
| RF-07.3, ESC-07.5/6 | ReservationReassignmentIT: notas y grupo suficiente conservan mesas; combinación se conserva aunque baste una mesa; aumento reasigna. |
| RF-07.4, ESC-07.7/8 | ReassignmentIT: movimiento completo y origen reutilizable. RollbackIT: destino ocupado, duplicado, U1 con otro turno desconocido/snapshot discrepante/mesa desconocida incluso solo notas; fallo real de insert del recibo después de reemplazar, rollback íntegro y reintento. |
| RF-07.5, ESC-07.9/10 | ReservationReplaceConcurrencyIT: ediciones de misma versión, edición contra confirmación por destino y contra cambio de capacidad. Rechazo obsoleto conserva estado; errores de contención admitidos solo dentro del presupuesto existente. Carrera con cancelación pendiente T188. |
| RF-07.6, ESC-07.11/12 | ReservationReplaceReplayIT: replay tras otra edición/fuera de plazo, conflicto y pérdida de permiso de encargado conservando identidad. ContractIT verifica replay HTTP con ETag histórico después de otra escritura. |

ReservationReplacementSupport añade únicamente helpers sobre
ReservationConfirmationSupport/ManagedReservationIntegrationSupport e identidad
existentes. No crea otro Mongo ni configuración productiva. Compara documentos de
nueve colecciones e índices; las fixtures propias/failpoints/reloj se conservan o
limpian según el ámbito del ensayo. La integración usa Mongo efímero, nunca Mongo local.

Cobertura redactada y revisada: 6 RF / 12 escenarios. No equivale a cobertura
ejecutada ni a evidencia de carreras con cancelación. Las pruebas nuevas aún no
tienen XML atribuibles a esta fase. Los resultados previos 260/176 no las validan.

## Validación manual

Desde PowerShell, en `<WORKSPACE>\SpringWebFlux`, una línea
por comando. La aplicación puede permanecer detenida; Docker Desktop debe estar
disponible para Testcontainers al ejecutar integración.

```powershell
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Reservation*' --tests '*Availability*'
.\gradlew.bat integrationTest
```

Registrar autor, comando y resultado comunicados por el usuario, y contrastar XML
después de la ejecución. T173–T175, HTTP operativo/reinicio/gates, respaldo y
reversión siguen pendientes; la activación integral espera T129 de SPEC-005.
Ningún resultado de las specs anteriores se transfiere a esta entrega.
