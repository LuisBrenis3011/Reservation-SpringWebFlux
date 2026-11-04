## T188 preparado — 2026-11-02

Carreras reales edición/cancelación y ciclo integral añadidos en SPEC-008; pendientes de compilación y ejecución manual. No acreditan aprobación de H1–H3 ni T175.

# Revisión T174 — SPEC-007

## Correcciones H1–H3 preparadas — 2026-11-02

Implementadas por el agente, **pendientes de compilación y ejecución manual**.
Los hallazgos inferiores conservan el diagnóstico de T174, no describen como
vigente el código anterior. No se ejecutaron suites, HTTP, servicios, Docker ni Git.

| Hallazgo | Corrección preparada y comprobación por ejecutar |
|---|---|
| H1 | NearStart guarda uri/cuerpo/If-Match inicial antes de escribir; cada etapa guarda issuer/sub, clave, estado anterior y respuesta. La reanudación usa la misma intención, sin repetir el margen inicial del reloj. Permisos/plazos o replay los aplica el backend; tokens expirados se renuevan manualmente con la misma identidad. Se guarda y compara NearStart explícitamente tras reinicio. |
| H2 | MockitoSpyBean observa el template y el lector existentes. El primer callback se retiene con Sinks.One, dentro de su transacción, hasta que findAndModify del competidor emite un TransientTransactionError real. Barrera 2s, sin sleeps; conflicto contado obligatoriamente. Se conservan aserciones y se reintenta tras agotamiento solo después de terminar el competidor, comprobando estado sin cambios. Producción sigue con 3 intentos/5s. |
| H3 | Cada PUT aceptado se compara con intención, recurso previo, turno y configuración: identidad, historia, grupo/notas, asignación, capacidad, estado y ETag. Un manifiesto específico excluye únicamente reserva/revisión/recibo de esa intención de los hashes protegidos; compara sus invariantes y delta +1, fingerprint/versión/revisión del recibo, proyecciones BSON/HTTP y snapshots individuales. Los demás documentos, índices y opciones deben permanecer iguales. |

Archivos nuevos: ReservationReplacement.Assertions.ps1 (comparadores puros),
mongo-replacement-manifest.js (solo lectura por canal Base64), y
Test-ReservationReplacementAssertions.ps1 (comprobaciones sintéticas manuales).
El script sintético carga solo funciones seleccionadas del AST, sin invocar el
recorrido ni leer secretos, y sustituye persistencia, identidad y transporte por
memoria/datos ficticios. Prepara pérdida de respuesta, interrupción antes de guardar,
resultado ya guardado, tiempo fuera de margen, token renovado/cambiado y una sola
escritura de negocio. Incluye mutaciones de documento ajeno/índice/recibo/snapshot
que los comparadores deben rechazar. **No fue ejecutado por el agente.**

Los checkpoints incorporan comparisonVersion=2. Un checkpoint anterior vacío puede
recibir los campos nuevos conservando runId y parámetros. Si contiene etapas o
resultado final sin los nuevos comparadores, se rechaza antes de HTTP y se conserva
intacto para revisión explícita: no se inventan hashes anteriores, se sobrescribe
evidencia ni se reinicia otro ensayo sobre sus datos. No borrar ni editar manualmente
checkpoint/recibos para pasar validaciones.

Validación nueva del agente: parser Windows PowerShell 5.1 sin errores en los tres
scripts PS y `node --check` sin errores en el manifiesto JS. No se invocaron los
scripts ni las comprobaciones sintéticas; tampoco se compiló Java. Quedan pendientes
los cuatro comandos manuales siguientes y sus XML/resultados.

Los límites exactos 2h/90 días siguen cubiertos por la política automatizada previa;
no hay nuevas observaciones HTTP de esos bordes. Carrera con cancelación sigue en
T188. Los XML 268/191 corresponden a la versión previa a estas correcciones de H2;
no acreditan las nuevas barreras ni el nuevo script. T175 y cierre permanecen pendientes.

Validación manual (una línea cada comando, desde SpringWebFlux; detenerse si falla):

```powershell
powershell.exe -NoProfile -File .\scripts\dev\Test-ReservationReplacementAssertions.ps1
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Reservation*' --tests '*Availability*'
.\gradlew.bat integrationTest
```

Estas instrucciones no ejecutan el recorrido local. Su activación sigue esperando
las cinco funcionalidades, T129, corte/respaldo/versión puente y autorización integral.

Fecha: 2026-11-02. Revisión documental/estática del agente. T174 completada con
hallazgos; no implica aceptación de entrega, cierre ni ejecución de T175.

## Evidencia y alcance

El usuario confirmó prueba HTTP aislada y suites exitosas tras corregir identidades.
El agente inspeccionó XML existentes: **268 seleccionadas y 191 de integración**,
cero fallos, errores y omitidas. Incluyen los 8 casos unitarios/HTTP y 15 de
integración de SPEC-007. No se volvieron a ejecutar.

T173 registró análisis sintáctico del script en Windows PowerShell 5.1.26100.9711,
sin errores; eso no acredita comportamiento ni recuperación de checkpoints.
No hay resultados HTTP operativos/reinicio de este recorrido. No se inspeccionaron
secretos ni se presume activación. Checklist de requisitos 16/16; sin hooks.

## Trazabilidad de los 6 RF y 12 escenarios

| RF / escenarios | Evidencia automatizada y contraste | Límites reales |
|---|---|---|
| RF-07.1 / ESC-07.1–2 | ReplaceHttpTests: entrada, campos, notas, cabeceras, códigos y ETag. ReassignmentIT: identidad/local/titular/createdAt en edición de notas. RollbackIT: ajena, cancelada y legado; ContractIT: cadena/router/servicio reales. | El script operativo no demuestra todos los invariantes tras cada PUT aceptado: H3. |
| RF-07.2 / ESC-07.3–4 | ReplaceTimeTests: 2h y 90 días inclusivos, fuera de rango, encargado en inicio exacto. RollbackIT: cliente dentro de 2h rechazado, dual como encargado aceptado, inicio original alcanzado rechazado. | Extremos exactos acreditados por pruebas de política, no HTTP real. NearStart es opcional, sin evidencia operacional; su reanudación tiene H1. |
| RF-07.3 / ESC-07.5–6 | ReassignmentIT conserva mesa/combinación válida, reduce grupo sin optimizar y aumenta grupo reasignando. Exclusión propia consumida en el servicio/lector. | Script prepara notas Q1 y traslado, no aumento real del grupo; no anunciar ese caso HTTP como probado. |
| RF-07.4 / ESC-07.7–8 | ReassignmentIT mueve y permite usar origen. RollbackIT conserva estado ante lleno/duplicado, U1 con turno desconocido, snapshot discrepante, mesa desconocida/ajena incluso solo notas; falla insert de recibo y comprueba rollback/reintento. | Script compara manifiestos completos en rechazos, pero no delta permitido en escrituras aceptadas: H3. |
| RF-07.5 / ESC-07.9–10 | ConcurrencyIT ejecuta flujos de edición/edición, edición/confirmación y edición/configuración con revisiones, recibos y destino coherentes. | Flux.merge no exige que se solapen las secciones críticas: H2. Carrera con cancelación pendiente T188, tal como fija el plan. |
| RF-07.6 / ESC-07.11–12 | ReplayIT: resultado histórico después de otra edición/fuera de plazo, clave conflictiva y retirada de permiso conservando issuer/sub. ContractIT: replay HTTP con ETag histórico. | Reanudación real tras interrupción del script sin acreditar; H1/H3 afectan la fuerza de la evidencia del ensayo, no invalidan los XML existentes. |

Todos los RF/escenarios tienen trazabilidad, pero eso no significa cobertura
integral ni aprobación. La evidencia automatizada anterior se conserva con estos límites.

## H1 — Reanudación temporal de NearStart

El bloque NearStart obtiene siempre un GET vigente y vuelve a exigir inicio entre
120 y 7200 segundos antes de consultar los pasos guardados. Si la edición dual fue
aceptada/guardada pero hubo interrupción antes del cierre del recorrido, al reanudar
después de avanzar el reloj puede rechazar la fixture antes de recuperar ese éxito.
La recuperación del resultado ya aceptado no debería depender de que continúe
abierta la ventana para una nueva operación. Es un defecto estático de recuperación,
no un incidente observado en el entorno local.

Congelar URI/cuerpo/If-Match/identidad esperada de la fixture cercana antes de su
primera escritura; distinguir nueva operación de resultado guardado/replay. Si
está completada, recuperar y contrastar la evidencia sin reimponer el margen local;
si está pendiente, conservar clave y dejar al backend aplicar autorización/plazo
o replay según corresponda. No saltar controles de negocio para una intención nueva.
Añadir comprobación de recuperación con reloj/respuestas sintéticos, incluidos
interrupción antes/después de guardar respuesta y expiración del token (renovación
manual conservando issuer/sub). No ejecutar HTTP/Docker para verificar este helper.

## H2 — Solapamiento no demostrado en concurrencia

ReservationReplaceConcurrencyIT usa Flux.merge(materialize(...)) y verifica el
resultado, pero no una barrera/señal dentro de las operaciones. Una ejecución
secuencial también satisface esas aserciones. Los tres XML verdes acreditan los
resultados observados, no que se produjo necesariamente contención transaccional.

Forzar un orden reproducible con señal/barrera reactiva acotada en un punto de
lectura/escritura de prueba, demostrar que el competidor entra antes de liberar
el primer intento y conservar las aserciones de revisiones/recibos/asignación.
No añadir sleeps ni ampliar los tres intentos o cinco segundos de producción.
Permitir agotamiento acotado cuando corresponda y comprobar ausencia de efectos
parciales antes de reintentar tras terminar el competidor. Cancelación sigue en T188.

## H3 — Invariantes y conservación tras escrituras aceptadas

El script compara identidad/snapshot en notas, pero después de reasignar comprueba
solo shiftId/id/version; después del PUT del encargado, solo incremento de versión.
El GET final se compara con esa última respuesta y el manifiesto final se guarda
como referencia de reinicio. Así, un cambio indebido de titular/createdAt/grupo o
de documentos ajenos durante un PUT aceptado podría convertirse en baseline sin
detectar la desviación. Comparar configuración material no cubre otras reservas.

Comprobar cada éxito frente a la intención y al estado anterior: identidad/local/
titular/createdAt inmutables, estado CONFIRMED, grupo/notas solicitados, snapshot de
destino coherente, asignación suficiente y ETag de versión; al conservar turno y
asignación, mantener historia. En manifiestos de aceptación, permitir solo el delta
esperado de la reserva dedicada, revisión del local y recibo de la intención;
conservar demás documentos/índices/política. No permitir cambios globales ni
eliminar datos para ajustar comparaciones. Para NearStart incluir su estado final
explícito en comprobación tras reinicio, no solo en el hash global.
Probar los comparadores con datos sintéticos, incluyendo una mutación ajena que
deban rechazar. No reescribir un checkpoint existente ni aprobar evidencia fallida.

## Contrato y entrega pendiente

Se contrastaron PUT, esquema ReservationInput, notas omitidas, If-Match fuerte,
Idempotency-Key, estado 200/ETag y errores con handler/servicio/pruebas. No se
modificó OpenAPI ni se ejecutó lint. Su descripción reutilizada de If-Match menciona
cancelación repetida; no habilita editar canceladas en esta spec (409 explícito).

No se identificó una nueva decisión de negocio pendiente. H1–H3 son correcciones
del ensayo y fuerza de las pruebas. El gate sigue sin modificarse y la ejecución
operativa espera cinco funcionalidades verificadas, T129, corte persistente,
respaldo restaurable, versión puente compatible y activación integral autorizada.
La bandera ActivationPrerequisitesConfirmed del script es una declaración del
operador, no acreditación automática de esos prerrequisitos.

T175, HTTP/reinicio/gates/restore/reversión, aprobación y cierre siguen pendientes.
No se transfieren aprobaciones de 001–003 ni se ejecutan comandos del entorno en T174.
