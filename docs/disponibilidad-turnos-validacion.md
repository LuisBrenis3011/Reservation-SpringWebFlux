# SPEC-003 — Revisión de entrega: T086 y T087

## Cierre aprobado — 2026-10-29

El responsable del proyecto aprobó expresamente el cierre en esta conversación,
sin consignar un nombre. **SPEC-003 cerrada y aprobada, 27/27 tareas.** Las tres
specs de Preparación de disponibilidad están cerradas y aprobadas; lote **88/88**.
Se conserva la evidencia y la autoría de las ejecuciones del usuario, así como los
límites de los ensayos locales. Sin nuevas pruebas, servicios ni operaciones Git.
Los estados pendientes de aprobación de las secciones inferiores son historial.

## Estado vigente — T087 completada, aprobación formal pendiente

Sesión de reversión, Previous 6/6 y Current 10/10 contrastados con respaldo,
manifiestos y checkpoints: coherentes. Resultados ejecutados por el usuario;
el agente solo inspeccionó evidencia. SPEC-003 **27/27 tareas**, lote **88/88**.
SPEC-003 no está cerrada ni aprobada. [Entrega, autoría, hashes y límites](disponibilidad-turnos-entrega.md).
Los estados pendientes de las secciones inferiores son historial de preparación.

## Estado vigente — Respaldo contrastado, reversión preparada

El usuario ejecutó el respaldo/restauración: 29 documentos, cero fallos. El agente
contrastó spec-003-validation.json, manifiestos coincidentes y hashes del archive
y checkpoints. Zona Lima, dos turnos, revisión 16, índices y siete recibos del ensayo
acreditados, junto con conservación integral de la base. [Evidencia y etapas manuales
de reversión](disponibilidad-turnos-reversion.md).
Se preparó -IncludeShifts en la reversión existente, sesión propia y versión anterior
5031d8e. Sin ejecutar Docker, compilaciones, servicios, HTTP, suites ni commits.
T087 permanece abierta (26/27; lote 87/88), reversión y aprobación final pendientes.
Las secciones inferiores conservan historial.

## Estado vigente — Gates contrastados, respaldo preparado

Ejecución del usuario contrastada: Disabled 5/5 y Enabled 11/11, ligados al mismo
checkpoint HTTP y revisión 16, datos y ETag conservados. T087 continúa abierta
(26/27; lote 87/88). [Evidencia y procedimiento de respaldo/restauración](disponibilidad-turnos-respaldo.md).
Se añadió -IncludeShifts al script existente y prueba específica de solo lectura.
Sin ejecutar Docker, Mongo, respaldos, restauraciones, suites ni servicios desde
el agente. Pendientes ejecución del ensayo, reversión y cierre. Los apartados
inferiores conservan el historial y no sustituyen este estado vigente.

## Estado vigente — HTTP y reinicio contrastados, gates preparados

Ejecuciones del usuario: recorrido completo y GET tras reinicio manual exitosos.
Checkpoint contrastado por el agente: 61 etapas esperadas, siete escrituras,
revisión 16, zona Lima y dos turnos; httpCompleted=true y reinicio declarado
registrado. Fin UTC 2026-10-29T01:19:02.3184149Z; reinicio UTC 01:21:30.0964677Z.
[Evidencia, hash y procedimiento manual de gates](disponibilidad-turnos-gate.md).

Script de gates preparado, sin ejecutar: catálogo antiguo, zona, colección y ambos
recursos; autenticación y comparación íntegra al reactivar, incluidas mesas y
combinaciones. Checkpoint separado, original intacto. **T087 abierta, 26/27 tareas,
lote 87/88**. Pendientes Disabled/Enabled, respaldo/restauración, reversión y cierre.
Las notas anteriores de recorrido preparado sin ejecutar son historial.

Fecha de revisión: 2026-10-28. SPEC-003 continúa en revisión, sin aprobación
formal ni cierre. T086 completada como revisión; T087 parcial y abierta.
Estado: 26/27 tareas; lote 87/88. H1–H3 corregidos y validados por ejecución del
usuario, con XML contrastados por el agente. T087 continúa abierta por la evidencia
operativa pendiente; SPEC-003 no está cerrada ni aprobada.

## T087 — Lint recibido y recorrido preparado

El usuario ejecutó Redocly con extends minimal: **contrato válido, cero errores y
seis warnings**. Corresponden a localhost y cinco esquemas sin uso: TableInput,
TablePatch, Table, CombinationInput y Combination. Se conserva OpenAPI y sus reglas;
no se hereda el resultado de contratos de SPEC-001/002. El agente no ejecutó npx.

Se preparó Test-LocalShifts.ps1 con checkpoint propio, permisos explícitos de
fixtures/cambios de zona y validación de sintaxis en Windows PowerShell 5.1.
No se ejecutó el recorrido ni se obtuvo evidencia de HTTP o reinicio.
[Procedimiento manual, conservación y límites](disponibilidad-turnos-http.md).
Base Git de esta preparación: eb547292e918adaafb7ef3a5bd49fdc9255fdc9e,
árbol inicialmente limpio. T087 sigue sin marcar; gates, respaldo/restauración,
reversión y cierre siguen pendientes.

## Validación confirmada de H1–H3 — 2026-10-28, America/Lima

El usuario confirmó compilación exitosa (2 s, seis tareas up-to-date), selección
test exitosa (23 s) e integración exitosa (1 min 27 s), y comunicó haber realizado
el commit. El agente únicamente inspeccionó los XML y Git, sin repetir ejecuciones.

| Informe actual | Archivos | Casos | Fallos / errores / omitidos | Inicios UTC |
|---|---:|---:|---|---|
| test, selección Availability y ReservationCrudServiceImplTests | 13 | 230 | 0 / 0 / 0 | 2026-10-29T00:08:23.065Z–00:08:40.020Z |
| integrationTest | 18 | 121 | 0 / 0 / 0 | 2026-10-29T00:11:59.337Z–00:12:48.919Z |

Las fechas UTC corresponden al 2026-10-28 por la noche en America/Lima.
Commit observado: `dca7e005e2389aba3ed2acbc901262328571d7a0`,
`fix: explain invalid shift times and strengthen history checks`.
Árbol Git limpio antes de registrar esta evidencia. Se verificaron en los XML los
cuatro casos temporales parametrizados tanto HTTP como de validador, el nuevo PUT
de turno terminado y los casos reforzados de recálculo/rollback de zona. H1–H3
quedan validados con ese alcance automatizado. Los totales 225/120 conservados abajo
son anteriores y no se suman a 230/121. No hay evidencia nueva de HTTP real con JWT,
reinicio, gates, respaldo/restauración o reversión. El resultado posterior del lint
se registra en la sección vigente de T087 de arriba.

## Historial — preparación de la corrección H1–H3

Base observada: commit `883b0b8eab484512b5ff8a9edebfc8a7d83fe090`
(`docs: record shift validation evidence and delivery gaps`), árbol limpio antes
de estas correcciones. El commit 8612b2e y los XML 225/120 siguientes conservan
su alcance anterior: no acreditan las pruebas nuevas o ampliadas.

- **H1:** RestaurantShiftValidator distingue cero offsets (hora inexistente) de
  varios (hora ambigua/repetida) mediante ShiftLocalTimeException. Mantiene
  VALIDATION_ERROR/422 y el rechazo sin ajuste automático. AvailabilityHttpSupport,
  componente compartido de SPEC-001, se amplía únicamente para ese subtipo final:
  publica uno de dos mensajes fijos en español; otros errores conservan su
  tratamiento previo y no exponen causas internas. No se cambian firmas públicas,
  códigos ni esquema OpenAPI. No se crea un segundo soporte HTTP.
- **Pruebas H1:** cuatro casos de ZoneRules, gap y repetición en inicio y fin;
  verifican razón, código y mensaje. Cuatro casos HTTP parametrizados usan el error
  del validador real y el servicio simulado para comprobar mensaje/422 en POST de
  turno, PUT de turno y PUT de zona. Se conserva la comprobación de ocultación del
  mensaje de errores genéricos. Estos tests HTTP no sustituyen un recorrido real.
- **H2:** esc0318_turnoTerminadoRechazaEdicionYConservaDocumentoRevisionYRecibos
  avanza el Clock después del fin, propone un nuevo intervalo futuro y exige
  SHIFT_ALREADY_STARTED; compara documento completo, respuesta GET, zona, revisión,
  número y contenido de recibos. Usa únicamente la infraestructura efímera de IT
  cuando el usuario ejecute la suite; no opera sobre Mongo local.
- **H3:** futurosConservanLocalesEHistoriaSeMantiene añade aserciones de localEnd,
  endInstant, id, restaurantId y duración, además de las de inicio, zona e historia.

El agente ejecutó únicamente compileJava, compileTestFixturesJava, compileTestJava
y compileIntegrationTestJava: BUILD SUCCESSFUL (17 s inicialmente y 6 s en la
comprobación final tras reforzar el IT de H1), sin ejecutar suites,
servicios, Docker ni commits. Las nuevas pruebas quedan pendientes del usuario.
T087 sigue sin marcar; los ensayos operativos y el cierre conservan sus pendientes.

## Autoría y evidencia de fase 5

El usuario comunicó estas tres ejecuciones exitosas. El agente no las repitió:

| Validación ejecutada por el usuario | Evidencia contrastada por el agente |
|---|---|
| compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava | Salida comunicada: BUILD SUCCESSFUL en 3 s, 6 tareas up-to-date. No hay XML de compilación que acredite una ejecución adicional. |
| test --tests '*Availability*' --tests '*ReservationCrudServiceImplTests' | 13 XML, 225 casos, 0 fallos, 0 errores, 0 omitidos. Inicios UTC: 2026-10-28T23:08:27.287Z–23:08:41.172Z. Es una selección, no la suite test completa. |
| integrationTest | 18 XML, 120 casos, 0 fallos, 0 errores, 0 omitidos. Inicios UTC: 2026-10-28T23:09:03.843Z–23:10:08.947Z. |

Commit observado: `8612b2ed84df70aa733e49a4f8595d42ef29c1f5`,
`feat: edit shifts and atomically change restaurant time zone`.
Estado Git inicial sin cambios preparados, modificados ni archivos nuevos.
Este vínculo identifica el código observado; los XML son resultados locales
aportados por el usuario, no una atestación de CI asociada criptográficamente al commit.

Se comprobó el descubrimiento específico de SPEC-003:

| Clase | Source set | Casos en XML |
|---|---|---:|
| AvailabilityShiftHttpTests | test | 31 |
| AvailabilityShiftValidatorTests | test | 10 |
| AvailabilityTimeZoneIT | integrationTest | 10 |
| AvailabilityShiftOverlapIT | integrationTest | 3 |
| AvailabilityShiftReadTests | integrationTest | 2 |
| AvailabilityShiftConcurrencyIT | integrationTest | 2 |
| AvailabilityShiftFailureIT | integrationTest | 4 |
| AvailabilityShiftLegacyIT | integrationTest | 2 |
| AvailabilityShiftZoneChangeIT | integrationTest | 6 |

Son 41 casos específicos en test y 29 en integrationTest, incluidos en los
totales anteriores; no se suman otra vez. Los 24 escenarios de negocio no equivalen
a 24 métodos: algunos casos son parametrizados y otros verifican varias reglas.

## T086 — Trazabilidad de los 8 RF y los 24 escenarios

Archivos bajo `src/test/java/com/brenis/SpringWebFlux/handlers/` (Http),
`src/test/java/com/brenis/SpringWebFlux/validators/` (Validator) y
`src/integrationTest/java/com/brenis/SpringWebFlux/services/` (los demás).
Los nombres abreviados siguientes corresponden a AvailabilityShiftHttpTests,
AvailabilityShiftValidatorTests, AvailabilityTimeZoneIT y AvailabilityShift*.

| RF | ESC | Prueba / aserción inspeccionada | Resultado y límite |
|---|---|---|---|
| 03.1 | 03.1 | Http: esc0301_zonaAusenteEsNullSinDefault, esc0301_putPropioDevuelveZonaYETag; TimeZoneIT: zonaInicialRepeticionYReplaySinDefault | Zona propia y null explícito, ETag y replay. |
| 03.1 | 03.2 | Http: esc0302_permisosAntesDeLeerCuerpo; TimeZoneIT: zonaInvalidaNoPersiste; OverlapIT: sinZonaNoSeCreaTurno | Permisos, zona inválida y ausencia de zona; no se usa un default. |
| 03.2 | 03.3 | Validator: esc0303_medianocheConFechaExplicita; ReadTests: esc0307_0308_snapshotEstableEHistoria | Cuatro horas y snapshot de un turno con fecha de fin explícita. |
| 03.2 | 03.4 | Validator: esc0304_fechasInvalidas | Igualdad, fin anterior, fecha y formato inválidos. |
| 03.3 | 03.5 | OverlapIT: esc0305_0306_adyacenciaYSuperposicionEntreFechas | Adyacencia aceptada. |
| 03.3 | 03.6 | Mismo caso; edicionExcluyeIdentidadYRechazaRevisionOSolapamiento | Solapamiento de alta y edición rechazado; revisión/recibos conservados. |
| 03.4 | 03.7 | ReadTests: esc0307_0308_snapshotEstableEHistoria | La zona actual distinta no reinterpreta el snapshot; no se cambió la zona del SO/JVM en el ensayo. |
| 03.4 | 03.8 | Mismo caso e aislamientoYReplayHistorico | Lista vacía, filtrado por propietario y recurso ajeno 404. |
| 03.5 | 03.9 | ZoneChangeIT: putFuturoConservaIdentidadYReplayYRechazaHistoria | PUT conserva identidad, incrementa una revisión y permite replay. |
| 03.5 | 03.10 | TimeZoneIT: reservaProtegidaBloqueaZona; ConcurrencyIT: edicionFrenteAConfirmacionConservaCompromiso | Bloqueo con reserva futura y snapshot/revisión conservados. |
| 03.6 | 03.11 | ZoneChangeIT: putFuturoConservaIdentidadYReplayYRechazaHistoria; FailureIT: falloNoModificaTurnoNiZona | Actualización completa y rechazo sin efectos parciales. |
| 03.6 | 03.12 | ConcurrencyIT: esc0311_0312_altasSuperpuestasNoSeConfirmanAmbas | Solo una alta confirmada; agotamiento acotado admisible y reintento posterior rechazado por conflicto. |
| 03.2 | 03.13 | Validator: esc0313_0314_rechazaGapYOverlapEnAmbosExtremos; Http: esc0313_0314_explicaCausaTemporalEnAltaEdicionYZona; ZoneChangeIT: segundoTurnoInvalidoRevierteTodo | H1 añade gap en ambos extremos y mensaje específico. Compilado; nuevas aserciones pendientes de ejecución. |
| 03.2 | 03.14 | Validator y Http: mismos casos parametrizados | H1 añade comprobación de razón/mensaje de ambigüedad en inicio y fin. Compilado; pendiente de ejecución. |
| 03.5 | 03.15 | ZoneChangeIT: futurosConservanLocalesEHistoriaSeMantiene | H3 comprueba ambos locales/instantes, zona, identidad y duración. Nuevas aserciones compiladas, pendientes de ejecución. |
| 03.5 | 03.16 | ZoneChangeIT: segundoTurnoInvalidoRevierteTodo, cambioNoPuedeRecalcularInicioNoFuturo, futuroRecalculadoNoSeSuperponeConHistoria | Rollback del conjunto por gap; otros rechazos comprueban revisión. |
| 03.5 | 03.17 | ZoneChangeIT: reservaEnCursoProtegeZonaYEdicionSinAlterarSnapshot | Visita vigente protege zona y edición, con reserva y recibos conservados. |
| 03.2 | 03.18 | ReadTests: esc0307_0308_snapshotEstableEHistoria; ZoneChangeIT: esc0318_turnoTerminadoRechazaEdicionYConservaDocumentoRevisionYRecibos | H2 añade PUT posterior al fin con documento, GET, zona, revisión y recibos intactos. Caso compilado, pendiente de ejecución. |
| 03.2 | 03.19 | Validator: esc0318_0319_futuroEstricto; ZoneChangeIT: putFuturoConservaIdentidadYReplayYRechazaHistoria | Igual al reloj rechazado y comparación con ±1 ns; rechazo por inicio original exacto. |
| 03.5 | 03.20 | ZoneChangeIT: futurosConservanLocalesEHistoriaSeMantiene | Documento histórico íntegro conservado; futuro recalculado. |
| 03.7 | 03.21 | FailureIT: esc0321_0322_falloNoDejaParcialesYReintentaMismaClave, falloNoModificaTurnoNiZona | Reintento de alta/edición con la misma clave después de recuperación. |
| 03.7 | 03.22 | Mismos casos parametrizados fail/delay; TimeZoneIT: falloODemoraConservaZonaRevisionYPermiteReintentar | 503, sin cambios de revisión/recibos/turno; conservación de zona también en TimeZoneIT. |
| 03.8 | 03.23 | LegacyIT: esc0323_0324_legadoStringOBinarioPermiteConsultaBloqueaAlta | GET autorizado durante transición, conserva la reserva antigua. |
| 03.8 | 03.24 | Mismo caso parametrizado BSON/string; TimeZoneIT: legadoConservaZonaYRevision, huerfanoBloqueaSinCrearZona | POST/PUT turno y PUT zona bloqueados; sin adaptación/borrado. |

### Historial de hallazgos detectados por T086

- **H1 — RF-03.2, ESC-03.13/14:** el validador captura DateTimeException y emite
  un mensaje genérico; AvailabilityHttpSupport devuelve el código como mensaje.
  Se rechaza con 422, pero no se explica al cliente si la hora no existe o es
  repetida. Las pruebas actuales solo exigen VALIDATION_ERROR. Falta ajustar esa
  explicación y comprobarla, además de un gap en el extremo final.
- **H2 — ESC-03.18:** no se encontró un caso directo de PUT después del fin del
  turno, con comparación de identidad, locales, zona, instantes, revisión y recibos.
  El código rechaza por inicio no futuro, pero eso es inspección, no ese caso ejecutado.
- **H3 — ESC-03.15:** reforzar las aserciones de ambos extremos del futuro
  recalculado; el caso actual comprueba directamente el inicio y la zona.
- El checklist de calidad de requisitos conserva una nota histórica de 6 RF/18
  escenarios. El inventario real es 8/24. Se dejó intacto como artefacto de revisión
  de requisitos; sus 16/16 marcas no certifican esta implementación.

Esa revisión inicial no modificó código productivo ni pruebas. La corrección
posterior de H1–H3 se describe al principio; todavía no se declara validada.

## Contrato y compatibilidad

Se contrastaron las seis operaciones del router/handler con OpenAPI 3.1.0:
GET/PUT time-zone, POST/GET shifts y GET/PUT shifts/{shiftId}, bajo el prefijo
`/catalog`. Requests estrictos, UUID, snapshot temporal, revision y zoneId nullable
en GET sin configuración coinciden con los DTO. POST 201 con Location y ETag;
PUT/GET 200 con ETag. PUT exige If-Match; writes usan Idempotency-Key.
Seguridad JWT y errores 400/401/403/404/409/412/422/503 consumen el soporte común.
Los IT comprueban replay y conservación; los tests HTTP usan dobles y no sustituyen
el recorrido con el emisor local real.

Se leyó el JSON y resolvieron sus 64 referencias locales: ninguna ausente.
SHA-256 del contrato sin modificar:
`B530CF05E7F13F9CE0555447A131EAB876658AD99C391F5D9AC00198FB628569`.
Esta comprobación estática no ejecuta ni sustituye Redocly. Posteriormente el
usuario aportó el lint de SPEC-003: válido sin errores y con seis avisos, descritos
en la sección vigente de T087. No se ocultan reglas
ni se cambia la semántica para eliminar warnings. La descripción del contrato
conserva su estado propuesto; esta revisión no lo aprueba formalmente.

Se reutilizan coordinador, guard SHIFT/ZONE, Clock e inicializador. No se añadió
infraestructura compartida, caché, recurrencia, borrado ni asignación de reservas.

## T087 — Evidencia pendiente específica de SPEC-003

| Comprobación | Estado |
|---|---|
| Compilación y selección/integración de fase 5 | Usuario: exitosas; XML contrastados como arriba. |
| Hallazgos H1–H3 | Validados por el usuario; XML actuales 230/121 sin incidencias, commit dca7e00. No sustituyen los ensayos operativos. |
| Lint OpenAPI de SPEC-003 | Usuario: contrato válido, cero errores, seis warnings conocidos; sin cambios de contrato/reglas. |
| HTTP con JWT real: zona, POST/GET/PUT turno, permisos, If-Match, idempotencia/replay, reglas temporales y rechazo sin cambios | Script preparado y sintaxis revisada; ejecución y evidencia pendientes. |
| Persistencia de zona y turnos tras reinicio | Modo -AfterRestart preparado, pendiente de ejecución y evidencia. |
| Gate desactivado/reactivado: catálogo compatible, rutas ocultas/autenticadas y datos/ETag conservados | Pendiente de ensayo específico. |
| Respaldo/restauración aislada con zonas, turnos, índice, revisiones y recibos | Pendiente; no reutilizar como prueba suficiente un respaldo anterior sin estos recursos. |
| Reversión compatible y regreso: datos, historia temporal, índices, revisiones, recibos y ETag conservados | Pendiente; versión anterior compatible todavía por contrastar para este alcance. |
| Aprobación formal y cierre | Pendientes; no solicitados en esta entrega. |

Las aprobaciones y ensayos de SPEC-001/002 no se transfieren a SPEC-003.
Los checkpoints de mesas/combinaciones no acreditan turnos o zona por su existencia.
No se inspeccionaron JWT ni se accedió a Mongo, Docker o servicios.

## Próxima validación manual — PowerShell

Las correcciones ya fueron validadas por el usuario. Estos comandos se conservan
para futuras regresiones; no hace falta repetirlos por esta actualización documental:

```powershell
Set-Location <WORKSPACE>\SpringWebFlux
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Availability*' --tests '*ReservationCrudServiceImplTests'
.\gradlew.bat integrationTest
```

El lint de SPEC-003 ya fue aportado como válido con seis warnings; se conserva el
comando de referencia y no es necesario repetirlo por esta preparación:

```powershell
Set-Location <WORKSPACE>
npx --yes @redocly/cli lint specs/003-configurar-turnos/contracts/openapi.json --extends minimal
```

El comando puede descargar la CLI mediante npx. Conservar su salida y sus avisos.
Los XML actuales acreditan 230/121; no reutilizar 225/120 como resultado de esta ampliación.

## Git Bash — sugerido, sin ejecución del agente

Desde SpringWebFlux; revisar antes de confirmar:

```bash
git add scripts/dev/Test-LocalShifts.ps1 docs/disponibilidad-turnos-http.md docs/disponibilidad-turnos-validacion.md README.md
git diff --cached --check
git diff --cached --stat
git commit -m "test: prepare manual shift and time zone HTTP checks"
```

Los documentos SDD de specs permanecen fuera del repositorio del servicio.
