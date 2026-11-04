# Ensayo local de reversion de version — T040

**Ejecutado y aprobado por el usuario; cierre de SPEC-001 aprobado el 2026-10-27.**
Ensayo 20261027-230840-4011c689: Previous paso a 23:14:16Z y Current a 23:17:14Z.
El usuario compilo y ejecuto el JAR anterior, y volvio a IntelliJ actual.
Catalogo 200/mesas 404 en anterior; 200/401/200 y mesa/ETag conservados en actual.
Ambos manifiestos sin diferencias; evidencia privada y SHA-256 del JAR contrastados
por el agente. No se repitieron suites ni se ejecutaron servicios al registrar esto.
Las instrucciones debajo describen el ensayo realizado y su posible reproduccion;
no se requiere repetirlo para acreditar este cierre. No basta el gate por si solo.

## Version elegida y limites

Anterior: 81f0e6145fbf8c82fd81fae7669aa82d3c9660f5, fase 4, anterior a la
instrumentacion de T038. Conserva JWT, mesas/PATCH y coordinacion de reservas.
Se reviso que esquema, MongoConfig, inicializador y ReservationCrudServiceImpl
no difieren del HEAD inspeccionado. No representa retorno a una version sin guard
ni retiro de esquemas, migracion, restauracion de la base antigua o alta disponibilidad.

La exportacion utiliza git archive con ese commit fijo, sin checkout, reset,
stash, add, commit ni worktree. Los cambios locales de documentacion se conservan.
La preparacion exige codigo productivo rastreado sin diferencias frente a HEAD;
si difiere, revisar antes de continuar, sin descartarlo automaticamente.
Compila solo bootJar en backups/availability-rollback/<ensayo>/src, sin suites.
No se copian .env ni secretos al codigo exportado. Fuente, JAR, hash y manifiesto
quedan privados y excluidos de Git. Los comandos git de exportacion son de lectura
del historial y escritura del archivo privado, no modifican el indice ni la rama.

El script de arranque usa la raiz original como working directory para leer .env,
mantiene Mongo 27018 y fuerza --availability.enabled=false y puerto 8082 en el
JAR anterior. No altera .env. La version anterior tiene una lectura demostrativa
de Italian al arrancar; se reviso que no escribe. Se fuerza logging Mongo a INFO.
El JAR se verifica por SHA-256, y al validar Previous se comprueba que el proceso
que escucha en 8082 sea el que ejecuta ese JAR exacto.

No ejecutar ambas versiones a la vez. Detener TODOS los writers y no hacer suites
ni escrituras manuales durante el ensayo. El script comprueba 8082 libre al preparar
y arrancar, pero esa comprobacion no descubre todas las instancias/clientes posibles.
No se borra ningun dato ni volumen, ni se aplica el backup anterior sobre Mongo.

## 1. Preparar, con IntelliJ detenido

Desde la raiz del servicio, con Docker/Mongo activos y todos los writers detenidos:

~~~powershell
& .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage Prepare -WritersStopped
~~~

Lee la evidencia aprobada de ambas etapas de reservas antiguas, captura un
manifiesto NUEVO (incluye la revision de B posterior a esas pruebas), exporta el
commit y compila bootJar. Comprueba que Mongo no haya cambiado durante la preparacion.
No arranca el JAR. Requiere JDK 21 y dependencias Gradle disponibles; no ejecuta tests.

Solo admite una sesion privada rollback-session.json: si ya existe, se detiene
sin sobrescribir evidencia. Ante un fallo, conservar los archivos y revisar antes
de repetir. No borrar cambios locales ni datos para forzar el procedimiento.

## 2. Arrancar el JAR anterior en una segunda PowerShell

En otra terminal, tambien desde la raiz del servicio:

~~~powershell
& .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage StartPrevious
~~~

Dejar esa terminal abierta. Ejecuta Java en primer plano: esperar Started
SpringWebFluxApplication. IntelliJ debe seguir detenido; no iniciar otro writer.

## 3. Validar la version anterior desde la primera PowerShell

~~~powershell
& .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage Previous
~~~

Esperado: proceso del JAR preparado, catalogo 200, mesas 404 y manifiesto Mongo
identico al estado previo (documentos BSON, indices, revisiones y recibos).
Solo lee por HTTP/Mongo; no crea ni modifica reservas. Guarda previous-validation.json.

## 4. Volver a la version actual

Detener el JAR anterior con Ctrl+C en SU terminal. Despues iniciar la aplicacion
actual desde IntelliJ en 8082, con AVAILABILITY_ENABLED=true. No cambiar Mongo ni
restaurar un dump. En la primera PowerShell, obtener un token vigente:

~~~powershell
& .\scripts\dev\Get-LocalToken.ps1 -User encargado-a -CopyPassword
~~~

~~~powershell
& .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage Current
~~~

Esperado: el proceso del JAR anterior ya no atiende 8082; catalogo 200, mesas sin
token 401, mesa original autenticada 200 con mismos datos/revision y ETag coherente.
El manifiesto completo debe seguir igual al previo. Se registra current-validation.json
con operatorDeclaredCurrentRestart=true: el usuario debe haber vuelto realmente
a su configuracion actual de IntelliJ. No se presenta como prueba automatica de
identidad de build del proceso IntelliJ ni como ensayo de despliegue de produccion.

## Cierre y fallos

La sesion privada registra commit objetivo, commit actual al preparar, SHA-256 del
JAR anterior y timestamps. Un fallo mantiene el ensayo pendiente; conservar archivos
y detenerse, sin ignorar diferencias de manifiesto ni restaurar una copia vieja.
Al terminar, queda la version actual con gate=true y los artefactos anteriores
conservados. El agente no ejecuta estos comandos, suites, arranques ni commits.
T040 solo podra cerrarse al revisar los resultados y recibir aprobacion explicita.

Tras validar todo el bloque, desde Git Bash (sin secretos ni backups):

~~~bash
git add scripts/dev/Test-LocalVersionRollback.ps1 scripts/dev/Test-LocalLegacyReservations.ps1 scripts/dev/read-local-legacy-state.js docs/disponibilidad-reversion-version.md docs/disponibilidad-reservas-antiguas.md docs/disponibilidad-cierre.md
git diff --cached --stat
git commit -m "test: verify legacy compatibility and prepare version rollback rehearsal"
~~~
