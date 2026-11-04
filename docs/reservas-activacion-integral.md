## Estado vigente del puente — 2026-11-04

El flujo del [plan externo](../../specs/005-confirmar-reserva/bridge-plan.md) y
sus consumidores están implementados para preparar el artefacto, verificarlo de
forma aislada, revisar la cadena v2 y usar el mismo JAR en la reversión gestionada.
El usuario comunicó Passed en 12 grupos sintéticos y sintaxis JavaScript de la
integración actual AF_PACKET+strace (catálogo 1.4.0), conservados en
`bridge-all-synthetic-d76dca93d66a4ea5973c1f83a43aa7a8`. Los casos conservan Pending
cuando no acreditan las etapas completas. El candidato/JAR real
`20261104T183001Z-1fee331299b24ac5981c58fa9193eceb` está Prepared; no hay
evidencia real de aislamiento ni Review real comunicados. El corte y la reversión
siguen bloqueados hasta cumplir sus prerrequisitos y recibir autorización explícita.

El usuario comunicó OK sintético para Assertions, PreparationAssertions,
IsolationAssertions, CatalogAssertions y ExecutionAssertions, y posteriormente
para ReviewAssertions y ExecutionAssertions. Confirmó un commit de Review sin SHA.
En la ronda posterior el usuario comunicó OK de recuperación, Review, corte y
orquestación sintéticos. La primera salida de RollbackAssertions no incluyó el
mensaje final; posteriormente el usuario ejecutó la versión instrumentada y comunicó
su OK completo, fixture bridge-synthetic-b2a05ec4bbdf4d5cad0e2c60f656fad9.
No se determinó la causa de la salida anterior ni se supone un commit de reversión.
Las ejecuciones sintéticas no acreditan Docker, HTTP, Mongo, aislamiento ni aprobación.
El estado de subpasos se conserva en [tasks.md](../../specs/005-confirmar-reserva/tasks.md).

La siguiente acción es una sola validación sintética mediante
Test-ReservationBridgeAllAssertions.ps1. El nuevo método usa SYS_PTRACE y seccomp
acotado únicamente en el observador, sin ampliar permisos de APP. Cada JVM espera
la comprobación de TracerPid antes de exec; strace cubre intentos sin paquete y
AF_PACKET cubre paquetes. Una pérdida de observación invalida el ensayo. El
responsable autorizó este cambio de contrato; no equivale a ejecutar ni aprobar
el aislamiento real. Los reportes 1.3.0 deben regenerarse para 1.4.0.

---

# Secuencia integral de reservas — T129

Fecha: 2026-11-02. Documento preparado por el agente; no constituye ejecución,
autorización para cambiar gates, aplicación del corte ni aprobación de entrega.
SPEC-005 41/42; lote 98/103. T130 y T191 siguen abiertas; sin cierre de specs.

## Evidencia disponible

- Usuario: comprobación pura T126 («OK: recuperacion e invariantes sinteticos...»)
  y comprobación pura T128 («OK: etapas, politica, snapshots, hashes y preflight...»).
  Ejecutó node --check de read-reservation-gate-probe.js sin mensajes y regresó al
  prompt. El agente registra lo comunicado; no ejecutó esas comprobaciones.
- T127: Test-ManagedReservationRecoveryAssertions.ps1 y node --check de
  read-managed-reservation-policy.js SIN resultado comunicado. Pendientes.
- Recorridos HTTP de 004–008, reinicios, gate integral, respaldo post-corte y
  reversión gestionada: SIN evidencia aportada. No transferir validaciones de 001–003.
- No se identificó SHA/JAR puente ni se produjo BridgeEvidence; el estado vivo de
  gates, Mongo, política, identidades y Docker no fue consultado en esta tarea.

## Orden de preparación y ejecución futura

1. Resolver validaciones puras pendientes de T127 y cualquier fallo de las de
   T126/T128. Revisar trazabilidad, scripts y sus limitaciones; comprobar que las
   cinco funcionalidades estén listas y que el usuario autorice los ensayos reales.
   No considerar que preparar un script prueba el comportamiento real.

2. Conocer el estado REAL de la política mediante un procedimiento de solo lectura
   y conservarlo en evidencia privada. Si la lectura falla, si hay datos v2 sin
   política coherente o el estado no coincide con la secuencia prevista, detener.
   Nunca usar modos antiguos de reversión una vez aplicado el corte.

3. Con writers detenidos y gates de reservas apagados, crear respaldo previo y
   restaurarlo únicamente en destino aislado usando el procedimiento preparado.
   Contrastar archive/hash, source-before/source-after/restored, documentos,
   índices, opciones y política; conservar ruta y evidencia. No restaurar sobre
   origen ni borrar bases, contenedores, volúmenes o checkpoints anteriores.

4. Identificar y acreditar ANTES del corte un commit y JAR puente reales. Congelar
   scripts C1 y catálogo; usar PrepareArtifact, VerifyIsolated y Review en ese orden.
   Review requiere cuatro reportes completos Passed y produce BridgeEvidence v2
   con autor y referencias verificables al candidato, JAR y reportes. Sus banderas
   se derivan de esos reportes; no se inventan ni se elige automáticamente un commit.
   El corte valida la cadena antes de contactar origen y otra vez antes de Apply.
   Está bloqueado mientras C1 permanezca Pending o falte evidencia real revisada.

   Prepare de la reversión gestionada requiere corte activo y respaldo posterior;
   no produce la evidencia previa al corte. El script de T127 además exige que el commit puente coincida con HEAD en fuentes
   productivas/Gradle y que no haya cambios productivos locales; verificar que exista
   un candidato real que cumpla esa restricción antes de planificar su uso.

5. Preparar Keycloak/identidades de desarrollo mediante scripts existentes solo de
   forma manual y autorizada. Obtener CUSTOMER_A, CUSTOMER_B, DUAL y encargados en
   la misma PowerShell; mantener tokens en memoria. Verificar firma, issuer, audiencia,
   roles y pertenencia. No publicar credenciales ni volcar JWT en checkpoints.

6. Solo tras 2–5, con escritores detenidos y reservations.enabled=false, ejecutar
   primero el preflight de corte preparado con BackupDirectory y BridgeEvidence
   realmente verificados. Examinar salida y conservar evidencia; el preflight por sí
   solo no aplica el corte. Cualquier Apply es una acción posterior explícita del
   responsable. El corte persistente retira escrituras antiguas; apagar el gate
   posteriormente NO lo revierte. No efectuar Apply mientras exista el bloqueo 4.

7. Después del corte verificado y con prerequisitos aprobados, activar manualmente
   availability.enabled y reservations.enabled, reiniciar IntelliJ en 8082 y ejecutar
   recorridos propios de 004–008 con fixtures dedicadas, permisos y checkpoints
   separados. T126 confirma reservas, 004 consulta disponibilidad, 006 consulta
   autorizada, 007 modifica y 008 cancela; el orden exacto debe respetar sus fixtures
   y evitar escritores competidores no controlados. En cada uno, comprobar reinicio
   manual y registrar solo casos realmente ejecutados. No confundir pruebas sintéticas
   ni comandos preparados con resultados HTTP. Q4, límites exactos y casos opcionales
   permanecen pendientes cuando no haya evidencia específica.

8. Después de completar checkpoints de los cinco recorridos, preparar baseline del
   gate integral. Disabled y Enabled se ejecutan después de cambios de gate y reinicios
   manuales, sin otros escritores. Comprobar catálogo, 404/401, disponibilidad pública,
   lectura antigua autorizada y 410 del legado, snapshots/ETag y manifiesto íntegro.
   Conservar hashes originales. El ensayo usa UUID inocuo verificado para DELETE;
   no usar el ID real de la fixture. La exclusión de escritores es declaración
   operativa y no un bloqueo distribuido. No ejecutar si la política no es verificable.

9. Con writers detenidos, producir respaldo POSTERIOR gestionado y restaurarlo
   aisladamente; comprobar las reservas v2, política, revisiones, recibos, índices,
   archive y hashes de checkpoints. El respaldo anterior al corte no sirve como
   evidencia de reversión gestionada con datos posteriores.

10. Solo si 4 y 9 están acreditados, ensayar Prepare, StartPrevious, Previous y
    Current mediante sesión gestionada separada y evidencia v2 revisada. Cada etapa
    recibe BridgeEvidence y revalida cadena, JAR y C1. Prepare copia y comprueba los
    mismos bytes certificados sin recompilar; BridgeCommit, si se indica, debe
    coincidir. Las sesiones gestionadas anteriores se conservan y rechazan.
    StartPrevious exige corte aún verificable y puerto libre. Previous acredita
    catálogo, rutas ocultas y manifiesto; detener con Ctrl+C en la terminal del puente.
    Reiniciar manualmente la versión actual y ejecutar Current; contrastar GET,
    ETag y estado persistido vigente, no solo el recibo histórico. No restaurar una
    copia anterior sobre origen ni volver a una versión sin barrera.

11. T130 y las tareas de evidencia de 004/006/007/008 revisan resultados por actor,
    versión y fecha; registrar fallos y casos no ejecutados. La aprobación final de
    cada spec es separada y explícita. Los checkpoints y respaldos son evidencia
    privada, no sustituyen revisión ni autorización del responsable.

## Comandos de validación pendientes, NO operativos

Desde <WORKSPACE>\SpringWebFlux, el usuario puede validar la
preparación T127 sin Docker ni servicios:

    powershell.exe -NoProfile -File .\scripts\dev\Test-ReservationBridgeAllAssertions.ps1

El usuario comunicó OK de las comprobaciones anteriores, incluidos 54 C1. La
versión 1.4.0 y su ejecutor conjunto todavía no tienen resultado comunicado.
Node --check y las fixtures del parser strace se incluyen en esta única entrada.
No se proponen comandos de Apply ni de ejecución HTTP hasta resolver el bloqueo de
puente y verificar prerequisitos. Los comandos futuros de respaldo/recorridos figuran
en docs/reservas-recuperacion.md, docs/reservas-confirmacion.md y
docs/reservas-gate-revision.md; sus marcadores no son valores ejecutables.

## Límites de esta tarea

El documento registra implementación y resultados comunicados; no constituye
ejecución de HTTP, Docker, builds, servicios ni Git, ni cambia gates, política,
datos o checkpoints. La comprobación estática de sintaxis no acredita pruebas.
T129 marca la secuencia documentada; no acredita que sea ejecutable con la evidencia
actual. El bloqueo de puente y la validación T127 siguen pendientes.
