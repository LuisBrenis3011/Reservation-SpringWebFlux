# SPEC-002 — Reversión compatible y vuelta a la versión actual

**Resultado posterior del usuario, contrastado el 2026-10-28:** sesión
20261028-173335-a530a760, Previous 4/4 y Current 6/6 correctos; hashes y manifiestos
coincidentes. T060 completada. [Entrega verificada, pendiente de aprobación formal](disponibilidad-combinaciones-entrega.md).
Los pasos siguientes conservan las instrucciones originales, no indican una nueva ejecución pendiente.

## Evidencia y versión elegida

El 2026-10-28 se contrastó por lectura el respaldo del usuario
`backups/availability/20261028T053931Z-7892c3033d144c5a97c7f41f07fd62dd`:
19 documentos, dos combinaciones, nueve recibos totales y siete del ensayo;
revisión 9 e índice único. spec-002-validation.json, manifiestos completos de
origen antes/después y destino restaurado coinciden; los hashes del archive y
checkpoints HTTP/gate también coinciden. No se ejecutó otra restauración.

Versión anterior: **72fa5311a0d724582381dd968e226daca6f3d311**, cierre de SPEC-001.
Su coordinador, guard, inicializador y servicio de reservas coinciden con los
actuales en los archivos comparados; no incorpora el router de combinaciones.
Se arrancará con el gate desactivado y todos los otros escritores detenidos.
No se ensaya volver a una versión sin coordinación ni guard.

Se amplió Test-LocalVersionRollback.ps1 con -IncludeCombinations y -BackupDirectory.
El modo sin estos parámetros conserva el procedimiento anterior. La sesión
propia es `secrets/local-identity/combinations-rollback-session.json`: no reemplaza
rollback-session.json. El checkpoint del respaldo y el checkout se conservan.

## Controles y límites

Prepare exige el respaldo específico, manifiestos y hashes correctos, checkpoints
coincidentes, 8082 detenido, declaración de escritores detenidos y código productivo
sin diferencias ni fuentes nuevas sin versionar. Exporta el commit anterior con
git archive en una carpeta nueva de backups/availability-rollback y construye
bootJar sin suites. No cambia rama, índice ni archivos fuente del checkout.

Las demás etapas exigen la sesión y el hash del JAR, el mismo HEAD preparado,
código productivo intacto y el mismo respaldo validado. Se compara todo el
manifiesto de Mongo: colecciones, conteos, documentos BSON, opciones e índices.
Esto conserva combinaciones, su índice único, revisión y todos los recibos,
incluidos los siete históricos ya verificados en el respaldo. No se restaura
una copia vieja sobre la base ni se envían writes de negocio o replay HTTP.

Current exige haber validado Previous, una JVM diferente a la anterior en 8082,
reinicio manual en IntelliJ, autenticación y GET de colección/recurso con datos,
revisión y ETag originales. La identificación del arranque actual es declaración
del operador más comprobaciones de código/HTTP; no una atestación binaria de IntelliJ.

La sintaxis fue revisada en Windows PowerShell 5.1. El agente no compiló JAR,
ejecutó Docker, servicios, HTTP ni suites. La reversión continúa pendiente.

## Pasos manuales — una línea por comando

Desde SpringWebFlux, mantener Mongo y Keycloak activos. No ejecutar otros recorridos
ni escrituras hasta terminar. Dejar .env con AVAILABILITY_ENABLED=true para la
vuelta a IntelliJ; el JAR anterior recibirá false como argumento explícito.
Detener Eats Hub en IntelliJ y todos los escritores antes de Prepare.

**Primera PowerShell:** preparar el JAR, sin arrancarlo:

```powershell
& .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage Prepare -WritersStopped -IncludeCombinations -BackupDirectory 'backups/availability/20261028T053931Z-7892c3033d144c5a97c7f41f07fd62dd'
```

Requiere Java 21/JAVA_HOME. Si hay sesión previa de SPEC-002 o datos distintos,
el script se detiene; no borrar sesiones ni modificar checkpoints para forzarlo.

**Segunda PowerShell**, situada en la misma raíz del servicio: arrancar solo el
JAR anterior y dejar esta terminal abierta mientras se ejecuta:

```powershell
& .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage StartPrevious -IncludeCombinations
```

Cuando arranque en 8082, **volver a la primera PowerShell** y comprobar:

```powershell
& .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage Previous -IncludeCombinations
```

Se espera catálogo 200, mesas y colección/recurso de combinaciones 404, Mongo sin
cambios. Si pasa, ir a la **segunda terminal, donde corre el JAR**, y detenerlo
con **Ctrl+C**. Después iniciar la versión actual desde IntelliJ en 8082, gate=true.

En la primera terminal renovar el token de encargado-a:

```powershell
& .\scripts\dev\Get-LocalToken.ps1 -User encargado-a -CopyPassword
```

Después de «Token guardado», comprobar la vuelta:

```powershell
& .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage Current -IncludeCombinations
```

Se espera catálogo 200, rutas protegidas sin token 401, colección/recurso propios
200 y datos/revisión/ETag conservados, además de manifiesto idéntico al respaldo.
Comunicar las salidas y conservar la carpeta del ensayo. No cambiar HEAD ni hacer
commits entre Prepare y Current. Los archivos de evidencia no contienen JWT.

## Git Bash — después del ensayo

```bash
git add scripts/dev/Test-LocalVersionRollback.ps1 README.md docs/disponibilidad-combinaciones-reversion.md docs/disponibilidad-combinaciones-respaldo.md docs/disponibilidad-combinaciones-validacion.md
git diff --cached --check
git diff --cached --stat
git commit -m "test: prepare compatible rollback verification for combinations"
```

No se hacen commits automáticamente. T060 y la aprobación formal siguen pendientes
hasta revisar los resultados; SPEC-002 no se cierra ni se avanza a SPEC-003.
