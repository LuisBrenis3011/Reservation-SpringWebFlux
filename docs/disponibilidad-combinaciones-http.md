# SPEC-002 — Recorrido HTTP local de combinaciones

## Estado y preparación

Script preparado: `scripts/dev/Test-LocalCombinations.ps1`. Revisión de sintaxis
sin errores; el agente no lo ejecutó, no envió peticiones HTTP, no inició servicios
ni corrió suites. Su preparación no acredita resultados del recorrido ni cierra T060.

El usuario ya validó OpenAPI con Redocly: sin errores y con 8 warnings,
uno de localhost y siete schemas sin uso. Se conservan contrato y reglas.
[Evidencia y pendientes](disponibilidad-combinaciones-validacion.md).

Usar la preparación local existente: Eats Hub en IntelliJ, puerto 8082,
AVAILABILITY_ENABLED=true, Mongo replica set y Keycloak ya preparados. Este
script no cambia .env, servicios, usuarios, credenciales ni datos de reservas.
No se ejecuta automáticamente y no debe combinarse con otros recorridos o escrituras.

Reutiliza `LocalIdentity.Common.ps1`, las identidades encargado-a, encargado-b
y sin-rol y los restaurantes A/B existentes. Los tokens permanecen en variables
de proceso de la misma PowerShell; no se muestran ni se guardan en el checkpoint.

## Qué crea y qué conserva

Al autorizar su ejecución con `-AllowFixtureWrites`, crea exclusivamente en A:

- Tres mesas nuevas con etiquetas `SPEC002 <runId> 1/2/3` y capacidades 4, 2 y 3.
- Combinación AB de capacidad 6 y combinación BC de capacidad 5.
- Cambia AB a AC, capacidad 7, conservando id/restaurante; después envía un PUT
  equivalente en orden inverso con clave nueva para excluir su propia identidad.

Son siete comandos nuevos aceptados en total: tres altas de mesas, dos altas de
combinaciones y dos PUT. Sus revisiones deben aumentar exactamente siete veces.
Los replay y rechazos deben conservar la revisión alcanzada. Se compara la
configuración previa de mesas/combinaciones de A y la colección/revisión de B.
No se borran fixtures al terminar: deben persistir para la comprobación de reinicio
y los futuros gates. No hay endpoint de borrado de combinaciones en este alcance.

## Checkpoint y recuperación

Archivo propio, excluido de Git:
`secrets/local-identity/combinations-http-checkpoint.json`.
No modifica los checkpoints de SPEC-001. Guarda identidad del ensayo, solicitudes,
claves de idempotencia, If-Match, respuestas, timestamps y snapshots técnicos.
No contiene contraseñas ni JWT. Usa bloqueo exclusivo y reemplazo atómico del archivo.

Compatibilidad de guardado corregida para Windows PowerShell 5.1: File.Replace
recibe NullString.Value como ruta de respaldo nula, evitando la conversión de
$null a cadena vacía. El agente comprobó creación y reemplazo con las funciones
reales sobre archivos desechables aislados en build (PowerShell 5.1.26100.9711).
No ejecutó HTTP ni suites y conservó intactos el checkpoint real y sus temporales.

Antes de enviar una solicitud guarda su intención. Una etapa incompleta se
reintenta con la misma URI, clave, cuerpo y revisión; las ya comprobadas se leen
del journal y se identifican en consola como «Checkpoint». Las consultas finales
se realizan de nuevo para no acreditar solo respuestas guardadas.

Si se interrumpe el proceso, renovar los tokens necesarios y repetir exactamente
el comando con `-AllowFixtureWrites`. No borrar/editar el checkpoint ni cambiar
claves para superar un error. Si hubo otra escritura, revisión inesperada o una
regla de negocio impide continuar, conservar el archivo y revisar la causa.
Un recorrido terminado no crea más datos si se invoca de nuevo; indica usar
`-AfterRestart`. No sobrescribe checkpoints de otra versión o especificación.

## Pasos manuales — PowerShell

Ejecutar cada comando en una sola línea y usar la misma terminal para tokens y script:

```powershell
Set-Location <WORKSPACE>\SpringWebFlux
```

Obtener los tres tokens para evitar reutilizar los anteriores expirados.
Ejecutar uno a uno. En el navegador iniciar sesión con el usuario indicado;
la contraseña queda copiada por `-CopyPassword`. Esperar «Token guardado»
en PowerShell y cerrar todas las ventanas InPrivate abiertas por ese login
antes de obtener el siguiente usuario, para no reutilizar la sesión anterior.

```powershell
& .\scripts\dev\Get-LocalToken.ps1 -User encargado-a -CopyPassword
& .\scripts\dev\Get-LocalToken.ps1 -User encargado-b -CopyPassword
& .\scripts\dev\Get-LocalToken.ps1 -User sin-rol -CopyPassword
```

Con la app ya levantada en IntelliJ y sin otros escritores, ejecutar:

```powershell
& .\scripts\dev\Test-LocalCombinations.ps1 -AllowFixtureWrites
```

El script comprueba 401 sin token y 403 por restaurante ajeno o rol ausente en
GET/POST/PUT; GET propio 200; altas 201 con Location/ETag; PUT 200 conservando
identidad; duplicados POST/PUT 409; If-Match ausente 400 y obsoleto 412;
misma clave con otra carga 409. Verifica replay de POST y PUT antes/después
de otros writes, cuerpo/estado/Location/ETag originales y recurso actual intacto.
Termina con comparación de datos previos y revisión exacta, y guarda su resultado.

Si termina correctamente, detener y volver a iniciar solo Eats Hub desde IntelliJ,
conservando 8082 y el gate habilitado. No detener Mongo ni Keycloak, ni ejecutar
otro recorrido de mesas entre ambas etapas. Volver a la misma PowerShell y ejecutar:

```powershell
& .\scripts\dev\Test-LocalCombinations.ps1 -AfterRestart
```

Esta etapa hace solo GET: compara combinación, colecciones, mesas, capacidad,
revisión y ETag con el checkpoint. Si expiró el token de A, renovarlo con su
comando de arriba y repetir `-AfterRestart`; no hace falta renovar B/sin-rol
para esta etapa. El script no puede demostrar por sí mismo un reinicio:
registra que el usuario declara haberlo realizado y qué datos coinciden.

## Evidencia y límites

El usuario aportó las salidas correctas de ambas etapas. La inspección posterior
del checkpoint confirma 29 etapas HTTP, httpCompleted=true y reinicio declarado
con datos/revisión/ETag conservados (revisión 9, dos combinaciones y cuatro mesas).
No adjuntar tokens ni credentials.json. No se repite el recorrido de altas.
Gates de combinaciones, respaldo/restauración, reversión compatible y aprobación
expresa siguen pendientes: el recorrido HTTP no los acredita por herencia.
La protección temporal, legado y fallos tienen evidencia automatizada separada;
este recorrido no inserta reservas para reproducirlos sobre la base local.

## Gate desactivado y reactivado — pasos manuales

Se preparó `scripts/dev/Test-LocalCombinationGate.ps1`, con sintaxis comprobada en
Windows PowerShell 5.1 sin invocarlo. Su ejecución sigue a cargo del usuario.
Solo hace GET y registra evidencia local; no cambia .env, no reinicia
servicios y no crea ni actualiza fixtures. No ejecutar otra validación de mesas o
combinaciones ni efectuar otras escrituras entre etapas.

Desde SpringWebFlux, abrir la configuración local:

```powershell
notepad .env
```

Cambiar únicamente `AVAILABILITY_ENABLED=true` por `AVAILABILITY_ENABLED=false`,
guardar, detener Eats Hub con el botón rojo de IntelliJ y volver a iniciarlo en
8082. Mantener Mongo y Keycloak encendidos. Si IntelliJ tiene esa misma variable
en su configuración de ejecución, debe coincidir; las respuestas HTTP determinan
qué configuración se cargó realmente. No compartir el contenido de .env.

Comprobar la etapa desactivada (no necesita token):

```powershell
& .\scripts\dev\Test-LocalCombinationGate.ps1 -Stage Disabled
```

Debe obtener catálogo antiguo 200, colección de combinaciones 404 y combinación
del checkpoint 404. Si recibe 401 en las rutas nuevas, revisar la variable y el
reinicio; no continuar a Enabled hasta que Disabled pase.

Volver a poner `AVAILABILITY_ENABLED=true` en .env, guardar y reiniciar solo
Eats Hub desde IntelliJ en 8082. Obtener de nuevo el token de encargado-a en la
misma PowerShell para evitar expiración; no hacen falta B/sin-rol para este paso:

```powershell
& .\scripts\dev\Get-LocalToken.ps1 -User encargado-a -CopyPassword
```

Después del mensaje «Token guardado», ejecutar:

```powershell
& .\scripts\dev\Test-LocalCombinationGate.ps1 -Stage Enabled
```

Debe obtener catálogo antiguo 200, colección/recurso sin token 401, con token
propio colección/recurso 200 y mesas 200. Compara todos los integrantes,
identidades, propietarios, capacidades, etiquetas de mesas, revisión 9 y ETag
con el checkpoint HTTP. No basta con que un endpoint devuelva 200.

La evidencia queda en `secrets/local-identity/combinations-gate-checkpoint.json`,
separada de la de SPEC-001. Conserva un historial de etapas exitosas, sin JWT ni
contraseñas. Enabled requiere una etapa Disabled previa del mismo checkpoint;
si este cambia, se rechaza la mezcla de evidencias. Se conserva el reemplazo
atómico compatible con Windows PowerShell 5.1 y el checkpoint HTTP queda intacto.
Solo se registra éxito tras completar las comparaciones. Este script no acredita
recibos o índices en Mongo, respaldo/restauración ni reversión de versión.
Comunicar ambas salidas; T060 permanece abierta hasta completar lo pendiente.

**Resultado posterior:** el usuario aportó Disabled y Enabled exitosos. Se
contrastaron ambos checkpoints: mismo ensayo/hash, 3/6 comprobaciones correctas,
reactivación enlazada y configuración/revisión/ETag conservados. No hace falta
repetir este ciclo para preparar el [respaldo/restauración aislada de SPEC-002](disponibilidad-combinaciones-respaldo.md).

## Git Bash — separado del recorrido

Después de revisar la preparación y sus resultados, desde SpringWebFlux:

```bash
git add scripts/dev/Test-LocalCombinations.ps1 scripts/dev/Test-LocalCombinationGate.ps1 README.md docs/disponibilidad-combinaciones-http.md docs/disponibilidad-combinaciones-validacion.md
git diff --cached --check
git diff --cached --stat
git commit -m "test: prepare combination gate checks and record HTTP evidence"
```

El checkpoint queda bajo secrets/ y los documentos SDD fuera del Git del servicio.
