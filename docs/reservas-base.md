# Base compartida de Gestión de reservas — SPEC-005, fase 2

Fecha: 2026-10-29. Alcance: T090–T112, después de T089 documental.
Registro histórico de entrega. Validación posterior del usuario: compilación,
243 pruebas seleccionadas y 137 de integración exitosas, según XML inspeccionados.
El avance vigente y la fase 3 constan en [confirmación](reservas-confirmacion.md).
Implementación y pruebas redactadas; compilación y suites de esta entrega pendientes
de ejecución del usuario. No acredita confirmación HTTP, activación ni cierre.

## Componentes y contratos internos

| Tareas | Entrega y responsabilidad |
|---|---|
| T090 | Identidades de prueba cliente/otro cliente/encargado/dual sobre fixtures existentes; contexto Mongo efímero reutilizado |
| T091–T093 | Documento v2 en `reservations`, estado propio, repositorio condicionado por restaurante/titular/estado/versión e integridad de capacidades y tiempos |
| T094–T096 | Actor desde JWT validado, perfil CUSTOMER explícito, plazos inclusivos 2 horas/90 días y selector determinista de opciones configuradas |
| T097 | Ocupación por turno con validación previa de referencias y tiempos del legado; un fallo nunca significa mesa libre |
| T098–T100 | `MutationOutcome<T>` y `writeWithOutcome`: changed conserva el flujo previo; noChange revierte el incremento provisional y guarda recibo en la revisión anterior; replay recupera la respuesta y revierte la escritura provisional |
| T101 | Índices únicos parciales de mesa ocupada y titular confirmado, más índices de listas; colisiones conservadas y preparación rechazada |
| T102–T104 | DTO/mapper, JSON estricto, fingerprint de actor/método/ruta/cuerpo/If-Match, clave interna `rsv:` y reserva del prefijo en configuración |
| T105–T108 | Política persistente de corte, barrera en handler y servicio antiguos, seguridad y gate nuevo apagado por defecto; inicializador verifica política, v2 y namespace |
| T109–T110 | Contadores de resultado acotados y logs con operationId, sin JWT, notas ni identificadores de cliente/reserva; un exporter fallido no cambia el resultado de negocio |
| T111–T112 | Pruebas de base y revisión de dependencias, interfaces y comandos manuales |

Se mantienen las firmas `write`, `readSnapshot` y `writeLegacy`, el máximo de tres
intentos y el presupuesto de cinco segundos. El ETag de reservas representa su versión
propia; `expectedRevision` queda null en la metadata del coordinador común.

`ReservationHttpSupport` exige que sus futuros consumidores autoricen antes del replay
y vuelvan a comprobar el recurso dentro de la sesión. No sustituye esa autorización
con la posesión de una clave. Las rutas y comandos gestionados se implementarán desde T113.

## Dependencias y límites

- U1: el lector contrasta turno y mesas del restaurante y todos los extremos temporales
  antes de filtrar por el turno solicitado. No modifica el adaptador ni los guards de oferta.
- I1: T112 incluye T095 y T096; no deja el selector ni los plazos para otro propietario.
- U2: la consulta multirrestaurante de SPEC-006 reutilizará template/TransactionalOperator;
  no se crea aquí otro coordinador ni un restaurante ficticio.
- Q4: la cancelación futura verificará su propia reserva sin depender del lector global
  ni del guard de oferta. Aquí no se implementa cancelación productiva.
- C1: la adaptación de scripts de reversión es T127 y sigue pendiente. Los scripts
  históricos no acreditan compatibilidad después del corte de reservas gestionadas.
- No se preparó identidad Keycloak nueva, marca de corte, migración, login, API nueva
  ni scripts operativos. No se cambió `.env` ni el contrato OpenAPI.

El arranque de esta revisión prepara índices mediante el inicializador existente.
Una colisión o dato v2 inválido aborta la preparación; no se borra ni regulariza.
`RESERVATIONS_ENABLED` sigue false por defecto. La lectura antigua tiene protección
de autenticación/rol; la autorización detallada por restaurante pertenece a SPEC-006.
No activar el nuevo flujo local antes de completar sus dependencias y gates de entrega.

## Pruebas redactadas y evidencia

- `ReservationCoordinatorOutcomeTests` y `ReservationCoordinatorOutcomeIT`: rechazo
  previo al callback, recibo noChange, replay, conflicto de clave, contención acotada
  y commit recuperable. Los failpoints se restituyen en finally.
- `ReservationFoundationPolicyTests`: identidad dual, selección, integridad y fallo
  de lectura de la política.
- `ReservationSecurityBaseTests`: nuevas rutas ocultas, legado autenticado y catálogo.
- `ReservationInfrastructureIT`: índices multikey/titular, colisión sin borrado,
  huérfana con/sin corte, política inválida y referencias de legado ajenas/inexistentes
  o temporalmente incoherentes. Limpieza limitada a fixtures propias.
- `ReservationTelemetryTests`: resultados y etiquetas de cardinalidad acotada.
- Las pruebas antiguas de CRUD reciben una barrera controlada en su fixture unitaria.

Autoría: el agente redactó e inspeccionó fuentes; no ejecutó compilación ni suites.
El usuario informó BUILD SUCCESSFUL antes de esta ampliación, para los fixtures
iniciales. Ese resultado no valida los componentes agregados después. Los resultados
de SPEC-001/002/003 y el lint de SPEC-005 son evidencia heredada con su alcance original.

## Validación manual de esta entrega

PowerShell, una línea por comando desde el servicio:

```powershell
Set-Location '<WORKSPACE>\SpringWebFlux'
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Reservation*' --tests '*Availability*'
.\gradlew.bat integrationTest
```

El filtro Reservation incluye los tests nuevos y el CRUD existente. integrationTest
requiere el entorno de Testcontainers usado por las suites anteriores; los ensayos
usan Mongo efímero, no los documentos del Mongo local. Compartir resultado y, ante
fallos, el reporte específico. No declarar aprobado nada que carezca de evidencia.

## Avance

T089–T112 implementadas/documentadas: SPEC-005 24/42 y lote 24/103. Las casillas de
redacción no significan suites aprobadas. T113–T130 y las otras specs nuevas siguen
pendientes; fase 3 no iniciada. SPEC-005 continúa sin cierre ni aprobación formal.
