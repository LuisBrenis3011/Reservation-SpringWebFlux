# SPEC-003 — HTTP validado y gates preparados

T087 abierta: 26/27 tareas, lote 87/88; sin cierre ni aprobación formal.

## Evidencia del usuario contrastada

El usuario ejecutó el recorrido y reinició manualmente IntelliJ. El agente leyó
el checkpoint propio sin ejecutar HTTP: 61 etapas con respuestas esperadas,
httpCompleted=true, siete escrituras aceptadas, revisión 16, zona America/Lima y
dos turnos conservados. Fin HTTP: 2026-10-29T01:19:02.3184149Z; reinicio declarado
comprobado por GET: 2026-10-29T01:21:30.0964677Z (2026-10-28 en America/Lima).
El reinicio se acredita como declaración del usuario, no como reinicio ejecutado
o detectado automáticamente por el agente.

SHA-256 del checkpoint original:
`F811D7069AD980D8AFECAF43959FEEED28540CCBE48E4BEF4C5019B2C66D7FCE`.
No se escribe en ese archivo. Las comprobaciones operativas futuras no heredan
aprobaciones de SPEC-001/002.

## Procedimiento manual — solo GET

Se preparó `scripts/dev/Test-LocalShiftGate.ps1` reutilizando el procedimiento de
combinaciones. Exige HTTP y reinicio completados. Guarda intentos en otro archivo:
`secrets/local-identity/shifts-gate-checkpoint.json`, ligado al runId y hash de la
referencia HTTP. Usa bloqueo exclusivo y reemplazo atómico compatible con PS 5.1.
No guarda tokens ni cambia .env, reinicia servicios o crea fixtures. Enabled exige
una comprobación Disabled exitosa del mismo checkpoint y enlaza su attemptId.
Conserva los intentos anteriores; si cambia el checkpoint, se detiene sin sobrescribir.

Evitar otras escrituras en A/B hasta terminar ambas etapas. No volver a ejecutar
el recorrido HTTP/reinicio para renovar su referencia durante este ciclo.

1. En el `.env` de SpringWebFlux, cambiar manualmente solo esta línea:

```properties
AVAILABILITY_ENABLED=false
```

2. Detener y volver a iniciar la aplicación actual en IntelliJ en **8082**.
   Si la configuración de ejecución define la misma variable, evitar que prevalezca
   sobre .env. El resultado HTTP es lo que comprueba si se aplicó el cambio.
3. En PowerShell, desde SpringWebFlux:

```powershell
& .\scripts\dev\Test-LocalShiftGate.ps1 -Stage Disabled
```

Debe comprobar cinco respuestas: catálogo antiguo 200, zona 404, colección 404 y
ambos recursos de turnos 404. No necesita token para esta etapa.

4. Cambiar manualmente la misma línea a:

```properties
AVAILABILITY_ENABLED=true
```

5. Reiniciar la aplicación actual en IntelliJ en **8082**. Obtener token A en la
   PowerShell que ejecutará el script (no se necesitan B ni sin-rol en esta etapa):

```powershell
& .\scripts\dev\Get-LocalToken.ps1 -User encargado-a -CopyPassword
```

6. Después de completar el inicio de sesión, ejecutar:

```powershell
& .\scripts\dev\Test-LocalShiftGate.ps1 -Stage Enabled
```

Debe comprobar once respuestas: catálogo 200; zona, colección y ambos turnos 401
sin token y 200 con token; mesas y combinaciones 200 con token. Comparará cuerpos
completos, fechas/horas, ambos instantes, zona, identidad, revisión 16 y ETag con el
checkpoint HTTP, incluidas las colecciones de mesas/combinaciones. No cambia la
referencia para aceptar diferencias. Un resultado inesperado detiene el registro
del intento; conservar archivos y comunicar la salida.

## Validación y límites

Sintaxis revisada en Windows PowerShell 5.1, sin ejecutar el script, HTTP, suites,
Docker ni servicios. Ese análisis no acredita las etapas Disabled/Enabled: ambas
siguen pendientes de ejecución del usuario y revisión de evidencia.

Los GET no prueban directamente índices/recibos de Mongo. Siguen pendientes
respaldo/restauración aislada específica de zonas/turnos, reversión compatible y
cierre. No se borraron datos, cambiaron gates ni hicieron commits desde el agente.

## Git Bash — sugerido tras revisar la entrega

```bash
git add scripts/dev/Test-LocalShiftGate.ps1 docs/disponibilidad-turnos-gate.md docs/disponibilidad-turnos-validacion.md
git diff --cached --check
git diff --cached --stat
git commit -m "test: prepare shift availability gate checks"
```

La documentación de specs permanece fuera del Git del servicio. Conservar los
cambios locales del recorrido HTTP anterior al preparar cualquier commit.
