# SPEC-002 — Revisión de entrega y evidencia disponible

## Estado y autoría

Estado actualizado el 2026-10-28: T059 y T060 completadas; evidencia final
contrastada en [la entrega verificada](disponibilidad-combinaciones-entrega.md).
SPEC-002 cerrada y aprobada expresamente por el responsable el 2026-10-28,
mediante «apruebo el cierre del spec 2» en esta conversación. SPEC-003 no se inicia.

El usuario ejecutó compilación, pruebas seleccionadas e integración y comunicó
BUILD SUCCESSFUL. El agente leyó los XML, código, contrato y Git; no ejecutó
suites, compilación nueva, servicios, peticiones HTTP, Docker ni operaciones Mongo.
No se hicieron add, commits ni publicaciones. El árbol Git estaba limpio al comenzar.

Commit observado: `53c090143d381fcff0c32f113413284db12db1c7`,
`feat: replace table combinations with reservation protection`, fechado el
2026-10-27 a las 23:24:12 -05:00. Los XML preceden a ese commit: no demuestran
una ejecución posterior al commit; concuerdan con la secuencia pruebas y luego
commit que comunicó el usuario. No se afirma que los XML registren un hash Git.

## Resultados comprobados en los informes del usuario

Fuente: `build/test-results/test/TEST-*.xml` y
`build/test-results/integrationTest/TEST-*.xml`, excluidos de Git.

| Ejecución | XML / clases | Pruebas | Fallos | Errores | Omitidas | Inicio de clases, UTC |
|---|---:|---:|---:|---:|---:|---|
| `test --tests '*Availability*' --tests '*ReservationCrudServiceImplTests'` | 11 | 184 | 0 | 0 | 0 | 2026-10-28 04:21:01.742–04:21:13.332 |
| `integrationTest` | 11 | 91 | 0 | 0 | 0 | 2026-10-28 04:22:09.574–04:22:46.985 |

En America/Lima esos inicios corresponden al 2026-10-27, 23:21 y 23:22.
Los intervalos son los timestamps de inicio de las clases, no la duración de
las suites. La compilación fue comunicada como exitosa y UP-TO-DATE en 3 s;
esto no se presenta como una recompilación de todas las fuentes.

La selección de `test` no equivale a la suite completa: no acredita una nueva
ejecución de `SpringWebFluxApplicationTests.contextLoads`. Integración descubre
también `AvailabilityCombinationReadTests`, aunque su nombre no termina en IT.
Los totales incluyen pruebas compartidas; no son 275 pruebas exclusivas de SPEC-002.

| Clase de combinaciones | Source set | Casos descubiertos |
|---|---|---:|
| `AvailabilityCombinationHttpTests` | test | 39 |
| `AvailabilityCombinationValidatorTests` | test | 8 |
| `AvailabilityCombinationConcurrencyIT` | integrationTest | 9 |
| `AvailabilityCombinationFailureIT` | integrationTest | 6 |
| `AvailabilityCombinationLegacyIT` | integrationTest | 8 |
| `AvailabilityCombinationProtectionIT` | integrationTest | 10 |
| `AvailabilityCombinationReadTests` | integrationTest | 6 |
| **Subtotal propio** | **47 seleccionadas + 39 integración** | **86** |

Todos estos casos tienen cero fallos, errores y omitidas. Se cuentan las
invocaciones parametrizadas del XML, no solo métodos anotados. La evidencia
histórica de fase 3 (164/68, commit `61284`) se conserva como antecedente;
la de SPEC-001 (138/52 y aprobación) no se transfiere a esta entrega.

## T059 — Trazabilidad revisada

Las clases HTTP están en `src/test/java/com/brenis/SpringWebFlux/handlers/`,
las de validación en `src/test/java/com/brenis/SpringWebFlux/validators/` y
los IT en `src/integrationTest/java/com/brenis/SpringWebFlux/services/`.
Los nombres siguientes identifican métodos existentes; en casos parametrizados
se cotejaron sus invocaciones en el XML. Cobertura automatizada no sustituye
recorridos contra el servicio levantado con JWT real.

| RF | Escenario | Pruebas verificadas y comportamiento |
|---|---|---|
| RF-02.1 | ESC-02.1 | HttpTests.`esc0201_postPropioDevuelveContratoLocationYETagSinMemberKey`; ReadTests.`esc0205_altaYConsultasSumanSeisSinDuplicarCapacidadFisica`: alta propia y persistencia. |
| RF-02.1 | ESC-02.2 | HttpTests.`esc0202_sinTokenOEncargadoAjenoNoEjecutaServicio`; ReadTests.`esc0202_0204_miembroInexistenteOAjenoRechazaTodoSinFiltrarDatos`; ConcurrencyIT.`putRechazaReferenciasInvalidasYRecursoAjenoSinEscriturasParciales`: permisos y aislamiento POST/PUT. |
| RF-02.2 | ESC-02.3 | ValidatorTests.`esc0203_0204_ordenNoDistingueConjuntosYLaClaveEsCanonica`; ReadTests.`esc0205_altaYConsultasSumanSeisSinDuplicarCapacidadFisica`: conjunto canónico e identidad. |
| RF-02.2 | ESC-02.4 | ValidatorTests.`esc0204_repetidosSeRechazanAntesDeConvertirEnConjunto` y `esc0204_minimoDosSinNullNiUuidInvalido`; ConcurrencyIT.`putExcluyeSuIdentidadPeroRechazaOtroConjuntoYaRegistrado`: entradas inválidas y duplicado excluyendo id propio. |
| RF-02.3 | ESC-02.5 | ReadTests.`esc0205_altaYConsultasSumanSeisSinDuplicarCapacidadFisica` y `coleccionVaciaYLecturasNoIncrementanRevision`: capacidad seis, lista vacía y revisión estable. |
| RF-02.3 | ESC-02.6 | ReadTests.`esc0206_capacidadVigenteEnDosCombinacionesQueCompartenMesa`: ambas sumas reflejan cambio de capacidad física. |
| RF-02.4 | ESC-02.7 | ProtectionIT.`esc0207_cambioLibreConservaIdentidadRestauranteYMesasFisicas`: PUT libre, nuevos integrantes/capacidad e identidad estable. |
| RF-02.4 | ESC-02.8 | ProtectionIT.`esc0208_0211_protegeAgregarRetirarOSustituirEnReservaFuturaYEnCurso`, offset 3600: tres cambios rechazados, configuración y reserva conservadas. |
| RF-02.5 | ESC-02.9 | ProtectionIT.`esc0207_cambioLibreConservaIdentidadRestauranteYMesasFisicas`; ConcurrencyIT.`esc0209_snapshotNoMezclaRevisionYCapacidadesDuranteCambioDeMesa`: write completo y snapshot coherente. |
| RF-02.5 | ESC-02.10 | ConcurrencyIT.`esc0210_altasConcurrentesConOrdenDistintoNoDuplicanConjunto`, `putConcurrentesNoConvergenEnDosConjuntosDuplicados` e `indiceUnicoProtegeAunqueSeOmitaElServicio`: unicidad real y ausencia de parciales. |
| RF-02.4 | ESC-02.11 | ProtectionIT.`esc0208_0211_protegeAgregarRetirarOSustituirEnReservaFuturaYEnCurso`, offset -1800: tres cambios bloqueados durante visita; ConcurrencyIT.`confirmacionConcurrenteNoPermiteCambiarCombinacionComprometida`. |
| RF-02.4 | ESC-02.12 | ProtectionIT.`esc0212_finExactoLiberaSinCambiarSnapshotsHistoricos`: bloqueo antes del fin, aceptación en el fin exacto y conservación histórica. |
| RF-02.6 | ESC-02.13 | FailureIT.`esc0213_0214_rechazoTemporalNoDejaEscriturasYPermiteMismaClave` y `esc0213_0214_putInclusoIdenticoCompruebaReservasYRevierteAnteFallo`: reintento con misma clave tras fallo/demora. |
| RF-02.6 | ESC-02.14 | Los mismos casos FailureIT comprueban rechazo temporal y revisión/recibos/configuración sin cambios, incluso PUT equivalente. |
| RF-02.7 | ESC-02.15 | LegacyIT.`esc0215_consultaPermaneceDisponibleDuranteTransicion`: GET permite consulta sin adaptar ni eliminar legado. |
| RF-02.7 | ESC-02.16 | LegacyIT.`esc0216_legadoStringOBinarioBloqueaAltaSinAdaptarDatos`, `esc0216_putIdenticoOCambiadoNoEvitaLegadoStringOBinario` y `fechaAntiguaSinFinFiableNoSeSuponeFinalizada`: POST/PUT bloqueados, BSON/string e incertidumbre. |

Cobertura adicional comprobada: replay tipado de POST/PUT tras otro write,
If-Match obsoleto, clave reutilizada con otra carga/revisión, cuerpo estricto,
cabeceras inválidas, ETag, Retry-After, gate en WebTestClient, overflow y referencias
persistidas irresolubles. Las carreras mantienen los tres intentos originales y
comprueban reintento posterior cuando el agotamiento acotado es un resultado admisible.

La revisión encuentra pruebas para los 7 RF y 16 escenarios, con casos válidos y
borde. No se modifican casillas funcionales ni se declara aceptación de los RNF
operativos pendientes. El checklist de calidad se conserva en solo lectura:
16/16 marcadas; su nota histórica «5 requisitos/12 escenarios» está desactualizada
frente al spec vigente (7/16) y no se usa para el recuento de cobertura.

## Contrato OpenAPI y límites de la comprobación

Se leyó `specs/002-combinar-mesas/contracts/openapi.json`, OpenAPI 3.1.0:
dos paths y cuatro operaciones, coincidentes con router/handler actuales.

| Operación relativa a /catalog | Cuerpo / cabeceras | Respuesta |
|---|---|---|
| GET `/restaurants/{restaurantId}/table-combinations` | Autorización; sin clave obligatoria | 200, items/revision y ETag |
| POST misma colección | CombinationInput, Idempotency-Key | 201, Combination, Location y ETag |
| GET `/restaurants/{restaurantId}/table-combinations/{combinationId}` | Autorización; sin clave obligatoria | 200, Combination y ETag |
| PUT mismo recurso | CombinationInput, Idempotency-Key, If-Match fuerte | 200, Combination y ETag; identidad conservada |

CombinationInput admite solo tableIds, al menos dos UUID distintos. Combination
contiene id/restaurantId/tableIds/capacity/revision; capacidades y revisión usan int64.
400, 401, 403, 404, 409, 412, 422, 500 y 503 figuran en las operaciones;
errores usan soporte común y 503 incluye Retry-After. No hay DELETE, PATCH,
gestión de turnos ni capacidad editable de combinación.

La inspección nueva parseó JSON, resolvió las cuatro referencias locales distintas
sin destinos ausentes y contrastó rutas, requests, DTO y casos HTTP existentes.
El agente no ejecutó Redocly. Después el usuario aportó el resultado del comando
`npx --yes @redocly/cli lint specs/002-combinar-mesas/contracts/openapi.json --extends minimal`:
contrato válido, sin errores, validación en 170 ms y 8 warnings.

Avisos conocidos a contrastar con Redocly, sin ocultar reglas ni eliminar schemas:

- `no-server-example.com`: server local `http://localhost:8080/catalog`; el ensayo
  del usuario utiliza 8082. No se cambia el contrato para reflejar un puerto local.
- `no-unused-components`: por análisis de referencias quedan siete schemas sin uso
  desde las operaciones: TableInput, TablePatch, Table, ShiftInput, Shift,
  TimeZoneInput y TimeZone. Se conservan y se documenta su deuda.

El resultado aportado confirma exactamente esos ocho avisos (1 + 7). Se registra
como ejecución del usuario, sin silenciar reglas ni modificar OpenAPI. El lint
de SPEC-001 no se utiliza como evidencia del contrato de SPEC-002.

## T060 — Evidencia disponible y pendiente

| Verificación | Estado en SPEC-002 | Evidencia / condición de cierre |
|---|---|---|
| Compilación, selección y descubrimiento de integración | Confirmada | Usuario + XML contados arriba; 184/91 y cero incidencias. |
| Aislamiento, integridad, protección, replay y revisión | Confirmada en automatizadas | 86 casos propios y regresión compartida; no equivale a JWT/HTTP reales. |
| Lint OpenAPI actual | Confirmada por el usuario | Redocly: contrato válido, cero errores y 8 warnings conocidos (localhost + siete schemas). |
| HTTP real autorizado y denegado | Confirmada por el usuario y contrastada con checkpoint | 29 etapas: 401/403, GET 200, POST 201, PUT 200, duplicados 409, If-Match 400/412, conflictos de clave y replay histórico; datos previos conservados. |
| Persistencia tras reinicio | Confirmada tras reinicio declarado por el usuario | GET 200 y comparación de combinación, colecciones, mesas, capacidad, revisión 9 y ETag; el script no reinicia por sí mismo. |
| Gate desactivado/reactivado | Confirmada por el usuario y contrastada con ambos checkpoints | Disabled: catálogo 200 y colección/recurso 404. Enabled: colección/recurso sin token 401, con token 200 y datos/mesas/revisión 9/ETag conservados. |
| Respaldo y restauración | Confirmada por el usuario y contrastada con archivos | Ejecución 20261028T053931Z-7892c3033d144c5a97c7f41f07fd62dd: 19 documentos, dos combinaciones, nueve recibos totales, siete del ensayo, revisión 9 e índice único. Manifiestos y hashes coincidentes; origen intacto. |
| Reversión compatible y retorno | Confirmada por el usuario y contrastada con archivos | Sesión 20261028-173335-a530a760, Previous 4/4 y Current 6/6; manifiestos coincidentes con respaldo, índice/revisiones/recibos y ETag conservados. No se realizó replay HTTP nuevo en esta etapa. |
| Aprobación de cierre | Registrada, 2026-10-28 | Responsable del proyecto, mediante aprobación expresa en esta conversación; nombre no consignado. |

Para el recorrido real se preparó `scripts/dev/Test-LocalCombinations.ps1`, que
reutiliza las identidades y crea tres mesas y dos combinaciones de ensayo, con
checkpoint separado en `secrets/local-identity/combinations-http-checkpoint.json`.
Su sintaxis se revisó sin errores; no fue ejecutado por el agente. Véanse los
[comandos y pasos manuales](disponibilidad-combinaciones-http.md).
El usuario completó consulta/alta/PUT/replay y el reinicio manual. El 2026-10-28
el agente contrastó el checkpoint existente: httpCompleted=true, 29 etapas con
respuesta, final.timestampUtc=2026-10-28T04:54:12.5988083Z y restart.timestampUtc=
2026-10-28T04:57:14.0274927Z (2026-10-27, 23:54/23:57 en America/Lima).
Se conservaron dos combinaciones, cuatro mesas y revisión 9. El log aportado de
IntelliJ muestra autorización y lecturas exitosas; no acredita por sí mismo un reinicio.
La autoría de ejecución es del usuario; la inspección del agente es de solo lectura.

Se preparó `scripts/dev/Test-LocalCombinationGate.ps1` con etapas Disabled/Enabled,
solo GET y evidencia separada en `secrets/local-identity/combinations-gate-checkpoint.json`.
Reutiliza el checkpoint HTTP sin modificarlo y enlaza ambas etapas por hash e
identificador del ensayo. Verifica catálogo, colección/recurso, autenticación y
datos/revisión/ETag al reactivar. Después el usuario ejecutó ambas etapas y
el 2026-10-28 el agente contrastó el historial: Disabled a las 05:24:02.7203075Z
(00:24 en Lima), Enabled a las 05:25:47.7622807Z (00:25 en Lima), 3/6
comprobaciones correctas y vínculo Disabled→Enabled válido. El hash de checkpoint
HTTP coincide y el ensayo es el mismo. No se repitieron peticiones por el agente.
El usuario cambió la variable y reinició manualmente según
[los pasos del gate](disponibilidad-combinaciones-http.md#gate-desactivado-y-reactivado--pasos-manuales).
No reutilizar scripts de mesas suponiendo que prueban combinaciones,
ni fixturear reservas locales o borrar datos para aparentar evidencia.
Las comprobaciones temporales/legacy y fallos ya tienen evidencia automatizada;
cualquier ensayo manual de esas condiciones requiere preparación explícita y aislada.

Se preparó la reutilización de Test-LocalMongoRestore.ps1 con -IncludeCombinations
y un lector Mongo de solo consulta para verificar índice, configuración, revisión
y siete recibos históricos, además del manifiesto completo existente. No se ejecutó
Docker ni respaldo/restauración. [Pasos manuales y límites](disponibilidad-combinaciones-respaldo.md).
Después el usuario ejecutó el respaldo/restauración con éxito. Se contrastaron
spec-002-validation.json, manifiestos de origen/copia y hashes del archive y
checkpoints: coinciden. No se ejecutó una segunda comprobación sobre Mongo.
Se preparó [la reversión compatible](disponibilidad-combinaciones-reversion.md)
contra 72fa5311a0d724582381dd968e226daca6f3d311, con sesión separada y referencia
al respaldo validado. Reversión de versión y cierre siguen pendientes.

## Validación manual de documentación — PowerShell

No hace falta repetir suites Java por documentación y preparación del script
local. Redocly ya fue ejecutado por el usuario con el resultado registrado arriba.
Si cambia el contrato, desde `<WORKSPACE>`, repetir:

```powershell
npx --yes @redocly/cli lint specs/002-combinar-mesas/contracts/openapi.json --extends minimal
```

Si posteriormente cambia código, desde la raíz de SpringWebFlux y con Docker
disponible para integración, los comandos existentes siguen siendo:

```powershell
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Availability*' --tests '*ReservationCrudServiceImplTests'
.\gradlew.bat integrationTest
```

## Git Bash — separado de validación

Desde SpringWebFlux, revisar y versionar documentación y el script preparado:

```bash
git add scripts/dev/Test-LocalMongoRestore.ps1 scripts/dev/read-combination-backup-requirements.js README.md docs/disponibilidad-combinaciones-respaldo.md docs/disponibilidad-combinaciones-http.md docs/disponibilidad-combinaciones-validacion.md
git diff --cached --check
git diff --cached --stat
git commit -m "test: extend isolated restore verification to table combinations"
```

specs, planes, tasks y quickstart siguen fuera del Git de este servicio.
