# SPEC-003 — Respaldo contrastado y reversión preparada

T087 abierta, 26/27 tareas; lote 87/88. Reversión sin ejecutar, aprobación final pendiente.

## Evidencia del respaldo

Ejecución del usuario, inspección del agente: respaldo
`backups/availability/20261029T014445Z-aacbf97c253f41eb81fd6ab7a92bc9b9`.
Los manifiestos source-before/source-after/restored coinciden y los hashes del
archive y de ambos checkpoints coinciden con spec-003-validation.json.
Se restauraron 29 documentos; la prueba específica acredita zona Lima, dos turnos,
revisión 16, índices y siete recibos del ensayo (16 recibos totales en la base).
No equivale todavía a prueba de reversión de versión.

## Versión y procedimiento

Test-LocalVersionRollback.ps1 añade -IncludeShifts, separado de -IncludeCombinations.
Conserva los modos anteriores y usa `secrets/local-identity/shifts-rollback-session.json`.
Exige respaldo específico, hashes de checkpoints/archive, manifiestos coherentes,
código productivo actual limpio frente a HEAD y sesión/JAR ligados por hash.
No hacer commits ni otras escrituras durante el ciclo: HEAD queda fijado en Prepare.
Los cambios documentales y scripts locales no alteran esa comprobación productiva.

Versión anterior: `5031d8e878045637ceee9e197c3cf80da5475a4e`, cierre de SPEC-002
anterior a las rutas de zona/turnos. Coordinador, guard, inicializador, lector de
compromisos y servicio de reservas coinciden con HEAD en los archivos comparados.
No incluye RestaurantShiftRouter. Con gate=false debe conservar colecciones e
índices desconocidos y no escribir datos durante el ensayo. La compatibilidad es
una conclusión de inspección que la ejecución manual debe confirmar.

Se exporta y compila únicamente el JAR anterior fuera del checkout, bajo backups;
no se cambian ramas, índice o fuentes. No se restaura un respaldo antiguo sobre
el origen. El manifiesto completo compara documentos BSON, opciones e índices,
incluidos zona, turnos, revisiones y todos los recibos antes y después de cada etapa.
Current además compara GET autorizados de zona, lista y ambos recursos, con sus
cuerpos completos y ETag originales. Los recibos se preservan por comparación del
manifiesto, no mediante replay que pudiera introducir escrituras.

## Etapas manuales — PowerShell

Mantener Docker/Mongo disponibles. Detener la aplicación en IntelliJ y todos los
writers antes de Prepare, y conservarlos detenidos salvo el proceso de lectura
que se indique. Desde SpringWebFlux, cada comando en una línea:

1. **Primera PowerShell:** preparar exportación y JAR. Este comando sí compila
   bootJar cuando lo ejecuta el usuario; no arranca la versión anterior.

```powershell
& .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage Prepare -WritersStopped -IncludeShifts -BackupDirectory 'backups/availability/20261029T014445Z-aacbf97c253f41eb81fd6ab7a92bc9b9'
```

2. **Segunda PowerShell**, desde SpringWebFlux: arrancar el JAR anterior en 8082,
   gate desactivado por argumento. Dejar esa terminal abierta hasta la etapa Previous.

```powershell
& .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage StartPrevious -IncludeShifts
```

3. Con el JAR anterior listo, **primera PowerShell**:

```powershell
& .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage Previous -IncludeShifts
```

Debe comprobar catálogo 200, mesas/zona/colección/ambos turnos 404 y manifiesto
idéntico al respaldo, identificando el proceso del JAR preparado.

4. Detener el JAR anterior con **Ctrl+C en la segunda PowerShell**, que lo ejecuta.
   Volver a iniciar la versión actual en IntelliJ en 8082, con gate habilitado.
   No cambiar la conexión a Mongo ni crear fixtures. Obtener token A en la primera:

```powershell
& .\scripts\dev\Get-LocalToken.ps1 -User encargado-a -CopyPassword
```

5. **Primera PowerShell**, tras completar el login:

```powershell
& .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage Current -IncludeShifts
```

Debe comprobar catálogo 200, mesas 401, zona/lista/ambos turnos 401 sin token y 200
con token, datos/revisión/ETag conservados y manifiesto completo sin cambios. Guarda
Previous/Current en la carpeta de sesión propia. No sustituye la aprobación formal.

Si una etapa falla, conservar sesión, JAR, backup y checkpoints y comunicar la salida.
No borrar sesiones para forzar otro ensayo ni repetir escrituras del recorrido HTTP.

## Validación de la preparación y límites

Sintaxis analizada en Windows PowerShell 5.1. El agente no ejecutó Docker,
compilaciones, servicios, HTTP, suites ni commits. Backup ya acreditado por el
usuario; reversión todavía pendiente de evidencia. T087 y cierre siguen abiertos.

Git Bash sugerido para después de revisar la entrega, fuera del ciclo de reversión:

```bash
git add scripts/dev/Test-LocalVersionRollback.ps1 docs/disponibilidad-turnos-reversion.md docs/disponibilidad-turnos-validacion.md
git diff --cached --check
git diff --cached --stat
git commit -m "test: prepare compatible shift version rollback"
```
