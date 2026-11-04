# Compatibilidad de escrituras antiguas con el gate

## Evidencia vigente — ambas etapas aprobadas

Usuario y archivos privados contrastados: Disabled finalizo
2026-10-27T22:54:42Z, revision B 0 a 3; Enabled finalizo
2026-10-27T22:58:02Z, revision B 3 a 6. Seis comprobaciones HTTP aprobadas por
etapa, cada create/update/delete incremento una revision, ambas fixtures fueron
eliminadas y A quedo intacto. El agente no ejecuto esas peticiones.
Las notas de preparacion debajo son historicas. Reversion y aprobacion formal
recibidas posteriormente; SPEC-001 cerrada el 2026-10-27. No ejecutar de nuevo
este CRUD para acreditar el resultado previo. [Cierre](disponibilidad-cierre.md).

Procedimiento preparado para T040; el agente no ejecuta estas peticiones.
Usa el restaurante ficticio B, separado de la mesa y recibos validados de A.
No cambia Java, contratos ni la seguridad de las rutas existentes.

El script crea una reserva ficticia, la consulta, actualiza y elimina SOLO esa
reserva. Exige -AllowFixtureWrites; B debe comenzar sin reservas o se detiene.
Antes del DELETE verifica ID, restaurante, cliente ficticio y marcador de la
ejecucion en Mongo. Nunca elimina reservas previas ni hace limpieza en finally.
Cada write debe incrementar la revision de B una vez; total +3. Comprueba que
los datos de A no cambien, incluidos mesa y recibos. Evitar otros writers.

## Etapa 1: desactivado

Desde PowerShell en la raiz del servicio:

~~~powershell
. .\scripts\dev\LocalIdentity.Common.ps1; Set-LocalEnvValues (Join-Path $script:IdentityRoot '.env') @{AVAILABILITY_ENABLED='false'}
~~~

Detener e iniciar la aplicacion en IntelliJ, manteniendo 8082. Cuando arranque:

~~~powershell
& .\scripts\dev\Test-LocalLegacyReservations.ps1 -Stage Disabled -AllowFixtureWrites
~~~

Esperado: mesas 404, catalogo 200, POST reserva 201, GET 200, PUT 200 y DELETE 204.
Al final se verifica ausencia de la fixture en Mongo y revision inicial +3.

## Etapa 2: activado

Solo tras revisar la etapa anterior:

~~~powershell
. .\scripts\dev\LocalIdentity.Common.ps1; Set-LocalEnvValues (Join-Path $script:IdentityRoot '.env') @{AVAILABILITY_ENABLED='true'}
~~~

Reiniciar en IntelliJ y ejecutar:

~~~powershell
& .\scripts\dev\Test-LocalLegacyReservations.ps1 -Stage Enabled -AllowFixtureWrites
~~~

Esperado: mesas sin token 401, catalogo 200 y el mismo CRUD con revision +3.
No necesita tokens: reproduce la seguridad actual de las rutas antiguas.

## Evidencia y limites

Resultados privados: secrets/local-identity/legacy-disabled-validation.json y
legacy-enabled-validation.json. Cada ejecucion guarda checkpoints
legacy-fixture-<run>.json con identificadores ficticios antes/despues de escrituras.
Si falla, conservar checkpoint y datos, sin repetir POST automaticamente ni borrar
reservas para forzar verde. Si B ya tiene una reserva, revisar su procedencia antes
de continuar. Un alta incierta requiere buscar su marcador antes de repetir.

PlannerMSClient es el simulador existente, no un servicio externo real. El ensayo
es secuencial, no una prueba de concurrencia ni reversion de version. La ruta antigua
implementada es /catalog/reservation/{id}, aunque el alta anuncia /reservations/{id};
se conserva ese comportamiento sin alterar el contrato en este bloque.

Solo tras validar ambas etapas, desde Git Bash:

~~~bash
git add scripts/dev/Test-LocalLegacyReservations.ps1 scripts/dev/read-local-legacy-state.js docs/disponibilidad-reservas-antiguas.md docs/disponibilidad-replay-recibos.md docs/disponibilidad-cierre.md
git diff --cached --stat
git commit -m "test: verify legacy reservation writes across availability gates"
~~~

No agregar secrets/, backups/ ni .env. Los documentos SDD siguen fuera del servicio.
