# SPEC-003 — Recorrido HTTP manual de zona y turnos

T087 parcial, 26/27 tareas; lote 87/88. Script preparado, todavía no ejecutado.
No acredita HTTP real, reinicio, gates, respaldo/restauración, reversión ni cierre.
Los resultados deberán ser ejecutados y comunicados por el usuario.

## Preparación y límites del ensayo

El script `scripts/dev/Test-LocalShifts.ps1` reutiliza LocalIdentity.Common.ps1 y
el patrón de journal de Test-LocalCombinations.ps1, con checkpoint independiente
`secrets/local-identity/shifts-http-checkpoint.json` y bloqueo exclusivo propio.
No ejecuta los otros recorridos, cambia .env, arranca servicios ni escribe JWT.
También conserva los checkpoints y datos de SPEC-001/002.

El usuario debe tener la versión actual iniciada en IntelliJ en 8082, gate habilitado
y el entorno existente de Mongo replica set e identidad disponible. No se verificó
su disponibilidad durante la preparación. Evitar otras escrituras en A/B hasta
terminar el recorrido y el reinicio, también desde otros scripts o servicios.

El ensayo lee la configuración previa y se detiene sin escrituras de negocio si
A tiene turnos previos o una zona distinta de America/Lima. No ofrece un parámetro
para saltarse esa protección. No borrar datos ni el checkpoint para forzarlo.
Los GET pueden preparar metadatos técnicos mediante ensureInitialized, como en las
demás consultas; no se consideran una migración de los datos de negocio.

Se requieren dos permisos explícitos: `-AllowFixtureWrites -AllowZoneChanges`.
El script crea dos turnos de A y prueba Lima → UTC → Nueva York → Lima. Con zona
previa Lima, la restaura explícitamente al final; su revisión y recibos aumentan.
Si no había zona, la crea y termina en Lima: no existe DELETE de zona y no se
promete volver a null. Los dos turnos quedan conservados, no hay borrado automático.
Esta modificación es parte anunciada del ensayo, no una limpieza oculta.

Las fechas se fijan en el checkpoint antes de cualquier solicitud: enero del año
UTC actual más dos, incluyendo medianoche y adyacencia. Los casos estacionales usan
el segundo domingo de marzo y primero de noviembre de ese mismo año en Nueva York.
Si cambian las reglas de zona del runtime y un resultado difiere, el ensayo falla;
no ajusta fechas u offsets silenciosamente. No usa el reloj local del restaurante
para reinterpretar instantes: las comprobaciones de Lima/UTC son explícitas.

## Ejecución manual — PowerShell

1. Confirmar manualmente la aplicación actual en IntelliJ, puerto 8082 y gate
   habilitado. Conservar Mongo, Redis y Keycloak existentes; no recrearlos.
2. Desde una única PowerShell, obtener los tres tokens. Cada comando va en una línea:

```powershell
Set-Location <WORKSPACE>\SpringWebFlux
& .\scripts\dev\Get-LocalToken.ps1 -User encargado-a -CopyPassword
& .\scripts\dev\Get-LocalToken.ps1 -User encargado-b -CopyPassword
& .\scripts\dev\Get-LocalToken.ps1 -User sin-rol -CopyPassword
```

Iniciar sesión en la ventana privada con el usuario indicado y pegar su contraseña
copiada. Aceptar el acceso y esperar confirmación en PowerShell; cerrar la ventana
privada antes del siguiente usuario. No compartir los JWT ni las contraseñas.

3. Conociendo los cambios descritos arriba, ejecutar:

```powershell
& .\scripts\dev\Test-LocalShifts.ps1 -AllowFixtureWrites -AllowZoneChanges
```

El script verifica:

| Área | Comprobaciones preparadas |
|---|---|
| Configuración inicial | GET de zona/turnos de A y B; A sin turnos y zona null/Lima; mesas y combinaciones previas registradas. POST sin zona debe rechazar si era null. |
| Permisos | 401 sin token, 403 con encargado B y sin rol en consultas y escrituras propias de A. |
| Zona | Zona desconocida 422; PUT Lima 200; cambio UTC 200 y recálculo de ambos extremos; pruebas en Nueva York y regreso explícito a Lima. |
| Turnos | POST 201/Location/ETag y GET 200; medianoche explícita, adyacencia, PUT 200 con identidad estable; superposición, duración cero e inicio pasado rechazados. |
| Errores estacionales | Hora inexistente/repetida en inicio y fin, para POST y PUT, con 422/VALIDATION_ERROR y explicación exacta de H1. |
| Revisión | If-Match ausente 400 y obsoleto 412 en PUT de turno/zona; revisión del restaurante y ETag coherentes. |
| Idempotencia | Replay inmediato e histórico de POST/PUT turno y PUT zona; respuesta, Location, ETag y cuerpo originales, sin incrementar la revisión. Clave con otro cuerpo 409. |
| Conservación | Cada rechazo compara zona y lista antes/después. Final: exactamente dos turnos propios y siete escrituras aceptadas; mesas/combinaciones conservadas y B sin cambios. |

La revisión final debe ser la inicial +7: cuatro PUT de zona, dos POST de turno y
un PUT de turno. Los rechazos y replay no añaden revisiones. Los snapshots técnicos
de mesas/combinaciones reflejan la nueva revisión común, pero sus datos se comparan
excluyendo solo ese campo. No se interpreta una revisión compartida nueva como
una modificación de capacidad, etiqueta o integrantes.

El checkpoint persiste la intención antes de enviar cada solicitud: URI, método,
nombre de variable de token, cuerpo, clave, If-Match y resultado esperado. Guarda
respuestas de negocio, evidencia antes/después de rechazos y fecha UTC; no Authorization.
Se reemplaza atómicamente usando NullString en Windows PowerShell 5.1. Un fallo
conserva la intención y las claves; reanudar con el mismo comando. No cambiar claves,
fechas ni archivos de checkpoint. El checkpoint solo da por completo el recorrido
después de comparar las lecturas finales reales, no por tener solicitudes guardadas.

Si falla mientras la zona temporal está en UTC o Nueva York, esa situación queda
visible en el journal y en el mensaje inicial. Renovar tokens si expiraron y
reanudar el mismo comando hasta la etapa explícita de regreso a Lima. Si el fallo
requiere investigación, conservar todo y comunicar la salida; no forzar escrituras
ni restaurar una configuración sin revisar su revisión e idempotencia.

## Reinicio manual

4. Después del mensaje de recorrido completo, detener y volver a iniciar la versión
   actual en IntelliJ en 8082, con el mismo gate y configuración. Mantener abierta
   la PowerShell que contiene los tokens. Si A expiró, renovar solo A con su comando.
5. Ejecutar:

```powershell
& .\scripts\dev\Test-LocalShifts.ps1 -AfterRestart
```

Hace únicamente GET de zona, colección, ambos recursos y mesas/combinaciones de A;
exige igualdad de datos, ambos extremos, identidad, revisión y ETag respecto al
checkpoint final. Registra `operatorDeclaredRestart=true`: no detecta ni ejecuta
el reinicio por sí mismo. Cambios posteriores de otros escritores invalidan la
comparación; no se reemplaza la referencia final para ocultarlos.

## Evidencia y verificaciones pendientes

### Corrección de la comparación POST/GET

El primer intento del usuario se detuvo después de GET-turno: el script comparaba
indebidamente 201/Location del POST con 200/sin Location del GET. El checkpoint
conserva 19 etapas, dos escrituras aceptadas (zona Lima y primer turno), revisión
11 y cuerpos/ETag iguales en POST y GET. No acredita el resto del recorrido.

Se corrigió únicamente esa comparación: Check-CreatedGet exige GET 200, mismo
cuerpo y ETag que el POST y ausencia de Location. Same-Reply conserva la comparación
estricta de estado, cuerpo, ETag y Location para replay. No se modifica checkpoint,
fechas, claves, backend ni OpenAPI. Reanudar con el mismo comando de ambos permisos;
las etapas registradas se reutilizan y no se crea otro ensayo.

Validación aislada en Windows PowerShell 5.1: sintaxis válida; dos comparaciones
válidas aceptadas y ocho diferencias rechazadas (estado/cuerpo/ETag/Location para
GET y para replay). Solo se cargaron las funciones de comparación desde el AST con
datos sintéticos; no se ejecutaron el cuerpo del script, HTTP, suites ni servicios.
T087 sigue abierta, sin commits ni cierre.

La preparación se validó mediante análisis sintáctico en Windows PowerShell 5.1,
sin ejecutar el script ni HTTP, suites, servicios, Docker o commits. La sintaxis
válida no acredita el comportamiento frente al entorno real.

El usuario validó previamente compilación y suites 230/121 y el contrato OpenAPI:
válido sin errores, seis avisos (localhost y TableInput, TablePatch, Table,
CombinationInput y Combination sin uso). Se conservaron las reglas y el contrato.

T087 seguirá abierta hasta revisar evidencia específica. Este recorrido no acredita
el reloj exactamente actual, edición de historia, reservas protegidas, fallos del
lector ni carreras reales: sus pruebas automatizadas conservan ese alcance.
Tampoco acredita gates, respaldo/restauración aislada o reversión; no se heredan
automáticamente ensayos anteriores de SPEC-001/002. SPEC-003 no se cierra ni aprueba.

## Git Bash — opcional, después de revisar los archivos

```bash
git add scripts/dev/Test-LocalShifts.ps1 docs/disponibilidad-turnos-http.md docs/disponibilidad-turnos-validacion.md README.md
git diff --cached --check
git diff --cached --stat
git commit -m "test: prepare manual shift and time zone HTTP checks"
```

La documentación SDD externa al servicio no se añade al Git de SpringWebFlux.
