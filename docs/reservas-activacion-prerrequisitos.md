# Prerrequisitos de activación integral — revisión 2026-11-02

Inspección del agente; sin ejecución de suites, HTTP, Docker, servicios o acciones Git.
Checklist SPEC-005 16/16 y comprobación de prerrequisitos Spec Kit sin persistir
selección. No hay extensions.yml ni hooks configurados.

## Estado real y dependencias

| Tarea | Dependencias | Archivos / situación observada | Decisión |
|---|---|---|---|
| T126 | T125 de 005 y T157 de 006, ambas marcadas | Test-LocalReservationConfirmation.ps1 aún no existe | Siguiente tarea recomendada: preparar recorrido propio de confirmación/reinicio, sin ejecutarlo. |
| T127 | T157 de 006, marcada | Test-LocalMongoRestore.ps1 y Test-LocalVersionRollback.ps1 mantienen modos anteriores; no declaran IncludeManagedReservations ni verifican reservation_policy/corte según C1 | Pendiente; preparar ampliación y pruebas sintéticas. No usar sus modos históricos tras corte. |
| T128 | T142, T126, T158, T173, T189 | T142/T158/T173/T189 marcadas, T126 pendiente; Test-LocalReservationGate.ps1 ausente | Esperar T126. |
| T129 | T127 y T128 | Ambas pendientes; no hay secuencia integral acreditada ni SHA/JAR puente fijados por esta revisión | Esperar T127 y T128. No marcar ni activar por completar los consumidores. |

T127 está desbloqueada por T157 y puede prepararse separadamente después de T126;
no depende de que se ejecute el recorrido HTTP. Orden recomendado sin paralelizar
ediciones: T126 → T127 → T128 → T129. Preparar scripts antes de T129 no autoriza
ejecutarlos. No existe ciclo: la ejecución integral espera la preparación documental.

Los scripts de identidad/corte y los recorridos de 004/006/007/008 ya existen.
Su existencia solo acredita preparación, no usuarios realmente provisionados,
política persistente vigente, gates activos ni ensayos exitosos.
No se consultaron variables privadas ni Mongo; estado vivo de gates/corte no verificado.

## Condiciones de ejecución futura

- Cinco funcionalidades verificadas con evidencia y análisis de sus dependencias.
- Preparar T127/C1: lectura fiable de política en todos los modos y etapas antes
  de compilar, arrancar o acreditar; con corte rechazar modos/sesiones históricos.
  Admitir solo modo gestionado con sesión propia y SHA/JAR puente compatibles.
  Fallo al leer política rechaza; releer entre etapas, incluido corte entre Prepare
  y StartPrevious. Sin corte comprobado, conservar el comportamiento anterior.
- Respaldo previo restaurable en destino aislado, sin restaurar sobre origen.
  Identificar realmente versión puente compatible con v2, barrera y lectura segura006;
  no reutilizar automáticamente el SHA de las specs anteriores ni inventar hashes.
- Identidades locales y tokens en memoria; permisos explícitos para fixtures.
- T128 preparada y T129 documentada antes de activar manualmente. La activación
  depende de availability.enabled, reservations.enabled y política persistente.
  Apagar rutas nunca reabre escrituras antiguas.
- Cada resultado posterior debe indicar operador, comandos, versión, fecha y
  evidencia. No heredar cierres de 001–003 ni cerrar specs de reservas por estos pasos.

## Evidencia actual y siguiente paso

H1–H3 de 008: comprobación pura y dos chequeos de sintaxis JavaScript comunicados
como exitosos por el usuario, documentados en reservas-cancelacion-validacion.md.
No acreditan HTTP, Mongo, reinicio ni ejecución de los procedimientos de activación.

Preparar exclusivamente T126. Incluir POST, permisos, idempotencia/replay y reinicio,
recuperación de resultado incierto con intención congelada y comparadores semánticos.
Reutilizar helpers y separar casos opcionales/concurrentes de lo realmente ejecutado.
No introducir cambios de datos/gates, SHA ficticios, borrados ni regularización.
No implementar T127–T129 por anticipado; entregarlos como próximos pasos.
T191 permanece abierta.

Recuentos conservados: SPEC-005 37/42, SPEC-008 15/16, lote 94/103.
Esta revisión no completa tareas de implementación adicionales.
