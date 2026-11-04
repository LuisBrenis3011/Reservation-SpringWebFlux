# SPEC-003 — Gates validados y respaldo/restauración preparados

T087 abierta, 26/27 tareas; lote 87/88. Sin cierre ni aprobación formal.

## Evidencia recibida

El usuario ejecutó Disabled y Enabled. El agente contrastó ambos checkpoints:
referencia HTTP intacta, runId y hash coincidentes, Disabled 5/5 y Enabled 11/11,
con todos los checks aprobados y referencia explícita al intento Disabled.
Revisión 16 conservada. Marcas UTC: Disabled 2026-10-29T01:30:00Z y Enabled
2026-10-29T01:31:33Z (2026-10-28 en America/Lima; segundos mostrados sin fracciones).
El usuario cambió el gate y reinició manualmente; el agente no ejecutó HTTP.

## Ampliación del procedimiento

Test-LocalMongoRestore.ps1 añade `-IncludeShifts`, separado de `-IncludeCombinations`.
Sin el nuevo parámetro, conserva los modos de SPEC-001/002. No combinar ambos:
el checkpoint de SPEC-002 tiene una revisión histórica anterior a la configuración
de zona/turnos. El modo nuevo sí respalda la base completa, incluidas las mesas,
combinaciones y recibos anteriores, mediante el manifiesto integral existente.

El modo exige checkpoints de SPEC-003 completos, reinicio declarado y último gate
Enabled ligado a Disabled, con sus recuentos y revisión coherentes. Extrae siete
comandos aceptados, deduplicando por clave y contrastando sus replay. Transmite las
expectativas como JSON UTF-8 en Base64; no muestra su contenido ni credenciales.

read-shift-backup-requirements.js es de solo lectura y comprueba en cada manifiesto:

- Zona actual de A y revisión común del restaurante.
- Exactamente los dos turnos del checkpoint: UUID, propietario, ambos locales,
  zona e instantes. No recalcula ni reinterpreta sus snapshots al restaurar.
- Índice _id_ de zonas e índice no único restaurant_shift_interval con sus tres
  campos en orden. El índice de intervalos no garantiza ausencia de superposición.
- Los siete recibos originales: clave única por comando, fingerprint, estado,
  Location, revisión resultante y cuerpo histórico, distinguiendo zona de turno.

Se conserva el mecanismo previo: Mongo local 27018, imagen instalada del origen,
writers detenidos, archive copiado con docker cp, destino nuevo sin red externa ni
puertos publicados y volumen propio. No usa --drop ni restaura sobre el origen.
Compara documentos BSON, conteos, índices y opciones de toda la base antes/después
del respaldo, en el destino restaurado y de nuevo en origen. El destino vacío se
comprueba sin exigir previamente colecciones de ninguna spec.

Se conserva todo, incluidos intentos fallidos, archives, contenedores y volúmenes.
La evidencia nueva `spec-003-validation.json` vincula hashes de checkpoints y
archive con la prueba específica, junto con validation.json y manifiestos. Ningún
resultado preparado equivale a una ejecución aprobada del ensayo.

## Pasos manuales — PowerShell

1. Evitar nuevas escrituras. Detener Eats Hub en IntelliJ y **todos** los demás
   clientes que escriban en esta base. Mantener Mongo y Docker disponibles.
   No cambiar .env, borrar datos ni detener Mongo. El script comprueba que 8082
   no escuche, pero la ausencia de otros writers es una declaración del usuario.
2. Desde SpringWebFlux, ejecutar cada comando en una línea:

```powershell
Set-Location <WORKSPACE>\SpringWebFlux
& .\scripts\dev\Test-LocalMongoRestore.ps1 -WritersStopped -IncludeShifts
```

No necesita tokens. Si falla, conservar la carpeta y compartir la salida; no borrar
volúmenes ni cambiar checkpoints. Si una comprobación de origen falla, no se acredita
la restauración aunque exista un archive o un destino parcial.

3. Si termina correctamente, compartir la salida. Luego se puede volver a iniciar
   la versión actual en IntelliJ 8082 con gate habilitado. No hay que cambiar la
   conexión al Mongo de ensayo, cuyo puerto no se publica.

## Validación y límites

El agente revisó sintaxis PowerShell 5.1 y JavaScript con node --check. No ejecutó
Docker, Mongo, respaldos, restauraciones, HTTP, suites, servicios ni commits.
El ensayo real, la reversión compatible y el cierre siguen pendientes. No se
transfieren resultados de respaldos anteriores a las nuevas colecciones.

## Git Bash — sugerido tras revisar/validar

```bash
git add scripts/dev/Test-LocalMongoRestore.ps1 scripts/dev/read-shift-backup-requirements.js docs/disponibilidad-turnos-respaldo.md docs/disponibilidad-turnos-validacion.md
git diff --cached --check
git diff --cached --stat
git commit -m "test: prepare isolated shift backup restoration checks"
```

Conservar el resto de cambios locales anteriores; no añadir secretos o backups.
