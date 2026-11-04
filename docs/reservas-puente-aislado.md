# Harness aislado del puente de SPEC-005

El usuario comunicó la validación integrada actual con 12 grupos sintéticos Passed
y sintaxis JavaScript Passed, en `bridge-all-synthetic-d76dca93d66a4ea5973c1f83a43aa7a8`.
No acredita ejecución real ni aprobación.

Implementación integrada. El usuario comunicó OK de los cinco scripts sintéticos
indicados abajo y, después, de ReviewAssertions y ExecutionAssertions. La nueva
regresión posterior de Review, corte, recuperación y ejecución terminó OK según el
usuario. La comprobación de reversión instrumentada también terminó con su mensaje
final OK según el usuario, tras una salida anterior incompleta. El candidato
`20261104T183001Z-1fee331299b24ac5981c58fa9193eceb` está Prepared; aislamiento
real y revisión real permanecen pendientes.

VerifyIsolated ya conecta preflight local, pruebas de fuente exportada, diagnóstico
C1, recursos nuevos, observador, autocomprobación, catálogo HTTP y sellado de
reportes. No llama Review ni autoriza corte. Los OK sintéticos no acreditan captura
ni aislamiento real.

Cada intento usa una carpeta verification-UUID bajo el candidato, con un entorno
y recursos de nombre único. Se conservan scripts con hash, manifiestos, configuración
efectiva, adjuntos y reportes. Se detienen exclusivamente contenedores propios; no
se eliminan redes, contenedores, archivos anteriores ni checkpoints.

## Comprobaciones puras

Desde la raíz del servicio, una sola entrada; requiere PowerShell5.1, Python3
y Node para pruebas y sintaxis locales. No requiere servicios ni descarga herramientas.

```powershell
powershell.exe -NoProfile -File .\scripts\dev\Test-ReservationBridgeAllAssertions.ps1
```

El ejecutor conserva un log por comprobación y summary.json, verifica código de
salida y mensaje final y no declara éxito con casos fallidos o pendientes.
La comprobación de orquestación sustituye todas las fronteras externas: verifica
orden, aborto previo a HTTP y conservación de cuatro reportes sin producir Review.
Sus resultados nunca acreditan captura ni aislamiento real.

## Ejecución operativa posterior

No es el siguiente comando que deba ejecutarse ahora. El orden del SDD sigue
siendo integrar consumidores finales, validar sus controles, congelar hashes,
preparar el candidato y después producir evidencia real.

VerifyIsolated exige Candidate, ExecutedBy, IsolationImages y AllowIsolatedExecution.
IsolationImages es un JSON con exactamente mongo, redis, java y tools, cada valor
una referencia repositorio@sha256:digest real o el ID completo e inmutable
sha256 de una imagen local. Docker debe devolver el mismo ID para cada contenedor
creado con un ID local. Las cuatro imágenes deben existir localmente: el ejecutor
nunca solicita pull. No copiar hashes inventados como evidencia.

Las imágenes deben proporcionar Mongo con mongosh; Redis; Java21 con /bin/sh y
sha256sum; y herramientas con Python3, strace y /bin/sh. Las imágenes se inspeccionan antes
de crear recursos. Variables heredadas no autorizadas o volúmenes implícitos
ajenos bloquean. Mongo/Redis usan exclusivamente tmpfs identificados del ensayo.

Se requiere contenedores Linux y un engine que imponga el modo bridge
gateway_mode_ipv4=isolated, IPv6 desactivado y ausencia de ruta predeterminada.
El DNS propio no reenvía consultas. Si la plataforma no soporta las restricciones,
no se inicia el JAR.

El observador recibe exactamente NET_RAW y SYS_PTRACE, seccomp de lista permitida
y no-new-privileges; comparte los namespaces de red y PID de APP, sin montajes.
Compartir PID permite trazar y detener exclusivamente procesos del ensayo ante
una anomalía; nunca se usa PID o red del host. Conserva metadatos, no payload.
El centinela es un servidor nuevo en otra red, con controles positivos y registros
independientes de la captura. AF_PACKET observa paquetes permitidos y strace
observa los intentos permitidos/denegados, incluso cuando no se emite un paquete.

A1: el responsable autorizó el método combinado y el contrato pasa a 1.4.0.
El launcher de cada sonda/JVM se detiene antes de exec y continúa únicamente al
verificar TracerPid. Se conservan ventanas de traza y syscallCoverage por hash;
ausencia de strace, sintaxis no cubierta, desconexión del trazador, syscall no
admitida o fallo de captura impiden Passed. Esto implementa una vía operativa
para no-route sin añadir rutas ni autorizar al centinela. Su ejecución real y
compatibilidad con Docker Desktop siguen pendientes de validación.

Durante el recorrido se revalida el observador antes/después de cada petición,
se conserva el namespace al cambiar gates, se comprueba el proceso efectivo y el
hash del JAR montado antes/después. Las lecturas y rechazos deben conservar los
manifiestos completos de documentos, índices y recibos.

SOURCE_EXPORTED exige Gradle local de la versión del candidato, dependencias y
JDK21 disponibles sin descargas. Se usa una extracción nueva y se ejecutan solo
cuatro pruebas propietarias del puente; nunca bootJar. Si no se dispone de la
herramienta, esos casos permanecen Pending.

## Estados y límites C1

Los grupos LEG/V2/BARRIER solo pueden ser Passed con sus casos completos y una
misma evidencia ISO validada por hash. Una alteración de candidato, catálogo,
scripts o JAR invalida el sellado; un fallo del entorno/captura invalida HTTP.

El ejecutor C1 enumera los 54 IDs y ejercita el guard real con lector y acciones
instrumentados, sin transporte del origen. El guard aislado no acredita la etapa
operativa completa. Se implementó un ejecutor de la entrada
histórica real copiada por hash para los 36 casos NOCUT/CUT/READFAIL de los tres
modos y cuatro etapas, con política y comandos externos instrumentados. NOCUT se
detiene en el siguiente prerrequisito o frontera; CUT/READFAIL exigen el rechazo.
Los casos de JAR y evidencia alterados utilizan el consumidor gestionado y un control
positivo previo sobre revisión sintética. El usuario comunicó OK de CatalogAssertions,
ExecutionAssertions y RollbackAssertions tras corregir el ámbito del doble.
Posteriormente se preparó el ejecutor de los 16 casos restantes: las 12 etapas
gestionadas, tres carreras y SESSION-HISTORY. Esa versión aún no se ha ejecutado.
Las etapas gestionadas reusan la cadena v2 sintética y los validadores reales de
respaldo, sesión y política. Los transportes Git/Mongo/HTTP/JVM se sustituyen por
funciones; no se arranca una JVM ni se contacta una base. CUT debe completar la
etapa, y los negativos deben rechazar con archivos intactos y cero acciones
prohibidas. Current compara GET, ETag y estado persistido sintéticos.
Las carreras usan sesiones creadas por Prepare y un StartPrevious positivo con
doble antes de probar una rama con corte, conservando ambos checkpoints.
La compilación histórica se sustituye como función durante esos casos; el comando
normal de bootJar conserva su comportamiento. No se introduce un modo de omisión
de C1 en la CLI. Un fallo de preparación/control positivo conserva Pending.
Los casos solo se aprueban cuando se verifican sus condiciones; CatalogAssertions
exige los 54 casos y muestra el detalle de cualquiera incompleto.
No se simulan 54 aprobados ni reversión real. Por tanto el resultado
global puede ser Pending aun si los grupos HTTP pasan.

La emisión de Review exige cuatro reportes Passed. Review está implementado,
con validación sintética comunicada antes de los cambios posteriores; mantiene T130 abierta.

## Review local

Stage Review exige Candidate, Reports (cuatro rutas) y ReviewedBy explícito.
No arranca servicios, ejecuta pruebas ni recompila. El catálogo se toma de la
ruta SDD de la implementación, no de un archivo elegido por el reporte.

Revalida candidato/JAR/procedencia, grupos e IDs, niveles, booleanos, fechas,
autores, referencias y adjuntos. Los tres grupos HTTP deben compartir evidencia
ISO válida. Comprueba además la identidad de los scripts actuales frente a sus
snapshots y la sonda/controles/registros del servidor independiente del centinela.
Un guard C1 aislado o un reporte Pending no se convierte en aprobación.

Los insumos permanecen abiertos sin permiso de escritura mientras se vuelve a
validar la cadena y se publica bridge-evidence.json. El archivo definitivo se
crea mediante renombrado sin sobrescritura de un staging privado completo.
Un staging interrumpido se conserva con extensión .tmp; no se publica como
revisión. Una revisión existente se conserva y rechaza una segunda publicación.

Comprobación pura, preparada para ejecución del usuario:

```powershell
powershell.exe -NoProfile -File .\scripts\dev\Test-ReservationBridgeReviewAssertions.ps1
```

La comprobación reutiliza en un scope separado las fixtures del comparador,
añade scripts y prueba independiente sintéticos y bloquea transportes externos.
Un resultado OK no acredita aislamiento, corte, reversión o aprobación de spec.

Solo cuando existan los cuatro reportes reales Passed, la llamada operativa será
desde PowerShell (el arreglo se evalúa dentro de esa misma sesión):

```powershell
& .\scripts\dev\Prepare-LocalReservationBridge.ps1 -Stage Review -Candidate '<candidate.json absoluto>' -Reports @('<LEG.json>','<V2.json>','<BARRIER.json>','<C1.json>') -ReviewedBy '<revisor explícito>'
```

Las rutas de reportes deben permanecer bajo la raíz del candidato; se admiten
rutas absolutas internas o relativas a ella. Review no acepta banderas true
manuales ni una salida alternativa. No requiere AllowBuild ni
AllowIsolatedExecution. Las nuevas modificaciones de scripts invalidan reportes
anteriores que los referencien; congelar versiones finales antes de producir
evidencia real. Las integraciones de corte y reversión están preparadas y sus dobles
terminaron OK según el usuario; no acreditan corte ni reversión reales.

## Protección del corte

El script Set-LocalReservationCutover recibe BridgeEvidence v2 revisada y
comprueba toda su cadena antes de consultar configuración, puerto, JWT o Mongo.
Rechaza esquemas antiguos, booleanos no estrictos, reportes incompletos y
alteraciones de evidencia, catálogo, JAR, adjuntos o scripts evaluados.

Inmediatamente antes de Apply vuelve a validar la misma evidencia y catálogo;
mantiene abiertos sin permiso de escritura los archivos de la cadena y scripts
actuales durante la acción. Esto conserva los demás prerrequisitos existentes:
escritores detenidos, gate apagado, respaldo restaurable y JWT válidos.

Comprobación pura preparada para el usuario:

```powershell
powershell.exe -NoProfile -File .\scripts\dev\Test-ReservationBridgeCutoverAssertions.ps1
```

Reutiliza exclusivamente fixtures sintéticas de Review. Cuenta accesos a red,
configuración, HTTP y Docker ante evidencia inválida y simula alteraciones antes
de Apply. Un OK no acredita respaldo real, aislamiento ni corte.
