# Revisión T143 — SPEC-004

## Corrección H1–H3 preparada

El 2026-10-30 el usuario confirmó BUILD SUCCESSFUL de la validación solicitada.
Los XML inspeccionados por el agente reportan 255 seleccionadas y 164 de integración
sin fallos, errores ni omitidas (4 unitarias y 12 de integración de disponibilidad).
Esta evidencia no acredita recorridos HTTP reales, gates o cierre.

Inspección posterior del agente el 2026-10-30: XML disponibles con 255 seleccionadas
y 164 de integración sin fallos/errores/omitidas; incluyen 4 unitarias y 12 de
integración específicas de disponibilidad. El usuario no comunicó aún la ejecución
de H1–H3 en esta solicitud; autoría y compilación por confirmar. No se acredita HTTP.

Las pruebas siguientes fueron redactadas o ampliadas; **su compilación y ejecución
siguen pendientes del usuario**. No se ha acreditado aún la corrección en ejecución.

- H1: `ReservationAvailabilityIT.limitesEnRespuestaYFechaLocalLima` cubre inicio
  now, extremos inclusivos, TOO_FAR visible y cruce de medianoche en Lima. El test
  HTTP con item no vacío verifica los campos exactos y ausencia de ETag.
- H2: `ReservationAvailabilityTransactionIT` usa el TransactionalOperator y Mongo
  efímero reales. Provoca error de consulta en el servidor durante ocupación, captura
  los recursos transaccionales de ambas lecturas y exige UNDETERMINED tras cambiar
  de sesión. Prueba también fallo de oferta inicial y de oferta en fallback. Estos
  ensayos no se han ejecutado ni verificado; el test controlado anterior permanece.
- H3: `ReservationAvailabilityConcurrencyIT` realiza dos consultas y compara
  documentos e índices de restaurantes, reservas, metadata, recibos, oferta,
  turnos, zona y política; conserva la confirmación competidora y reevaluación.

Tras la ejecución del usuario, contrastar XML y registrar resultados sin
transferirlos a HTTP real. T144, gate, respaldo, reversión y aprobación permanecen
pendientes. No se cambió OpenAPI ni se ejecutaron compilaciones o suites aquí.

## Revisión original

Revisión estática del agente; no ejecución de suites, HTTP, servicios, Docker o Git.
T143 completada como revisión con hallazgos, no como aprobación de la funcionalidad.
T144 y cierre siguen pendientes. No se cambió código productivo ni OpenAPI.

## Trazabilidad comprobada

| RF | Escenarios | Evidencia disponible y límites |
|---|---|---|
| RF-04.1 | ESC-04.1/2 | IT de fecha local/medianoche y pruebas de grupo 0/21. La fixture temporal usa UTC; no acredita por sí sola una zona distinta de UTC. |
| RF-04.2 | ESC-04.3/4 | IT de opción suficiente y combinación que comparte mesa ocupada, reutilizando selector de 005. |
| RF-04.3 | ESC-04.5/6/11/12 | HTTP público con lista vacía, IT de TOO_SOON visible y política con extremos exactos. Faltan comprobaciones de respuesta con items, exclusión del inicio exactamente now y visibilidad de TOO_FAR: H1. |
| RF-04.4 | ESC-04.7/8 | UNAVAILABLE tras ocupación y matriz U1: turno/mesa desconocidos o ajenos, snapshot incoherente. Fallback de dos suscripciones después de rollback controlado; no acredita aborto real de sesión Mongo: H2. |
| RF-04.5 | ESC-04.9/10 | IT de GET sin metadata/recibo y confirmación posterior que reevalúa. No comprueba explícitamente dos visitantes ni conservación completa de documentos/índices durante el GET: H3. |

Los 5 RF y 12 escenarios tienen enlaces; eso no significa cobertura automatizada
completa ni que cada paso del escenario haya sido acreditado.

## H1 — Bordes y proyección pública

Completar pruebas del servicio y HTTP con items no vacíos: inicio exactamente now
excluido; exactamente 2 horas y 90 días OPEN; más de 90 días visible TOO_FAR,
reservable=false, manteniendo ocupación independiente del plazo. Comprobar fechas
locales con una zona distinta de UTC y cruce de medianoche. Validar campos exactos
del contrato y ausencia de mesas, titular, notas, reserva, revisión global y ETag.

La inspección del DTO y handler coincide con la proyección prevista, pero el test
HTTP actual solo usa items vacíos. No sustituirlo por una afirmación de cobertura.

## H2 — Fallos y sesiones

Conservar el test controlado que espera rollback antes de la segunda suscripción.
Añadir integración con fallo Mongo que aborte realmente la primera transacción y
compruebe recuperación mediante otra sesión/snapshot de oferta, sin reutilizar la
sesión abortada. Añadir fallo de oferta inicial y fallo de oferta durante fallback:
ambos deben devolver 503, sin convertirlos en lista vacía o disponibilidad libre.
Restituir failpoints y limpiar solo fixtures propias, sin ejecutar esos ensayos
automáticamente ni tocar Mongo local.

## H3 — No retención y conservación

Completar ESC-04.9 con dos consultas de visitantes que observan la última opción
sin adquirirla. Comparar documentos, asignaciones/versiones, metadatos, recibos e
índices antes/después de las consultas. Mantener ESC-04.10: una confirmación
competidora posterior obliga a reevaluar y rechazar la asignación incompatible.
No confundir consulta informativa con reserva o retención provisional.

## Contrato y script

OpenAPI se leyó sin modificarlo ni ejecutar lint. DTO y ruta coinciden por inspección
con AvailabilityList/AvailabilityItem y GET público. El código evita escribir desde
ensureInitialized reutilizando el TransactionalOperator existente; esto está registrado
como ajuste técnico respecto al uso inicial previsto de readSnapshot.

T142 prepara un script separado, sin Authorization ni JWT persistidos, con checkpoint
propio y reemplazo atómico. Compara manifiestos durante consultas. Baseline puede
estar vacío y no acredita bordes ni incertidumbre en ese caso; coverage solo marca
casos observados. Las etapas de ocupación/incertidumbre requieren estados reales
preparados por otros recorridos autorizados, sin inyección automática. AfterRestart
registra una declaración manual de reinicio, no prueba que el proceso se reinició.
Gate, respaldo/restauración, reversión y aprobación siguen pendientes.

## Evidencia y autoría

- Usuario: comunicó BUILD SUCCESSFUL de compilación y suites de SPEC-005 fase 3;
  su registro contrastado es 251 seleccionadas y 152 de integración.
- Agente: inspeccionó XML posteriores disponibles con totales 254 seleccionadas y
  160 de integración, cero fallos, errores y omitidas. El usuario aún no confirmó
  en este pedido los comandos/procedencia de esos XML ni la compilación de 004.
- Dentro de esos XML: tres casos unitarios específicos de disponibilidad y ocho
  de integración (1 concurrencia, 5 U1 y 2 disponibilidad), todos reportados sin
  fallos/errores/omitidas. No cubren automáticamente H1–H3.
- HTTP real de 004, reinicio, gates y evidencia operacional: pendientes; no se
  ejecutaron aquí ni se atribuyen al usuario por la mera existencia del script.

Siguiente paso recomendado: corregir H1–H3 dentro de la funcionalidad existente,
validar por ejecución manual del usuario y después continuar la entrega. No cerrar
SPEC-004 ni avanzar automáticamente a T144.
