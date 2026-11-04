# Identidad local para validar SPEC-001

**Estado vigente: SPEC-001 cerrada y aprobada por el usuario el 2026-10-27.**
Los pendientes de las notas de preparacion debajo son historicos. HTTP, reinicio,
gates, replay, writers antiguos, respaldo/restauracion y reversion quedaron
confirmados antes de la aprobacion. [Evidencia y limites](disponibilidad-cierre.md).

Keycloak 26.8.1: http://localhost:8180.
Eats Hub: http://localhost:8082/catalog.
Mongo: replica set rs0, puerto 27018. No se agrega login al backend ni se cambia OpenAPI.

## Preparacion repetible

Desde PowerShell en la raiz del servicio, una sola linea:

~~~powershell
& .\scripts\dev\Setup-LocalIdentity.ps1
~~~

El script prepara el proyecto Compose eats-identity con volumen propio, importa el
realm eats-hub-local, configura el cliente publico eats-hub-cli y verifica discovery,
JWK y Device Authorization. No utiliza Direct Access Grants ni contrasenas en el backend.

El cliente tiene basic, profile y email como scopes predeterminados. basic aporta
sub, el identificador del usuario exigido por Eats Hub. Las claves JWT son RS256;
los mappers proporcionan aud=eats-hub-catalog, roles y
restaurant_ids como listas. Los grupos de Keycloak contienen los UUID sin prefijo.

| Usuario | Restaurante | RESTAURANT_MANAGER |
|---|---|---|
| encargado-a | 11111111-1111-4111-8111-111111111111 | Si |
| encargado-b | 22222222-2222-4222-8222-222222222222 | Si |
| sin-rol | 11111111-1111-4111-8111-111111111111 | No |

Se insertan los restaurantes ficticios Eats Hub Demo A/B solo si faltan, con UUID
BSON estandar. Se revisan colisiones y se usa una transaccion con $setOnInsert:
ningun restaurante existente, mesa, revision o reserva se sobrescribe.
No se toca el Mongo del puerto 27017.

Los secretos se generan en secrets/local-identity, excluido de Git y Docker build.
El script conserva credenciales, importacion y volumen. Una configuracion privada
incompatible o un volumen anterior sin credenciales detiene la preparacion; no
se borra ni reemplaza el realm. Keycloak omite la importacion si el realm ya existe;
por eso la preparacion comprueba y repara la asociacion de basic por API administrativa.

## Reparar tokens sin sub en una instalacion existente

Si Eats Hub devuelve 401 con el mensaje de log «Claims invalidas» y el token no
contiene sub, ejecutar desde la raiz del servicio, en una sola linea:

~~~powershell
& .\scripts\dev\Repair-LocalIdentity.ps1
~~~

El script usa las credenciales administrativas locales en memoria, consulta el
cliente eats-hub-cli y el scope OIDC basic, y lo asigna como predeterminado solo
si falta. Verifica la asociacion al terminar. No elimina ni recrea realms,
usuarios, roles, grupos o datos; tampoco cambia las validaciones del backend.
No imprime ni guarda el token administrativo. No habilita Direct Access Grants
en eats-hub-cli; la autenticacion administrativa usa admin-cli en master.

Para la importacion privada solo admite la diferencia exacta de agregar basic a
la plantilla anterior, conservando una copia en
secrets/local-identity/import/eats-hub-local-realm.before-basic.json.
Cualquier otra diferencia detiene la operacion sin sobrescribirla.
Actualizar la importacion por si sola no repara un realm existente.

Renovar los TRES tokens despues de reparar: los emitidos anteriormente siguen
sin sub hasta expirar. No hace falta reiniciar Eats Hub por este cambio de scope.
Obtenerlos en la misma PowerShell con los comandos de la siguiente seccion,
cerrando todas las ventanas InPrivate entre usuarios, y ejecutar inmediatamente
Test-LocalTables.ps1. Si falla la reparacion, comprobar Keycloak en 8180 y las
credenciales administrativas privadas; no borrar volumenes para reintentar.

Solo despues de verificar proveedor y datos, se guarda copia privada del .env y
se actualizan AVAILABILITY_ISSUER_URI, AVAILABILITY_JWK_SET_URI,
AVAILABILITY_AUDIENCE y AVAILABILITY_ENABLED=true.
Reiniciar manualmente SpringWebFluxApplication en IntelliJ, con SERVER_PORT=8082
y working directory en la raiz del servicio, para cargar esos valores.

## Iniciar sesion y conservar tokens en la misma terminal

~~~powershell
& .\scripts\dev\Get-LocalToken.ps1 -User encargado-a -CopyPassword
~~~

Copia al portapapeles la contrasena de encargado-a y abre Edge en privado.
Escribir ese usuario, pegar la contrasena y autorizar el dispositivo.
Cerrar la ventana privada al terminar antes de pedir un token de otra cuenta.
Si no existe Edge, abrir la URL local indicada en una ventana privada.

El token queda solo en memoria de ESTA terminal, en EATS_HUB_TOKEN_A y
EATS_HUB_MANAGER_TOKEN. No se imprime ni se escribe en disco.
El helper comprueba cuenta y claims, incluida la presencia de sub antes de guardar
el token; si falta, indica que debe repararse la identidad y no almacena ese token.
Eats Hub verifica la firma con la JWK real.
No ejecutar el helper mediante otro powershell.exe -File, pues las variables
quedarian en ese proceso hijo.

Repetir con los otros usuarios, cerrando la ventana privada anterior entre cuentas:

~~~powershell
& .\scripts\dev\Get-LocalToken.ps1 -User encargado-b -CopyPassword
~~~

~~~powershell
& .\scripts\dev\Get-LocalToken.ps1 -User sin-rol -CopyPassword
~~~

Se crean EATS_HUB_TOKEN_B y EATS_HUB_TOKEN_NO_ROLE. Los tokens expiran a los 15 minutos;
renovarlos si hace falta o al abrir otra terminal. Para no copiar la contrasena,
omitir -CopyPassword y consultar privadamente credentials.json.
El administrador local-admin tambien esta en ese archivo. No pegar secretos en el chat.

Solo si Windows bloquea scripts, permitirlos en esta terminal antes de repetir:

~~~powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
~~~

## Recorrido HTTP real

Con los tres tokens en la misma terminal y la aplicacion reiniciada:

~~~powershell
& .\scripts\dev\Test-LocalTables.ps1
~~~

Comprueba 401 sin token, 403 por rol/restaurante, GET 200, POST 201, PATCH 200,
replay POST/PATCH y Location/ETag, conflicto de clave 409, revision obsoleta 412,
body invalido 400/422, etiqueta duplicada 409 y recurso inexistente 404.
Crea una mesa etiquetada para validacion y la conserva: no hay DELETE de mesas.
Evitar otros writes del mismo restaurante durante el recorrido de If-Match.

Guarda evidencia tecnica sin JWT en secrets/local-identity/http-validation.json.
Un error detiene el script. Revisar timestamp y salida: un archivo de una ejecucion
anterior no acredita una ejecucion posterior fallida.

Despues reiniciar MANUALMENTE la aplicacion en IntelliJ y ejecutar:

~~~powershell
& .\scripts\dev\Test-LocalTables.ps1 -AfterRestart
~~~

Compara identidad, propietario, etiqueta y capacidad, y verifica ETag/revision.
Guarda restart-validation.json con operatorDeclaredRestart=true. Solo acredita un
reinicio si el usuario realmente lo realizo; dos GET seguidos no lo acreditan.
Los scripts no reinician IntelliJ ni cierran automaticamente T040.

## Ciclo manual del gate despues de las escrituras

El script Test-LocalAvailabilityGate.ps1 solo hace GET y guarda evidencia privada.
No cambia .env, no reinicia servicios y no crea mesas. Reutiliza http-validation.json;
no repetir el recorrido de alta mientras se completa este ciclo.

1. Desactivar en .env desde la raiz del servicio:

~~~powershell
. .\scripts\dev\LocalIdentity.Common.ps1; Set-LocalEnvValues (Join-Path $script:IdentityRoot '.env') @{AVAILABILITY_ENABLED='false'}
~~~

2. Detener e iniciar la aplicacion en IntelliJ, manteniendo 8082. Verificar:

~~~powershell
& .\scripts\dev\Test-LocalAvailabilityGate.ps1 -Stage Disabled
~~~

Esperado: catalogo antiguo 200 y coleccion/mesa 404. Luego reactivar:

~~~powershell
. .\scripts\dev\LocalIdentity.Common.ps1; Set-LocalEnvValues (Join-Path $script:IdentityRoot '.env') @{AVAILABILITY_ENABLED='true'}
~~~

3. Reiniciar manualmente en IntelliJ. Obtener un token vigente de encargado-a y verificar:

~~~powershell
& .\scripts\dev\Get-LocalToken.ps1 -User encargado-a -CopyPassword
~~~

~~~powershell
& .\scripts\dev\Test-LocalAvailabilityGate.ps1 -Stage Enabled
~~~

Esperado: catalogo 200, mesas sin token 401 y mesa autenticada 200 con los mismos
datos y revision y ETag coherente. Si hay overrides de AVAILABILITY_ENABLED en
IntelliJ, alinearlos con la etapa: cambiar .env no los reemplaza.
Las evidencias gate-disabled-validation.json y gate-enabled-validation.json
quedan en secrets/local-identity. Su preparacion no acredita resultados: deben
ejecutarse y revisarse. Este ciclo no comprueba writers antiguos ni recibos de
idempotencia; tampoco acredita respaldo/restauracion o reversion de version.
Si falla una etapa, conservar los datos y revisar antes de continuar.

Resultado recibido y contrastado el 2026-10-27: las tres comprobaciones de Disabled
y las tres de Enabled pasaron, vinculadas al mismo recorrido HTTP. La misma mesa
conserva datos y revision y presenta ETag coherente. Ciclo del gate de lectura
confirmado; writers antiguos y replay de recibos siguen pendientes.
Siguiente comprobacion preparada, aun sin ejecutar:
[respaldo y restauracion aislada](disponibilidad-respaldo-local.md).

## Evidencia y limites

Diagnostico posterior comunicado por el usuario: tokens emitidos y peticion sin
token con 401; el recorrido se detuvo con 401 para encargado ajeno, y el log del
backend indico «Claims invalidas». Se confirmo la ausencia de sub. Se corrigieron
la plantilla, la preparacion y el helper y se agrego la reparacion repetible.
La comprobacion de sintaxis y JSON por si sola no acredita el recorrido HTTP.
Actualizacion 2026-10-27 (America/Lima): el usuario renovo los tokens y confirmo
las 15 comprobaciones HTTP aprobadas y el GET 200 tras reiniciar manualmente
IntelliJ. Se contrastaron http-validation.json (05:02:33Z) y
restart-validation.json (05:05:39Z): misma mesa, propietario, etiqueta, capacidad 6
y revision 2. El script verifica replay, Location/ETag y ETag tras reinicio.
El segundo archivo declara operatorDeclaredRestart=true; el primero conserva
restartVerified=false como registro del recorrido previo al reinicio.
T040 sigue abierto por gates/compatibilidad, respaldo/restauracion, reversion
y aprobacion formal; no por falta de tokens o persistencia.

Comprobado por el agente: sintaxis PowerShell, Compose valido, discovery con issuer
esperado, JWK RSA de firma, Device Authorization disponible y fixtures A/B en Mongo.
La preparacion se repitio sin reemplazar realm, secretos o restaurantes.
El backend todavia devolvia 404 antes de reiniciarse: aun cargaba el gate anterior.

No se obtuvieron tokens de los usuarios ni se ejecutaron escrituras HTTP autenticadas,
suites Gradle o commits en esta preparacion. No hay cambios Java, OpenAPI o SPEC-002/003.
Evidencia previa del usuario: 137 seleccionadas, 52 de integracion, suite completa
138/138 sin fallos y contrato valido con siete warnings conocidos.
Las notas de preparacion anteriores son historicas. Estado vigente de T040:
HTTP autenticado y reinicio confirmados; gates/reversion, respaldo/restauracion
y aprobacion formal pendientes. Detalle en [guia de cierre](disponibilidad-cierre.md).

Para volver a gate=false, cambiar AVAILABILITY_ENABLED y reiniciar la aplicacion.
Conservar volumenes. El .env anterior esta en
secrets/local-identity/application.env.before-identity: revisar claves concretas
antes de revertir para no perder cambios locales posteriores.

## Revision y Git, por el usuario

Parser: revisa sintaxis sin ejecutar scripts ni suites.

~~~powershell
Get-ChildItem .\scripts\dev\*.ps1 | ForEach-Object { $t=$null; $e=$null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$t,[ref]$e) | Out-Null; if($e.Count){throw ($_.Name+': '+$e[0].Message)}; Write-Host ($_.Name+': sintaxis correcta') }
~~~

Solo despues de validar, desde Git Bash:

~~~bash
git add src/main/resources/docker-compose.identity.yml src/main/resources/identity/ scripts/dev/ docs/identidad-local.md docs/disponibilidad-cierre.md
git diff --cached --stat
git commit -m "chore: prepare local Keycloak identity and table verification"
~~~

Los documentos SDD de specs quedan fuera de Git del servicio.

Fuentes oficiales:
[Docker](https://www.keycloak.org/getting-started/getting-started-docker),
[importacion](https://www.keycloak.org/server/importExport),
[OIDC y Device Authorization](https://www.keycloak.org/securing-apps/oidc-layers).
