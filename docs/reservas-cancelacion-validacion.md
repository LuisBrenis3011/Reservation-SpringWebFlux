## H1–H3: resultados comunicados por el usuario — 2026-11-02

El usuario ejecutó powershell.exe -NoProfile -File
.\scripts\dev\Test-ReservationCancellationAssertions.ps1 y obtuvo:
«OK: comparacion, deltas, noChange y recuperacion sinteticos. No acredita HTTP ni Mongo.»
La captura posterior muestra ambos node --check sin mensajes y retorno al prompt:
scripts/dev/mongo-cancellation-manifest.js y
scripts/dev/mongo-cancellation-confirmation-manifest.js.

Se registra como validación pura/sintáctica exitosa ejecutada por el usuario.
El agente inspeccionó archivos, dependencias y la evidencia aportada; no ejecutó
estos comandos ni inspeccionó un recibo persistido de esas ejecuciones.
H1–H3 quedan validados en el alcance sintético/sintáctico, no como recorrido HTTP,
Mongo, reinicio o prueba de activación. No hubo nuevas suites Java.
T191 sigue abierta. SPEC-008 15/16; lote 94/103, sin aprobación ni cierre.

---

## Reparación del doble de identidad preparada — 2026-11-02

Usuario ejecutó la comprobación pura y obtuvo «Identidad congelada ausente».
Causa inspeccionada: el doble Cancel-Identity resolvía $identity desde el ámbito
dinámico de Cancel-Step, donde era null. No es una validación del backend fallida.

Identidad sintética ahora en $script:CancellationTestIdentity. Los otros dobles
usan fixtures explícitas en ámbito script para respuestas y deltas. Las seis
interrupciones simuladas (cancelación/confirmación, antes de HTTP/respuesta/guardado)
exigen el mensaje esperado; una excepción ajena ya no acredita el caso.
También se comprueba la causa exacta al rechazar identidad distinta y se restablece
el indicador en finally. Se conservan las aserciones de integridad y recuperación.

Corrección pendiente de ejecución manual. No se ejecutaron suites ni recorridos,
ni se modificaron backend, helpers productivos o checkpoints privados. H1–H3
siguen pendientes de validación; T191 abierta, SPEC-008 15/16, lote 94/103.

Repetir desde el servicio:

    powershell.exe -NoProfile -File .\scripts\dev\Test-ReservationCancellationAssertions.ps1

---

## Correcciones H1–H3 preparadas — 2026-11-02

Implementadas por el agente y pendientes de comprobaciones manuales. Los hallazgos
originales se conservan debajo como diagnóstico histórico, sin declararlos aprobados.

- H1: ReservationCancellation.Assertions.ps1 reutiliza el canonizador estructural,
  normaliza solo campos de instante y conserva precisión hasta nanosegundos.
  Distingue null, campos ausentes/extra, arrays, estado, ETag y Location.
  GET se contrasta con cuerpo/ETag del POST respetando 200/sin Location frente a
  201/con Location para nuevas confirmaciones.
- H2: checkpoint schemaVersion=2 con validación de estructura, IDs, intención,
  identidad, pendingName, lastManifest y expectativas aceptadas. Se verifica
  continuidad antes de escrituras/replay/final. Recuperación prioritaria solo
  de la clave pendiente, comprobando delta y recibo antes de continuar.
  Sin recibo se revisan estado y plazo; con recibo se recupera la intención ya
  aceptada aunque haya pasado el plazo. -AfterRestart rechaza intenciones pendientes.
  Checkpoints anteriores se conservan y rechazan, sin migración/reseteo silencioso.
- H3: nuevo helper Mongo de solo lectura para confirmación, expectativas Base64.
  Protege cancelada, documentos ajenos, recibos previos, índices, opciones, política
  y metadatos no afectados. Verifica nueva reserva y recibo exclusivos, revisión +1,
  versión 1, identidad/turno/grupo/notas, ETag/Location, asignación, capacidades,
  snapshot/extremos contra oferta y ausencia de solapamiento físico.
  Noop compara además hash del documento BSON completo.
- Comprobaciones puras redactadas: fechas equivalentes/distintas y nanosegundos,
  null/campos/arrays, deltas/noChange, conservación, identidad y ventanas.
  Se prueban funciones reales de etapas mediante AST y dobles de I/O, simulando
  interrupción antes de HTTP, respuesta perdida y guardado interrumpido tanto en
  cancelación como nueva confirmación. Reloj controlado; no archivos privados ni JWT.
- Revisión realizada: parser de Windows PowerShell 5.1 sin errores en los tres
  archivos PowerShell. No se ejecutaron comprobaciones puras, suites, JavaScript,
  HTTP, Docker ni servicios. XML 275/210 anteriores no acreditan estos cambios.

Desde <WORKSPACE>\SpringWebFlux, ejecutar cada línea manualmente:

    powershell.exe -NoProfile -File .\scripts\dev\Test-ReservationCancellationAssertions.ps1
    node --check scripts/dev/mongo-cancellation-manifest.js
    node --check scripts/dev/mongo-cancellation-confirmation-manifest.js

No hace falta recompilar Java por cambios de scripts. No ejecutar aún HTTP:
T129 y activación integral pendientes. Si existe checkpoint schema 1, conservarlo
y revisar explícitamente antes de recuperar; no borrarlo/renombrarlo para forzar ensayo.

SPEC-008 15/16; lote 94/103. T191 abierta, sin aprobación ni cierre.
Próximo paso: recibir resultados de comprobaciones puras y revisar prerrequisitos
de activación integral antes de ensayos reales. Ejecuciones a cargo del usuario.

---

# Revisión T190 — SPEC-008: cancelación

Fecha: 2026-11-02. Autor de revisión: agente, por inspección estática.
T190 completada como revisión, no como subsanación ni aprobación de entrega.
SPEC-008 15/16; lote 94/103. T191 abierta. H1–H3 pendientes de corrección.
No ejecutar aún el script manual. No se ha activado el gate ni cerrado una spec.

## Evidencia y procedencia

- Usuario: compilación y selección exitosas; integrationTest mostró BUILD SUCCESSFUL
  en 2m19s y después error de comunicación con daemon. Posterior --no-daemon exitoso,
  7 up-to-date; reutilizó resultados, no volvió a ejecutar pruebas.
- Agente en T189 y reconfirmado en T190: XML seleccionados 275 e integración 210,
  sin fallos, errores ni omitidas. Es inspección de artefactos, no ejecución del agente.
- T189: análisis sintáctico con Windows PowerShell 5.1 y node --check, sin ejecutar
  el recorrido. La sintaxis válida no acredita comparadores ni reanudación correctos.
- T190: lectura de spec, plan, tareas, modelo, investigación, contrato, pruebas,
  quickstart, script y helper Mongo. Checklist 16/16; sin extensiones/hook configurados.
- HTTP, reinicio, gates, respaldo/restauración y reversión de esta spec: pendientes.
  No transferir aprobación de 001–003 ni de otras funcionalidades.

## Trazabilidad de los cinco RF y doce escenarios

Rutas Java relativas al servicio, paquete com/brenis/SpringWebFlux.

| RF | Escenarios | Pruebas inspeccionadas | Recorrido manual / límites |
|---|---|---|---|
| RF-08.1 | ESC-08.1–2 | ReservationCancellationTimeTests; ReservationCancellationHttpTests; ReservationCancellationIT: clienteExactamenteDosHorasYEncargadoDentroDeDosHoras, ajenaLegacyYVersionObsoletaConservanDatos, encargadoEnInicioExactoNoCancelaUnaConfirmada | Permisos y NearStart opcional; exactitud 2h/inicio y legacy solo automatizados. |
| RF-08.2 | ESC-08.3–4 | ReservationCancellationIT.liberaCombinacionABConservandoReservaC | Delta Mongo protege historia y documentos ajenos. No se obliga a usar A+B ni se acredita C por un recorrido aún no ejecutado. |
| RF-08.3 | ESC-08.5–6 | ReservationCancellationNoopIT: otroIdentificadorFueraDePlazoNoCambiaDocumentoNiRevision, noReactivaNiOmiteAutorizacionActual, permisoRetiradoNoRecuperaReciboDeEncargado; ContractIT | Noop con otra clave y versión obsoleta; fuera de plazo/revocación/reactivación se sostienen en pruebas automatizadas. |
| RF-08.4 | ESC-08.7–8 | ReservationCancellationConcurrencyIT: dosCancelacionesSoloUnaTransicionYNoopConfirmado, cancelarGanaAEdicionSinOcupacionHuerfana; ReservationReplaceConcurrencyIT.t188_edicionGanaACancelacionConSolapamientoReal | Idempotencia/replay HTTP preparados; carrera real solo IT. Sin ampliar intentos ni presupuestos. |
| RF-08.5 | ESC-08.9–10 | CancellationIT, CancellationFailureIT: falloDeLecturaPropiaYFalloDeReciboConservanTodo, commitInciertoNoRepiteTransicionYNoopConservaVersion; NoopIT.falloDeReciboNoopNoCambiaRevisionNiHistoria; ReservationLifecycleIT | Nueva confirmación preparada, conservación incompleta H3. No inducir fallos de commit en Mongo local. |
| RF-08.5 | ESC-08.11–12 | CancellationFailureIT: q4_noInvocaNingunLectorNiGuardGlobalCaidos, legadoAjenoNoImpideCancelarNiPierdeSuBloqueo, snapshotPropioCorruptoNoSeLiberaNiAunqueYaEsteCancelada | Q4Only separado y UNDETERMINED antes/después. Corrupción propia/fallo global simulado solo automatizados. |

Las clases abreviadas Cancellation* corresponden a ReservationCancellation*.
Los XML verdes acreditan las ejecuciones aportadas; no acreditan el script PowerShell.

## Contrato y comportamiento revisados

POST /restaurants/{restaurantId}/reservations/{reservationId}/cancellation, sin cuerpo;
Idempotency-Key e If-Match requeridos. Respuestas 200,400,401,403,404,409,412,500,503.
Handler, router y pruebas de contrato conservan ese alcance; no DELETE ni reactivación.
200 con ETag de versión de reserva, sin Location. Primera transición condicional
CONFIRMED y versión vigente; copia snapshot e historia, cambia estado/version/fechas,
reserva y recibo en una transacción. Índices parciales liberan ocupación por estado.

Q4: cancelación accede solo a su reserva y su integridad; no llama lector/guard global.
La rama CANCELLED ignora plazo y obsolescencia semántica, exige sintaxis/permisos
vigentes y registra noChange. Nueva clave crea recibo técnico sin mutar documento ni
revisión; misma intención recupera recibo con autorización/integridad actual.
El backend y las aserciones automatizadas inspeccionadas cubren esos invariantes.
No se identificó una desviación productiva confirmada en esta revisión.

## Hallazgos pendientes del recorrido manual

### H1 — Comparación textual de objetos e instantes (alta)

Equal-Cancel compara ConvertTo-Json textual. Cancel-Step compara reservationView y
receiptView del helper JS con el cuerpo HTTP. El helper usa Date.toISOString(), que
produce milisegundos fijos (.000Z), mientras un Instant HTTP puede representar el
mismo instante como Z sin fracción. También depende del orden de propiedades.
Hay un riesgo concreto de falso fallo después de una cancelación ya aceptada.
No está demostrado por ejecución local; se deriva del comparador y representaciones.

Corrección requerida: comparador estructural canónico independiente del orden de
propiedades y comparación temporal por instante (incluido cancelledAt nullable).
Conservar igualdad estricta de estado, ETag, Location y contenido semántico en replay;
no omitir campos ni normalizar valores de negocio distintos. Pruebas puras con
instantes equivalentes y distintos, null/fecha, propiedades reordenadas, campos
extra/ausentes y versiones diferentes. Reutilizar funciones existentes cuando proceda.

### H2 — Reanudación sin continuidad completa de evidencia (alta)

Cancel-Step con response guardada retorna sin verificar el estado actual. El POST
que vuelve a confirmar solo persiste intención/respuesta, sin un antes/después propio.
La captura final GET se acepta como nueva referencia sin contrastarla con todas las
respuestas aceptadas. Así, una escritura externa entre ejecuciones puede pasar a ser
baseline de etapas posteriores en vez de detectarse como deriva del ensayo.
El bloqueo de archivo protege el checkpoint, no bloquea escritores del backend.

Corrección requerida: guardar manifiestos/estado verificable después de cada etapa;
verificar continuidad antes de nuevas escrituras y antes de fijar el final. Si hubo
resultado incierto, recuperar solo la intención congelada con la misma clave y
comprobar su delta permitido antes de continuar. Validar integridad/schema del
checkpoint y mantener IDs, claves, identidad y evidencia original. Congelar NearStart
antes de escribir y revalidar el plazo de operaciones todavía pendientes: si el inicio
ya pasó, detener con explicación, sin sustituir fixture, regenerar claves o relajar plazos.
Pruebas puras de interrupción antes/después de aceptación, deriva externa e identidad
renovada igual/distinta. No reiniciar ni sobrescribir checkpoints previos silenciosamente.

### H3 — Conservación insuficiente alrededor de la nueva confirmación (alta)

Tras el POST nuevo solo se comprueba id distinto y status CONFIRMED. No se contrasta
turno, titular, restaurante, grupo, notas, versión inicial y asignación válida con la
intención/configuración congeladas; tampoco se verifica el delta exclusivo de reserva,
recibo y revisión de esa escritura. El manifiesto final captura el estado resultante,
pero no demuestra por sí mismo conservación del origen durante ese POST.

Corrección requerida: antes/después propio de nueva confirmación con expectativa
congelada; exactamente una reserva nueva y un recibo de intención, revisión +1 y
versión inicial, identidad/turno/grupo/notas/asignación/snapshot coherentes. Proteger
la cancelada completa, demás reservas, recibos previos, oferta, política, índices y
metadatos no afectados. Verificar cancelada original y nueva confirmada antes de
fijar final y tras reinicio; no confundir respuesta 201/Location con GET 200/sin Location.
Añadir pruebas puras positivas y negativas de esos comparadores. No escribir en Mongo
para preparar estas verificaciones ni debilitar las aserciones existentes.

## Dependencias y límites posteriores

T129 sigue abierta: no usar -ActivationPrerequisitesConfirmed hasta preparar secuencia
integral, respaldo restaurable, SHA/JAR puente, corte persistente, identidades y gates.
Q4 separado es correcto: el bloqueo general impediría nueva confirmación normal.
La carrera HTTP no está implementada por el script secuencial; su evidencia actual es
la IT reproducible, y el límite permanece explícito (no afirmar ensayo HTTP concurrente).
No se modificaron backend, pruebas, OpenAPI, script, helper, datos ni checkpoints en T190.
Las notas antiguas de quickstart son historial; el estado vigente es esta revisión.
Siguiente paso: corregir H1–H3, validar comparadores manualmente y solo después preparar
T191 con evidencia específica. Mantener T191 abierta y SPEC-008 sin aprobar.