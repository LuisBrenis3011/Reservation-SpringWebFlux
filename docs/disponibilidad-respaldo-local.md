# Respaldo y restauracion aislada de la base local

**Estado vigente: ensayo aprobado y SPEC-001 cerrada por el usuario el 2026-10-27.**
Los pendientes operativos mencionados en las notas de preparacion son historicos;
se resolvieron antes de la aprobacion. [Evidencia y limites](disponibilidad-cierre.md).

## Evidencia recibida — 2026-10-27

El usuario ejecuto el ensayo 20261027T053631Z-522c7f246054460082639b1defc41b0b,
terminado a 05:36:42Z con restoreVerified=true y sourceUnchanged=true. Se contrastaron
validation.json, manifiestos y hash del archive: 7 documentos, 4 colecciones,
documentos/indices coincidentes y origen sin cambios. Contenedor/volumen y backup
conservados. El resultado acredita esta base local y este ensayo, sin extenderlo
a migracion del Mongo antiguo o reversion de version. Instrucciones de repeticion debajo.

Preparacion de T040. Preparar este procedimiento NO acredita haberlo ejecutado.
El usuario ejecuta los comandos y aporta el resultado; no hay suites ni commits automaticos.

## Alcance

Respalda exclusivamente la base de aplicacion definida en .env en el contenedor
eats-availability-mongodb-replica-1, rs0 PRIMARY, imagen mongo:8.0.8, puerto local
27018. No copia el Mongo antiguo de 27017 ni credenciales/usuarios de admin.
No equivale a migracion, replica set de produccion ni reversion de version.

Usa mongodump con --db, --archive y --gzip. Este respaldo requiere TODOS los
writers detenidos: sin --oplog no se garantiza una instantanea durante escrituras.
No basta availability.enabled=false, pues las reservas antiguas siguen escribiendo.
El script exige -WritersStopped como declaracion y comprueba que 8082 no escuche;
esa comprobacion no descubre otros clientes, jobs, otras instancias o puertos.
Detenerlos tambien; no ejecutar suites ni escrituras de Compass durante el ensayo.

Se compara el manifiesto del origen antes/despues del dump, del destino restaurado
y del origen al finalizar. Incluye inventario, conteos, SHA-256 de documentos en
EJSON canonico ordenados por _id, indices y opciones de coleccion. La comparacion
de documentos incorpora tipos BSON (incluidos UUID y fechas), revisiones y recibos
cuando esas colecciones existen. No se imprimen documentos ni secretos.
Se rechazan vistas, series temporales y colecciones de sistema: no se simula soporte.

La copia binaria usa docker cp, evitando redireccion de archivos binarios con
Windows PowerShell. Los datos quedan en backups/availability/<id-unico>/, excluido
de Git y del build Docker; son datos reales locales y deben conservarse privados.

## Ejecutar desde PowerShell en la raiz del servicio

1. Detener SpringWebFluxApplication en IntelliJ y todos los demas writers.
   Mantener Docker y el Mongo de 27018 activos. No cambiar .env ni borrar volumenes.
2. Ejecutar esta unica linea, solo despues de confirmar esa parada:

~~~powershell
& .\scripts\dev\Test-LocalMongoRestore.ps1 -WritersStopped
~~~

3. Esperar el mensaje OK. Compartir solo el resumen, nunca dumps ni credenciales.
   Al terminar, iniciar Eats Hub nuevamente desde IntelliJ en 8082.

Cada ejecucion crea un contenedor y volumen nuevos con nombre eats-restore-check-<id>.
El destino usa exactamente el Image ID instalado del origen, network=none, sin
puertos publicados, y solo se accede con docker exec. Se verifica que la base de
destino este vacia antes de restaurar. No se usa --drop ni se permite elegir un
origen o destino alternativo por argumento. Nada restaura sobre 27018 o 27017.

La restauracion usa --stopOnError; cualquier error detiene el recorrido y conserva
backup y destino. No hay borrado ni limpieza automatica. El archivo restore-target.json
identifica el contenedor/volumen propios del ensayo para inspeccion posterior.
El contenedor aislado queda activo y conservado; puede detenerse manualmente por
su nombre exacto despues de revisar el resultado. No eliminar volumenes del proyecto.
El archive temporal tambien se conserva en /tmp del contenedor origen.

## Evidencia y fallos

Solo si todas las comparaciones pasan se genera validation.json con
restoreVerified=true, sourceUnchanged=true, declaracion de writers detenidos,
identidad del destino y SHA-256 del archive. Los manifiestos quedan al lado.
Un archivo de una ejecucion anterior no acredita una posterior fallida.
Una diferencia de hashes, indices, colecciones o conteos mantiene la comprobacion
pendiente: conservar todo y revisar el error, sin borrar origen ni relajar comparaciones.
Si el proceso falla, no asumir reversion o restauracion exitosa.

La parada declarada y las comparaciones no sustituyen coordinacion real de todos
los writers, y este ensayo no prueba HTTP sobre la copia ni recuperacion de claves
de Keycloak. Conservar pendientes compatibilidad de writers antiguos, replay de
recibos tras el ciclo de gate, reversion de version y aprobacion final de T040.

## Revision y Git

No hace falta repetir suites Gradle por este procedimiento. Se revisan sintaxis
PowerShell y JavaScript y despues el usuario ejecuta el ensayo aislado.
Solo si pasa, desde Git Bash:

~~~bash
git add scripts/dev/Test-LocalMongoRestore.ps1 scripts/dev/mongo-backup-manifest.js scripts/dev/Test-LocalAvailabilityGate.ps1 docs/disponibilidad-respaldo-local.md docs/disponibilidad-cierre.md docs/identidad-local.md
git diff --cached --stat
git commit -m "chore: add isolated Mongo backup verification and record gate checks"
~~~

Los archivos SDD siguen fuera del repo. No agregar backups/, secrets/ ni .env.

Fuentes oficiales:
[mongodump y consistencia](https://www.mongodb.com/docs/database-tools/mongodump/),
[mongorestore y archive comprimido](https://www.mongodb.com/docs/database-tools/mongorestore/).
