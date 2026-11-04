# SPEC-002 — Entrega cerrada y aprobada

Revisión de evidencia: 2026-10-28. T041–T060 completadas: **20/20 tareas**.
SPEC-002 cerrada y aprobada expresamente por el responsable el **2026-10-28**,
mediante «apruebo el cierre del spec 2» en esta conversación. No se consigna un
nombre que no fue indicado. No se inicia SPEC-003. Los documentos históricos de cada etapa
describen su situación al entregarse; este registro establece el estado vigente.

## Comportamiento entregado

POST y GET de colección, GET y PUT de recurso de combinaciones por restaurante.
Se conservan identidad y propietario al cambiar integrantes, se exige al menos
dos mesas propias distintas y se rechazan conjuntos equivalentes aunque cambie
su orden. La capacidad se deriva de las mesas vigentes; no añade plazas físicas.

Permisos de encargado y aislamiento por restaurante, cuerpo estricto, ETag,
If-Match e idempotencia con replay histórico sin incrementar revisión. Los cambios
efectivos protegen reservas futuras/en curso; legado sin adaptar e incertidumbre
de comprobación bloquean escrituras. No hay borrado, asignación de reservas ni turnos.
Se reutiliza la infraestructura de SPEC-001 y se mantiene el contrato OpenAPI.

## Ejecuciones del usuario y contraste del agente

| Evidencia | Resultado y alcance |
|---|---|
| Compilación y pruebas | Usuario: compilación exitosa, 184 seleccionadas y 91 de integración, sin fallos, errores ni omitidas. XML contrastados; 47/39 casos propios de combinaciones. No se presenta la selección como suite completa. |
| RF/ESC y contrato | Revisión documental: 7 RF y 16 escenarios trazados. Usuario: Redocly válido, cero errores y 8 avisos conocidos conservados. |
| HTTP y reinicio | 29 etapas HTTP; permisos, POST/GET/PUT, duplicados, revisión e idempotencia. Reinicio declarado manualmente y datos/ETag conservados; checkpoint inspeccionado. |
| Gate | Disabled/Enabled: 3/6 checks correctos, mismo ensayo/hash y vínculo de etapas, sin pérdida de datos. |
| Respaldo/restauración | Ejecución 20261028T053931Z-7892c3033d144c5a97c7f41f07fd62dd: 19 documentos, dos combinaciones, cuatro mesas, nueve recibos totales y siete del ensayo, revisión 9, índice único conservado y origen intacto. |
| Reversión compatible | Sesión 20261028-173335-a530a760: Previous 4/4 y Current 6/6, con documentos/índices/revisiones/recibos idénticos al respaldo y ETag conservado. |

La reversión usó como anterior `72fa5311a0d724582381dd968e226daca6f3d311` y como
commit actual preparado `4cebf1645cfc0d6cf1852cd45cb6e48cd4fcd904` (incluye el código
de combinaciones de `53c0901`). Previous fue registrado a las 17:35:01.3248498Z y
Current a las 17:37:12.3764399Z del 2026-10-28: **12:35 y 12:37 en America/Lima**.
Ambos enlazan el mismo run, versión, hash del JAR y hash de spec-002-validation.json;
los procesos registrados son distintos. El reinicio actual es declarado por el usuario.

El agente contrastó por lectura la sesión, Previous/Current, manifiesto previo a
reversión y manifiestos source-before/source-after/restored del respaldo. Coinciden
los hashes del JAR, archive, prueba de respaldo y checkpoints HTTP/gate. No se
ejecutaron nuevamente Docker, servicios, recorridos, compilación ni suites en esta
revisión; no se borraron datos, hicieron commits ni se alteraron archivos privados.

Fuentes privadas, fuera de Git: secrets/local-identity/combinations-rollback-session.json,
checkpoints HTTP/gate, carpeta backups/availability indicada arriba y
backups/availability-rollback/20261028-173335-a530a760. No publicar sus archivos,
backups, contraseñas o JWT. Esta guía no incluye cuerpos de reservas ni tokens.

## Límites y aprobación registrada

Se acredita un ensayo local con una versión anterior compatible y guard conservado.
No acredita reversión a una versión sin coordinación, alta disponibilidad,
producción ni autenticación del servidor restaurado. Las comprobaciones operativas
de T060 están completas; la aprobación formal de entrega y cierre fue comunicada
por el responsable el 2026-10-28 y se registra sin atribuirle ejecuciones al agente.

Los avisos OpenAPI por localhost y siete schemas sin uso permanecen documentados.
No hace falta repetir suites por esta actualización exclusivamente documental.
