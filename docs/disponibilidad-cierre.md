# SPEC-001 — Gestion de mesas: cierre aprobado

**Estado vigente: cerrada y aprobada por el usuario el 2026-10-27 (America/Lima).**
Aprobacion explicita: «apruebo el cierre de SPEC-001». T040 completada: **41/41
tareas** en SPEC-001; epica **41/88 completadas y 47 pendientes (0/20/27)**.
SPEC-002/003 no iniciadas. Las notas de entregas posteriores son historial;
los pendientes antiguos quedan resueltos por la evidencia vigente de este cierre.

Autor de las ejecuciones de validacion: usuario responsable del proyecto.
Autor de la implementacion asistida, scripts y revision documental: agente.
El agente contrasto archivos de evidencia y XML existentes; no repitio suites,
arranques, escrituras HTTP, respaldos o migraciones durante este registro ni hizo commits.
No se versionan dumps, JWT, claves, .env ni archivos privados de evidencia.

## Evidencia disponible

Fase 4 confirmada por el usuario y contrastada con build/test-results:
127 casos seleccionados de test y 52 de integrationTest, todos sin fallos, errores
ni omitidos. Commits: 4c421 y 81f0e.
No son resultados de la instrumentación nueva. La suite test completa, que incluye
contextLoads, no está acreditada por una selección filtrada.

## Instrumentación de T038

Propiedad única SPEC-001: AvailabilityTelemetry y AvailabilityMetricsConfig,
consumidos por el coordinador y AvailabilityHttpSupport. Micrometer core usa la
versión gestionada por Spring Boot. El registry por defecto es SimpleMeterRegistry;
si existe otro MeterRegistry se reutiliza. No se abrieron endpoints Actuator ni
se configuró un exporter. Los contadores son internos y se reinician con el proceso.

Cada suscripción lógica produce un evento key=value con operationId, restaurantId
(UUID o unknown), operation, outcome, code y durationMs. No se registran body,
label, JWT, claves de idempotencia, fingerprints, excepciones ni mensajes del driver.
El operationId se propaga en Reactor Context entre coordinador y handler, incluso
con cambios de hilo; el Error HTTP usa ese mismo ID. No depende de MDC.
Un replay genera un resultado replay en el coordinador, no un fallo ni otra escritura.
El commit incierto conserva OPERATION_OUTCOME_UNKNOWN y no afirma rollback.
Una avería del registry no convierte un commit confirmado en un fallo de negocio.

| Métrica | Uso |
|---|---|
| availability.operations | Contador de resultados de operaciones lógicas. |
| availability.operation.duration | Timer de duración monotónica por suscripción. |
| availability.conflicts | Rechazos finales 409/412, no cada reintento interno de Mongo. |
| availability.legacy.blocks | Rechazos LEGACY_RESERVATION_BLOCK. |
| availability.failures | Resultados error, incluidos fallo de comprobación y commit incierto. |

Etiquetas acotadas: operation=http/write/read/legacy, outcome=success/replay/rejected/error/cancelled
y códigos fijos. Los UUID no son etiquetas. HTTP y coordinador son capas distintas:
filtrar operation al sumar resultados, pues una petición puede registrar ambas.
La duración HTTP mide la construcción de ServerResponse, no el envío completo.
Los rechazos JWT/gate de la cadena de seguridad suceden antes del handler y quedan
fuera de estas métricas HTTP; no se presenta este registro como auditoría de autenticación.

Se cambió Mongo de DEBUG a INFO para evitar documentos de consulta en logs.
Se retiró el CommandLineRunner de demostración que se suscribía e imprimía datos al
arrancar. No se tocaron las rutas/DTO antiguos ni los presupuestos transaccionales.
Solo queda block en el bootstrap acotado del inicializador; no en las solicitudes.
Planner/Redis siguen fuera de la sesión de disponibilidad.

AvailabilityTelemetryTests añade diez casos de suscripción diferida, Mono<Void>,
rechazo/legado, fallos, replay, cancelación, etiquetas seguras, correlación reactiva
y fallo del registry. Casos redactados y compilados, sin ejecutar.

## Validación incremental para el usuario

PowerShell o terminal de IntelliJ, con JDK 21:

```powershell
Set-Location <WORKSPACE>\SpringWebFlux
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Availability*' --tests '*ReservationCrudServiceImplTests'
.\gradlew.bat integrationTest
```

Esperados: **137 casos seleccionados** y **52 de integración**. Docker debe estar
disponible para los fixtures efímeros de integración; no usan los datos locales.
Revisar conteos, failures/errors/skipped en build/test-results y los informes HTML
de build/reports/tests. NO-SOURCE no acredita validación. UP-TO-DATE reutiliza un
resultado previo; --rerun-tasks permite una ejecución nueva si hace falta.

Suite completa, solo con Mongo replica set y Redis locales ya preparados:

```powershell
.\gradlew.bat test
```

No reemplazar ni omitir contextLoads para aparentar validación del entorno.

Contrato, desde la raíz de documentación:

```powershell
Set-Location <WORKSPACE>
npx --yes @redocly/cli lint specs/001-gestionar-mesas/contracts/openapi.json --extends minimal
```

Evidencia histórica: contrato válido con siete warnings (localhost y seis componentes
compartidos no usados). No se suprimieron reglas ni componentes. El agente no ejecutó
este lint ahora; aportar el resultado de la versión actual. La matriz de los ocho RF
y veinte escenarios está fuera del repo, en specs/001-gestionar-mesas/trazabilidad.md.

## T040 — Estado vigente al 2026-10-27 (America/Lima)

| Comprobación | Estado actual | Evidencia necesaria |
|---|---|---|
| Selección e integración de fase 4 | Confirmadas: 127/52 | XML existentes y confirmación del usuario. |
| Pruebas tras T038 | Confirmadas por el usuario: 137/52 sin fallos | No se repitieron suites durante esta actualización documental. |
| Lint actual | Confirmado por el usuario: válido, siete warnings | localhost y seis componentes compartidos no usados. |
| Suite completa con contextLoads | Confirmada por el usuario: 138/138 | Entorno local preparado; no se repitió durante esta actualización. |
| Recorridos HTTP con emisor real | Confirmados: 15 comprobaciones aprobadas | Captura del usuario y http-validation.json; detalle debajo. |
| Persistencia tras reinicio | Confirmada por el usuario y archivo de evidencia | Mismo recurso y valores, capacidad 6, revisión 2 y ETag coherente. |
| Gate y compatibilidad | Confirmados: lectura, replay y writers antiguos en ambos gates | CRUD antiguo aprobado con gate=false/true, revision de B 0 a 3 y 3 a 6, fixtures eliminadas y A intacto. |
| Respaldo/restauración de la base local | Confirmado: 7 documentos en 4 colecciones, sin diferencias | validation.json y manifiestos del ensayo aislado, sin cambios en origen. No acredita migración del Mongo antiguo. |
| Reversión de versión de aplicación | Confirmada: JAR anterior compatible y vuelta a IntelliJ actual | Commit 81f0e6, Previous 200/404 y Current 200/401/200; hash del JAR contrastado y Mongo sin cambios. |
| Aprobación formal | Confirmada — 2026-10-27 | Usuario: «apruebo el cierre de SPEC-001». |

Los IT prueban condiciones aisladas de arranque/gate/transacciones; no sustituyen
las comprobaciones del despliegue real. No habilitar ni migrar automáticamente.
La reversión debe seguir el diseño compartido, sin borrar colecciones ni volúmenes.

### Evidencia HTTP y reinicio recibida

Resultados ejecutados por el usuario, con Eats Hub en 8082, Keycloak en 8180 y
Mongo replica set en 27018. Tras asignar basic al cliente, los tokens incluyen sub;
el backend conserva la validación de firma, emisor, audiencia, vigencia y sujeto.

Se contrastaron los archivos privados secrets/local-identity/http-validation.json
(2026-10-27T05:02:33Z) y restart-validation.json (2026-10-27T05:05:39Z) con las
capturas aportadas. No se copian secretos ni los archivos privados al repositorio.
El primer archivo conserva restartVerified=false porque describe el recorrido
previo; el segundo acredita la comprobación posterior con operatorDeclaredRestart=true.
El reinicio fue realizado y declarado por el usuario; el agente no lo ejecutó.

Los 15 estados esperados coinciden: sin token 401; encargado ajeno y usuario sin
rol 403; consulta propia 200; alta y replay POST 201; misma clave con otro payload
409; PATCH y replay 200; revisión obsoleta 412; campo desconocido 400; capacidad
inválida 422; etiqueta duplicada 409; mesa inexistente 404; consulta final 200.
El script también compara cuerpo y cabeceras de replay, Location en POST y ETag.
Después del reinicio el GET devolvió 200 para la misma mesa. Ambos archivos
conservan identidad, propietario, etiqueta, capacidad 6 y revisión 2; el script
verifica que ETag corresponda a la revisión de la respuesta.

### Limites del cierre aprobado

No quedan comprobaciones pendientes de T040 dentro del alcance local acordado.
La reversion usa una version compatible que conserva guard y esquema, no una
version sin coordinacion. El ensayo no restaura una copia vieja sobre datos nuevos.
La vuelta a IntelliJ fue declarada por el usuario; no se presume identidad automatica
del build actual por su puerto. No acredita despliegue productivo, migracion del
Mongo antiguo, integracion externa real de Planner ni implementacion de SPEC-002/003.

Esta actualización solo registra evidencia y revisa pendientes. No ejecuta pruebas,
reinicia servicios, cambia gates, respalda/restaura o migra datos ni crea commits.
T040 queda marcada con evidencia y aprobacion explicita; SPEC-002/003 no se han iniciado.

### Evidencia final — reversion y aprobacion

Ensayo 20261027-230840-4011c689: bootJar anterior compilado por el usuario desde
81f0e6145fbf8c82fd81fae7669aa82d3c9660f5, sin suites, sin cambiar checkout.
previous-validation.json (2026-10-27T23:14:16Z) identifica el proceso del JAR
preparado, catalogo 200 y mesas 404 con gate=false. current-validation.json
(23:17:14Z) confirma catalogo 200, autenticacion 401 y mesa 200 con datos/revision
y ETag conservados al volver a la aplicacion actual con gate=true.
Ambos archivos declaran databaseUnchanged=true, mismo ensayo y SHA-256 del JAR;
hash contrastado con el archivo existente. Los artefactos y el manifiesto nuevo
de Mongo se conservan en backups/availability-rollback/, fuera de Git.
El usuario ejecuto ambas versiones y aprobo despues el cierre explicitamente.

Los XML existentes acreditan 138/138 test y 52/52 integrationTest, sin fallos,
errores ni omitidos. Seleccion previa 137/137 y lint valido con siete warnings
aportados por el usuario. La matriz externa mantiene 8 RF y 20 escenarios.
No se ejecutaron nuevos comandos de pruebas o servicios para registrar la aprobacion.

### Continuacion — gate confirmado y respaldo preparado

El usuario completo las dos etapas despues de las escrituras. Se contrastaron
gate-disabled-validation.json (2026-10-27T05:18:20Z) y
gate-enabled-validation.json (2026-10-27T05:20:37Z), ambos ligados al mismo recorrido
HTTP y mesa. Tres comprobaciones por etapa, todas aprobadas: catalogo 200 y mesas
ocultas con false; catalogo 200, sin token 401 y misma mesa 200 con true. El script
compara datos, revision y ETag al reactivar. Son lecturas; no acreditan writers
antiguos ni replay de recibos, y el gate no equivale a rollback de version.

Se preparo [el ensayo de respaldo/restauracion local](disponibilidad-respaldo-local.md).
Requiere detener todos los writers y restaurar solo en un contenedor nuevo sin
red externa ni puertos. Compara colecciones, documentos BSON, indices, opciones
y origen sin cambios. No se ejecuto este ensayo, no hay evidencia de restauracion
todavia y T040 permanece abierto. No se hicieron commits ni se avanzaron otras specs.

### Evidencia vigente — respaldo/restauracion local aprobado

El usuario ejecuto Test-LocalMongoRestore.ps1 con writers detenidos. Ensayo
20261027T053631Z-522c7f246054460082639b1defc41b0b; validation.json de
2026-10-27T05:36:42Z declara restoreVerified=true y sourceUnchanged=true.
Se contrastaron manifiestos y SHA-256 del archive privado: 4 colecciones,
7 documentos (restaurants 2, restaurant_tables 1, restaurant_operations 2 y
operation_receipts 2), documentos e indices coincidentes en el destino aislado.
El origen conserva su contenido. Backup, contenedor y volumen del ensayo se
conservaron; no se restauraron datos sobre 27018 ni sobre el Mongo antiguo.
El usuario detuvo los writers y ejecuto la restauracion; el agente reviso evidencia.

Esto acredita conservacion de recibos en la copia restaurada, pero aun no el
comportamiento de replay HTTP tras el gate. Se preparo
[la comprobacion del recibo original](disponibilidad-replay-recibos.md): el agente
verifico por lectura su existencia y el fingerprint reconstruido, sin enviar POST.
Siguen pendientes ejecutar ese recorrido, comprobar writers antiguos, ensayar
reversion de version y recibir aprobacion formal. T040 sigue sin marcar.

### Evidencia vigente — replay original aprobado; writers antiguos preparados

El usuario confirmo el replay. Se contrasto receipt-replay-validation.json
(2026-10-27T17:05:55Z), vinculado a la misma mesa, recorrido HTTP y gate.
POST original 201 con cuerpo/Location/ETag originales; mesa actual, revision,
documentos, recibos e indices sin cambios. El agente no ejecuto estas peticiones.

Se preparo [la compatibilidad de reservas antiguas](disponibilidad-reservas-antiguas.md):
fixture nueva en B, CRUD HTTP con gate=false y true, revision +1 por write y
conservacion de A. No se ejecutaron esas etapas. Se mantiene el contrato antiguo
y el simulador Planner existente. Faltan estas comprobaciones, reversion de version
y aprobacion formal. T040 sigue sin marcar; SPEC-002/003 no iniciadas.

### Evidencia vigente — writers antiguos aprobados y reversion preparada

Se contrastaron legacy-disabled-validation.json (2026-10-27T22:54:42Z) y
legacy-enabled-validation.json (2026-10-27T22:58:02Z): 6/6 comprobaciones HTTP por
etapa, create/update/delete con revision +1 cada uno. B paso de 0 a 3 y luego de
3 a 6, ambas fixtures se eliminaron y A no cambio. Son recorridos secuenciales
con el simulador Planner existente, no una integracion externa real.

Solo faltan reversion de version y aprobacion formal. Se preparo
[el ensayo de version anterior compatible](disponibilidad-reversion-version.md)
con commit fijo 81f0e6145fbf8c82fd81fae7669aa82d3c9660f5. Mantiene guard y esquema;
su JAR se compilara en copia separada, se arrancara con gate=false y luego se
volvera a IntelliJ con gate=true. Se compara un manifiesto nuevo de Mongo antes,
durante y despues. No se arranco ni compilo el JAR ni se ejecutaron suites o
peticiones por el agente. T040 sigue sin marcar; no hay aprobacion implicita.

## Recorrido HTTP reproducible, cuando el entorno esté preparado

Usar servicio ya iniciado por el responsable, restaurante existente y JWT auténticos
configurados fuera del código. No publicar tokens, datos personales ni dumps de .env.
Los comandos siguientes crean una mesa de verificación con etiqueta única; no borran datos.
Configurar EATS_HUB_RESTAURANT_ID y EATS_HUB_MANAGER_TOKEN en el entorno local.
No se ejecutó este recorrido por el agente.

```powershell
$apiBase='http://localhost:8082/catalog'
$ownerId=[guid]::Parse($env:EATS_HUB_RESTAURANT_ID).ToString()
$headers=@{Authorization='Bearer '+$env:EATS_HUB_MANAGER_TOKEN}
$collection="$apiBase/restaurants/$ownerId/tables"
$label='Verificacion-'+[guid]::NewGuid().ToString('N')
$headers['Idempotency-Key']=[guid]::NewGuid().ToString()
$payload=@{label=$label;capacity=4} | ConvertTo-Json
$created=Invoke-WebRequest -UseBasicParsing -Method Post -Uri $collection -Headers $headers -ContentType 'application/json' -Body $payload
$table=$created.Content | ConvertFrom-Json
$replay=Invoke-WebRequest -UseBasicParsing -Method Post -Uri $collection -Headers $headers -ContentType 'application/json' -Body $payload
# Comparar 201, cuerpo, Location y ETag de created/replay; deben coincidir.
$headers['Idempotency-Key']=[guid]::NewGuid().ToString()
$headers['If-Match']=[string]$created.Headers['ETag']
$patched=Invoke-WebRequest -UseBasicParsing -Method Patch -Uri "$collection/$($table.id)" -Headers $headers -ContentType 'application/json' -Body (@{label=$label+'-Nueva';capacity=6} | ConvertTo-Json)
$expected=$patched.Content | ConvertFrom-Json
$readHeaders=@{Authorization=$headers['Authorization']}
$beforeRestart=Invoke-WebRequest -UseBasicParsing -Uri "$collection/$($table.id)" -Headers $readHeaders
```

Conservar table.id y expected. Detenerse aquí: el reinicio lo realiza el responsable,
siguiendo el procedimiento del entorno. Después del reinicio, con un JWT vigente:

```powershell
$afterRestart=Invoke-WebRequest -UseBasicParsing -Uri "$collection/$($table.id)" -Headers $readHeaders
$actual=$afterRestart.Content | ConvertFrom-Json
# Verificar id/restaurante/label/capacity iguales a expected; ETag coherente con actual.revision.
```

Entre POST y PATCH no deben intervenir otros writes de ese restaurante; si los hay,
obtener un GET actualizado y construir un comando nuevo con su If-Match.
Para rechazos probar también sin token (401), encargado ajeno (403), recurso
inexistente (404), headers/body inválidos (400/422), etiqueta duplicada (409) y
If-Match obsoleto (412). Casos de legado/protección y fallos se prueban únicamente
con datos y dependencias controlados; conservar snapshots antes/después.
Registrar estados, IDs técnicos y resultados, sin capturas que expongan JWT.

La comprobación afterRestart solo acredita reinicio si el responsable realizó el
reinicio entre ambas consultas. Ejecutarlas seguidas no acredita persistencia.

## Git sugerido, solo después de validar

Primer commit: instrumentación y pruebas; segundo: guía versionable.

```bash
cd /d/proyectosIntellij/SpringWebFlux
git add build.gradle src/main/java src/main/resources/application.properties src/test/java src/integrationTest/java
git diff --cached --stat
git commit -m "feat: instrument availability operations with safe logs and metrics"
git add docs/disponibilidad-cierre.md docs/disponibilidad-mesas-patch.md
git diff --cached --stat
git commit -m "docs: record availability validation and pending release checks"
```

Los artefactos de specs permanecen fuera de Git del servicio.



## Continuacion: identidad local preparada

El usuario confirmo 137 pruebas seleccionadas, 52 de integracion y la suite completa
138/138, junto con OpenAPI valido con los siete warnings conocidos.
La aplicacion arranco en 8082 con Mongo replica rs0 en 27018.
GET de catalogo devolvio 200 y GET de mesas 404 con el gate deshabilitado.

Se preparo Keycloak local 26.8.1 (8180), tres usuarios y dos restaurantes aislados.
Discovery, JWK y Device Authorization verificados; preparacion repetida sin sobrescribir.
La configuracion .env ya apunta al emisor y habilita disponibilidad para el proximo
reinicio manual. No se obtuvieron JWT de usuarios ni se comprobaron escrituras HTTP
autenticadas o persistencia tras reinicio en este bloque. No hubo suites ni commits.
[Comandos de una linea y estado de la evidencia](identidad-local.md).
T040 continua pendiente; no se infiere cierre de la preparacion del proveedor.
