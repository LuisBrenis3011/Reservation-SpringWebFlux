# SPEC-002 — Preparación de respaldo y restauración aislada

## Estado

Continuación de T060, 2026-10-28. Se contrastaron los checkpoints existentes del
usuario: HTTP y reinicio correctos; Disabled (3 comprobaciones) y Enabled
(6 comprobaciones) enlazados al mismo ensayo/hash, con datos conservados y revisión 9.
La etapa Enabled referencia la Disabled correcta y es la última etapa registrada.
No se transfiere la evidencia de restauración antigua de SPEC-001 a combinaciones.

Se amplió el procedimiento existente `scripts/dev/Test-LocalMongoRestore.ps1`
con el parámetro opcional `-IncludeCombinations`. El modo sin ese parámetro
conserva su comportamiento previo. Se añadió el lector de solo consulta
`scripts/dev/read-combination-backup-requirements.js`; no se duplica el procedimiento.
El agente revisó sintaxis en Windows PowerShell 5.1 y con `node --check`, sin
ejecutar scripts operativos, Docker, suites, respaldos ni restauraciones.
La restauración de SPEC-002 continúa pendiente de ejecución y evidencia del usuario.

**Resultado posterior del usuario:** ejecución 20261028T053931Z-7892c3033d144c5a97c7f41f07fd62dd
exitosa. El agente contrastó manifiestos origen antes/después y restaurado,
spec-002-validation.json y hashes: 19 documentos, índice único, revisión 9 y siete
recibos del ensayo conservados. La preparación inicial se conserva como historial;
la [reversión de versión](disponibilidad-combinaciones-reversion.md) todavía no se ejecuta.

Se corrigió el transporte de expectativas para Windows PowerShell 5.1: JSON UTF-8
codificado en Base64, transmitido por EATS_COMBINATION_EXPECTATIONS_BASE64 y
decodificado de forma estricta antes de JSON.parse. Se rechazan datos ausentes,
Base64/UTF-8/JSON inválidos sin imprimir su contenido. Base64 no es cifrado.
Se comprobó PowerShell 5.1 → Node con datos sintéticos, comillas y caracteres
españoles, usando el decodificador real y siete entradas ausentes/inválidas.
No se ejecutaron Docker, Mongo ni suites. El intento previo falló antes del dump
y dejó una carpeta vacía que se conserva; checkpoints y respaldos previos no cambian.

## Qué comprobará el modo de combinaciones

- Exige checkpoints HTTP/reinicio/gate completos y compatibles. No los modifica.
  Compara sus hashes al finalizar. No usa tokens HTTP ni imprime claves de recibos.
- Requiere la parada declarada de todos los escritores y comprueba que 8082 no
  esté escuchando. Esto no detecta otros clientes: el usuario debe detenerlos también.
- Mantiene los límites existentes: Mongo local 27018, origen identificado
  `eats-availability-mongodb-replica-1`, imagen instalada mongo:8.0.8, rs0 PRIMARY,
  sin URI personalizada ni operaciones sobre admin/local/config como base de datos.
- Antes del dump comprueba que existan restaurantes, mesas, combinaciones,
  revisiones y recibos. Verifica todas las mesas/combinaciones de A del checkpoint,
  capacidades derivadas, integrantes canónicos, revisión y el índice único completo
  `restaurant_combination_members_unique` sobre `(restaurantId, memberKey)`.
- Comprueba los siete recibos aceptados del ensayo por clave y propietario:
  estado, Location, revisión resultante y datos de respuesta histórica, incluidos
  los integrantes originales que difieren del recurso actual tras PUT.
- Reutiliza mongodump/mongorestore de toda la base de aplicación y su manifiesto:
  nombres/opciones de colecciones, conteos, hash de documentos BSON y hash de índices.
  Esto incluye datos de otros restaurantes y reservas presentes, no solo fixtures.
- Restaura únicamente en un contenedor y volumen nuevos de nombre único, con la
  misma imagen instalada del origen, `--network none` y sin puertos publicados.
  Exige destino vacío; no usa --drop ni restaura sobre el origen.
- Contrasta manifiesto completo y prueba específica en origen antes/después,
  destino restaurado y origen final. El dump se guarda en /tmp del contenedor y
  se copia como archivo binario; no atraviesa el pipeline binario de PowerShell.

El esquema y la integridad física se comprueban sobre la copia restaurada.
El destino aislado es standalone para este ensayo: no acredita alta disponibilidad,
promoción a producción, usuarios/auth del servidor ni operación transaccional de la app
contra la copia. Tampoco ejecuta replay HTTP sobre ella; verifica recibos almacenados.

## Pasos manuales — PowerShell

1. Mantener `AVAILABILITY_ENABLED=true` después del gate reactivado. No volver a
   ejecutar altas ni etapas de gate mientras se prepara este respaldo.
2. Detener **Eats Hub con el botón rojo de IntelliJ** y todos los otros clientes
   que puedan escribir en esta base: otras instancias, jobs, scripts, Compass o
   mongosh con escrituras. Mantener Mongo origen, Docker Desktop y Keycloak activos.
3. Desde la raíz del servicio ejecutar un solo comando, confirmando la parada:

```powershell
& .\scripts\dev\Test-LocalMongoRestore.ps1 -WritersStopped -IncludeCombinations
```

El script comprobará origen, creará el respaldo y el destino nuevo y realizará
la comparación. No iniciar escritores hasta que termine, tampoco para corregir
un error. Si falta la imagen/configuración esperada, un checkpoint no coincide
o hay datos distintos, conservar todo y revisar la causa; no borrar datos ni
forzar la revisión del checkpoint para obtener un resultado verde.

4. Si termina correctamente, comunicar toda la salida final, en particular
   la carpeta de evidencia y el mensaje de verificación específica de SPEC-002.
5. Volver a iniciar **solo Eats Hub desde IntelliJ en 8082**, conservando el gate
   habilitado. Este ensayo no requiere un nuevo login. No cambiar la aplicación
   para conectarla al destino aislado.

## Evidencia y conservación

Cada ejecución usa una carpeta nueva `backups/availability/<timestamp-uuid>/`,
excluida de Git. Conserva archive, manifiestos origen antes/después, restaurado,
identificación del destino y `validation.json` del procedimiento común.
`spec-002-validation.json` añade prueba específica de combinaciones, índice,
revisión y siete recibos, enlazada por hashes a los checkpoints HTTP y gate.
El archivo completo del dump se identifica por SHA-256.

Contenedor y volumen de restauración permanecen disponibles; el script no los
elimina. No compartir archivos de respaldo: contienen datos de la base. Los
temporales del dump se conservan; no se ejecuta limpieza ni restauración destructiva.
Un fallo conserva los artefactos ya creados, sin declarar el ensayo aprobado.

Hasta recibir resultados, respaldo/restauración sigue pendiente en T060. Incluso
con el ensayo aprobado, reversión compatible de versión y cierre formal siguen
pendientes; no se declara un cierre automático.

## Git Bash — después de validar y revisar

```bash
git add scripts/dev/Test-LocalMongoRestore.ps1 scripts/dev/read-combination-backup-requirements.js README.md docs/disponibilidad-combinaciones-respaldo.md docs/disponibilidad-combinaciones-http.md docs/disponibilidad-combinaciones-validacion.md
git diff --cached --check
git diff --cached --stat
git commit -m "test: extend isolated restore verification to table combinations"
```

Las sugerencias no ejecutan Git ni incluyen backups/secrets o los documentos SDD
externos al repositorio del servicio.
