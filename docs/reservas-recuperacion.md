# Recuperación de reservas gestionadas — T127 preparada

Fecha: 2026-11-02. Preparación/inspección del agente. Sin ejecutar procedimientos.
T126: no se recibió resultado de su comprobación pura ni de su recorrido; pendientes.
T127 preparada; SPEC-005 39/42, lote 96/103. T128–T130 y T191 abiertas; sin cierre.

## C1 y compatibilidad

Los dos puntos de entrada históricos cargan ManagedReservations.Common.ps1 y leen
la política del origen antes de seleccionar sesiones, exportar fuentes, compilar
o arrancar. Corte persistente activo rechaza Default/IncludeCombinations/IncludeShifts
y sesiones históricas. Lectura fallida, política inválida o v2/recibos sin política
verificable rechazan. Sin corte comprobado se conserva el flujo previo; los modos
son excluyentes. La política se relee antes de acciones críticas y acreditación,
y un cambio respecto del estado fijado en la invocación detiene la operación.
Cada nueva etapa vuelve a inicializar/verificar contra el estado actual del origen.
Las comprobaciones son por puntos; no equivalen a bloqueo distribuido. Exigir
escritores detenidos para respaldo/Prepare y ningún writer durante el ensayo.

read-managed-reservation-policy.js es exclusivamente lectura. Verifica rs0 PRIMARY
en origen, política, índices de ocupación/cliente, listas y recibos en modo prueba.
No crea documentos, no activa el corte ni normaliza reservas.

## Respaldo y restauración aislada

Test-LocalMongoRestore.ps1 incorpora -IncludeManagedReservations. Mantiene los modos
anteriores para origen sin corte. Conserva el protocolo de archive binario + docker cp,
destino nuevo con red none/sin puertos y volumen propio, comprobación de vaciedad y
comparación completa antes/después/restaurado/final. Nunca restaura sobre origen.
Incluye todos los documentos BSON, índices/opciones, reservas v2, política, revisiones
y recibos mediante manifiesto completo y prueba adicional gestionada.
Crea managed-validation.json con hashes de checkpoints y archive. No reemplaza
evidencia de 001–003 ni borra contenedores, volúmenes o respaldos.

CheckpointPaths opcional limita explícitamente archivos dentro de secrets/local-identity;
por defecto incluye los *checkpoint.json existentes. Tras corte exige el checkpoint
de confirmación con HTTP/reinicio completos y su hash; se comprueba que los hashes
seleccionados no cambien durante el ensayo. Esto no aprueba todos los gates o specs.
Antes del corte puede prepararse respaldo gestionado sin checkpoints v2; no sirve
como respaldo post-corte para las etapas de reversión gestionada.

Comando FUTURO, solo cuando T128/T129 y los prerrequisitos estén preparados, con
Eats Hub y todos los escritores detenidos:

    & .\scripts\dev\Test-LocalMongoRestore.ps1 -WritersStopped -IncludeManagedReservations

Conservar la carpeta de evidencia que imprima; no suponer nombre ni ruta aún existente.

## Puente SHA/JAR y sesión independiente

Test-LocalVersionRollback.ps1 enruta -IncludeManagedReservations a
Test-LocalManagedReservationRollback.ps1. Sesión propia:
secrets/local-identity/managed-reservations-rollback-session.json.
Exige BackupDirectory gestionado válido (archive, manifiestos y checkpoints coincidentes)
y BridgeCommit completo proporcionado explícitamente. No hay SHA predeterminado.
NO se identificó ni construyó una versión puente en esta tarea.

Restricción conservadora: el commit indicado debe existir y sus fuentes productivas,
recursos, Gradle y wrapper coincidir con HEAD productivo, sin cambios locales ni
fuentes sin versionar. Debe contener política, comandos y consulta segura. Se admite
un commit previo que conserve ese mismo código productivo. No es un procedimiento
para bajar a una implementación arbitraria. La ausencia de candidato verificable
detiene Prepare; no se elige un commit histórico de 001–003 ni se relaja la condición.

Prepare (ejecución futura del usuario) exporta el SHA indicado fuera del checkout y
compila solo bootJar. Fija SHA real, hash ZIP y hash JAR en sesión; compara Mongo
con el respaldo. No arranca la aplicación. Cada etapa revalida hashes, código/política
y origen antes de continuar. StartPrevious exige puerto libre y ejecuta SOLO ese JAR
en 8082 con ambos gates apagados, sin tocar .env ni retirar corte persistente.
Previous verifica proceso/JAR, catálogo200, reservas404 y manifiesto completo intacto.
Detener con Ctrl+C en la terminal del puente; iniciar versión actual en IntelliJ,
gates según guía integral y tokens renovados en la terminal de comprobaciones.
Current verifica proceso distinto, catálogo200, reservas401 sin token y GET propios
contra el snapshot vigente en Mongo (no contra recibos históricos anteriores a PUT
o cancelación), ETag y manifiesto idénticos al respaldo. No reejecuta escrituras.

Comandos FUTUROS de una línea; sustituir marcadores por valores realmente obtenidos:

    & .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage Prepare -WritersStopped -IncludeManagedReservations -BridgeCommit 'SHA-REAL-COMPLETO' -BackupDirectory 'RUTA-RESPALDO-VALIDADO'

En otra PowerShell, dejándola abierta:

    & .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage StartPrevious -IncludeManagedReservations

En la terminal de comprobaciones:

    & .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage Previous -IncludeManagedReservations

Tras detener el puente e iniciar manualmente la versión actual:

    & .\scripts\dev\Test-LocalVersionRollback.ps1 -Stage Current -IncludeManagedReservations

Ninguno de esos comandos debe ejecutarse todavía. T128/T129 preparan gates y orden
integral. Exigir identidades vigentes; jamás almacenar JWT en la sesión.

## Comprobaciones puras preparadas

Test-ManagedReservationRecoveryAssertions.ps1 cubre opciones excluyentes, JSON/Base64
con comillas/español, entradas inválidas, sin/con corte, lectura fallida y cambio
entre Prepare/StartPrevious que impide la acción simulada. No ejecuta Docker,
HTTP, compilación, JAR o bases. Usa dobles explícitos; inspecciona AST de los guards.
No acredita funcionamiento del Docker real, respaldo, puente o reversión.

Validación a cargo del usuario, desde <WORKSPACE>\SpringWebFlux:

    powershell.exe -NoProfile -File .\scripts\dev\Test-ManagedReservationRecoveryAssertions.ps1
    node --check scripts/dev/read-managed-reservation-policy.js

Registrar separadamente la comprobación T126 si aún no se ejecutó:

    powershell.exe -NoProfile -File .\scripts\dev\Test-ReservationConfirmationAssertions.ps1

El agente solo revisó sintaxis PowerShell5.1 y código; no ejecutó pruebas, HTTP,
Docker, Git, compilaciones ni servicios. Toda evidencia operativa y cierre siguen
pendientes. No se modificó backend ni OpenAPI. Las condiciones futuras no son
resultados acreditados. Siguiente tarea preparada: T128, sin ejecutar ni activar.
