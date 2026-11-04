# Replay del recibo original despues del ciclo de gate

## Evidencia vigente — recorrido aprobado

El usuario ejecuto el recorrido el 2026-10-27. Se contrasto
secrets/local-identity/receipt-replay-validation.json (2026-10-27T17:05:55Z):
HTTP 201, cuerpo/Location/ETag originales conservados, mesa actual y revision sin
cambios y manifiesto Mongo sin diferencias. Vinculado a la misma mesa y gate.
El agente no ejecuto el POST. Esta confirmacion sustituye el pendiente de ejecucion
de las notas historicas debajo. Writers antiguos, reversion y aprobacion recibidos
posteriormente: SPEC-001 cerrada el 2026-10-27. [Cierre](disponibilidad-cierre.md).

Comprobacion preparada para T040; no implica que el POST haya sido ejecutado.
Reutiliza exclusivamente la mesa de http-validation.json y requiere la evidencia
gate-enabled-validation.json del mismo recorrido. Mantener Eats Hub en 8082 y
Mongo local en 27018, con disponibilidad habilitada. Evitar otras escrituras
durante este recorrido: se exige que el manifiesto completo no cambie.

## Ejecutar en la misma PowerShell

Si hace falta, obtener un token vigente:

~~~powershell
& .\scripts\dev\Get-LocalToken.ps1 -User encargado-a -CopyPassword
~~~

Luego ejecutar:

~~~powershell
& .\scripts\dev\Test-LocalReceiptReplay.ps1
~~~

El script lee en memoria el recibo POST 201 que corresponde a la mesa de prueba
en el restaurante A, verificando tambien el marcador del restaurante ficticio.
Reconstruye el payload de alta con etiqueta y capacidad originales y verifica
su SHA-256 contra el fingerprint almacenado antes de enviar la peticion.
Si no puede reconstruir exactamente el comando, se detiene antes de enviar POST.
No imprime ni guarda la clave de idempotencia o el JWT.

Reenvia la clave y el comando originales. Se espera 201, cuerpo original,
Location y ETag de revision 1. Esa respuesta historica es correcta: la mesa
actual debe seguir con capacidad 6 y revision 2 segun la evidencia existente.
Compara el GET actual antes/despues y el manifiesto completo de Mongo, incluidos
documentos, indices y recibos. Una diferencia mantiene pendiente la comprobacion;
no se relajan aserciones ni se crean nuevos comandos para forzar un resultado.

Al pasar, guarda secrets/local-identity/receipt-replay-validation.json sin JWT ni
clave de idempotencia. No acredita por si solo writers antiguos, recuperacion de
version de aplicacion, migracion ni autorizacion para cerrar T040.

## Estado de preparacion

El agente comprobo por lectura que existe un unico recibo de alta para la mesa
de evidencia, revision 1, y que el fingerprint del payload reconstruido coincide.
No ejecuto el POST ni el recorrido HTTP; la validacion final corresponde al usuario.
Los valores numericos de la respuesta estan almacenados como BSON Long: el lector
los convierte a numero antes de reconstruir el JSON, conservando el valor original.

Solo despues de validar, junto con la documentacion del respaldo, desde Git Bash:

~~~bash
git add scripts/dev/Test-LocalReceiptReplay.ps1 scripts/dev/read-local-replay-receipt.js docs/disponibilidad-replay-recibos.md docs/disponibilidad-respaldo-local.md docs/disponibilidad-cierre.md docs/identidad-local.md
git diff --cached --stat
git commit -m "test: verify stored receipt replay after availability gate cycle"
~~~

No agregar backups/, secrets/ ni .env; specs sigue fuera del repositorio del servicio.
