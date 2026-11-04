# SPEC-003 — Entrega verificada, cerrada y aprobada

T087 completada por revisión de evidencia. SPEC-003: **27/27 tareas**; lote
**88/88**. Cierre aprobado expresamente por el responsable del proyecto en esta conversación el **2026-10-29**, sin nombre consignado. Las aprobaciones
de SPEC-001/002 mantienen su alcance original.

## Funcionalidad entregada

GET/PUT de zona horaria y POST/GET/PUT de turnos por fechas concretas, con permisos
por restaurante, futuro estricto, medianoche explícita y adyacencia permitida.
Rechaza superposiciones y horas locales inexistentes/repetidas con explicación.
Cambiar zona conserva locales de turnos futuros, recalcula ambos instantes y
mantiene la historia intacta; un conjunto inválido se rechaza de forma atómica.
Protege reservas futuras, en curso y antiguas sin adaptar. Reutiliza coordinador,
guard, Clock, inicializador y soporte HTTP, con If-Match, ETag e idempotencia.

## Ejecuciones del usuario y revisión del agente

El usuario ejecutó todas las comprobaciones siguientes. El agente inspeccionó
archivos y hashes; no repitió suites, compilaciones, Docker, servicios o HTTP
durante esta revisión final.

| Evidencia | Resultado contrastado |
|---|---|
| Compilación y pruebas tras H1–H3 | Usuario: compilación exitosa; XML 230 seleccionadas y 121 integración, cero fallos/errores/omitidos. |
| RF/escenarios y contrato | Revisión de 8 RF/24 escenarios; seis operaciones OpenAPI. Usuario: lint válido, cero errores y seis warnings conocidos, sin ocultar reglas. |
| HTTP y reinicio | Checkpoint SPEC-003: 61 etapas, siete escrituras, revisión 16 y dos turnos. GET tras reinicio declarado conserva zona, ambos extremos y ETag. |
| Gate | Disabled 5/5 y Enabled 11/11, enlazados al mismo checkpoint y revisión. |
| Respaldo/restauración aislada | 29 documentos; manifiestos de origen antes/después y restaurado iguales, archive y checkpoints con hashes coincidentes. Prueba específica: zona Lima, dos turnos, índices, revisión 16 y siete recibos del ensayo (16 recibos totales). |
| Reversión Previous | 6/6, UTC 2026-10-29T01:55:20.357831Z: catálogo 200 y rutas nuevas 404; manifiesto intacto. |
| Regreso Current | 10/10, UTC 2026-10-29T01:56:56.489517Z: catálogo 200, autenticación requerida y GET autorizados 200 con zona, turnos, revisión y ETag originales; manifiesto intacto. |

Marcas UTC del 29 corresponden al 28 de octubre en America/Lima. Los reinicios,
writers detenidos y regreso a IntelliJ se registran como declaraciones del usuario,
no como acciones ejecutadas por el agente.

## Vínculo entre artefactos

- Sesión: `secrets/local-identity/shifts-rollback-session.json`, run
  `20261029-015315-1e667987`. Previous/Current coinciden en run, spec, commits,
  hash JAR, hash de la prueba de respaldo y preservación del manifiesto.
- Versión anterior: `5031d8e878045637ceee9e197c3cf80da5475a4e`.
  Versión actual preparada: `ba174e07e5bbf90d03c291a5f00616ca46450591`.
- JAR anterior SHA-256:
  `44166E5542CFCCE594B8C1A40134BCC2744A370A827CEBA0675CB23F95BC3AD1`.
- Respaldo: `backups/availability/20261029T014445Z-aacbf97c253f41eb81fd6ab7a92bc9b9`.
  spec-003-validation.json SHA-256:
  `AF2BBAED8749364137DB6BDCAACA6E20DE520B0707115D9959184661A31F87EC`.
- Archive SHA-256:
  `97B0A23ACB398884274FAE9408260781DDDBEDC706631D239FCFC25D0104B583`.
- Checkpoint HTTP SHA-256:
  `F811D7069AD980D8AFECAF43959FEEED28540CCBE48E4BEF4C5019B2C66D7FCE`.
- Checkpoint gate SHA-256:
  `18099AFD91AAD364D3C5BC8E2F4FF72F06DBF1F1C7ACF3E7063F51BF19C760CF`.

El database-before de la sesión coincide en colecciones con el respaldo. Las
evidencias Previous/Current registran la comparación integral posterior; esta
revisión no vuelve a consultar Mongo ni afirma conocer cambios posteriores.

## Límites y siguiente decisión

Ensayos locales; no certifican producción, carga, alta disponibilidad ni volver
a una versión sin guard/coordinación. La restauración fue aislada, no sobre el
origen. La selección test no equivale a ejecutar la suite test completa. No hay
calendarios recurrentes, DELETE de turnos ni asignación real de reservas por mesas.
Los datos y fixtures del ensayo se conservan; no se ejecuta limpieza automática.

H1–H3 quedaron validados con su alcance automatizado. No se añaden tareas o
funcionalidades por esta revisión. El responsable aprobó el cierre el 2026-10-29.

## Validación y Git

No es necesario repetir suites o recorridos por cambios documentales. Se revisaron
coherencia, hashes, recuentos y enlaces. No se hicieron commits ni se alteró el índice.

Git Bash, desde SpringWebFlux, para registrar la entrega y los archivos locales
de los recorridos que todavía no están versionados:

```bash
git add README.md docs/disponibilidad-turnos-entrega.md docs/disponibilidad-turnos-validacion.md
git diff --cached --check
git diff --cached --stat
git commit -m "docs: record approved SPEC-003 closure"
```

Revisar el contenido preparado antes del commit. No añadir secrets/ ni backups/.
Los documentos SDD externos al servicio no pertenecen al Git de SpringWebFlux.
