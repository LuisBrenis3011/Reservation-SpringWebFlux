# Revisión T159 — SPEC-006

## Validación comunicada de H1–H3 — inspección 2026-11-02

El usuario confirmó BUILD SUCCESSFUL de compilación, pruebas seleccionadas
`*Reservation*`/`*Availability*` e integración. El agente solo inspeccionó XML:
**260 seleccionadas y 176 de integración**, cero fallos, errores y omitidas.
Incluyen ReservationQueryAuthorizationTests, ReservationQueryPaginationIT y
ReservationQueryContractIT, un caso cada uno sin fallos. Modificación local de XML:
2026-10-30; la fecha de inspección no representa una nueva ejecución.
H1–H3 cuentan con validación automatizada reportada por el usuario y contrastada
en XML. Los apartados inferiores de pendientes describen el estado anterior.
T160, HTTP operativo y aprobación siguen pendientes; no se cierra ninguna spec.

## Corrección H1–H3 preparada — 2026-10-30

Cambios implementados/pruebas redactadas, **pendientes de compilación y ejecución
del usuario**. No se acreditan aún resultados de esta revisión.

| Hallazgo | Corrección y prueba preparada |
|---|---|
| H1 | `managed` rechaza antes de buscar si el actor no es CUSTOMER ni encargado del local. Conserva `requireAccess` dentro de la sesión. ReservationQueryAuthorizationTests exige cero interacciones con Mongo y el operador; ContractIT comprueba 403 tanto para ID existente como inexistente de local ajeno. |
| H2 | ReservationQueryPaginationIT compara páginas pequeñas con el orden BSON obtenido de Mongo; excluye otro titular y legado, verifica CONFIRMED/CANCELLED, página vacía, size100 y parámetros fuera de rango. ContractIT añade parámetros repetidos/estado inválido. El test U2 con escritura competidora se conserva. |
| H3 | ReservationQueryContractIT usa handler, router, cadena de seguridad y servicio efectivos sobre el Mongo efímero existente. Cubre cinco GET positivos, campos exactos, ETag solo de recurso gestionado, roles/locales y GET antiguo con gate apagado. Compara documentos e índices de nueve colecciones antes/después, incluidos revisiones y recibos. |

El cambio de gate de ContractIT afecta solo al bean del contexto efímero del test
y se restituye en finally; no se modificó `.env` ni ningún servicio local. No se
cambió OpenAPI ni se ejecutaron compilaciones, suites, HTTP, servicios, Docker o
Git durante esta corrección. Los XML anteriores 259/174 no validan estos archivos.

T160, recorridos reales y aprobación de SPEC-006 continúan pendientes. Registrar
resultados únicamente cuando el usuario ejecute la validación indicada en el quickstart.

## Revisión original

Fecha: 2026-10-30. Inspección estática del agente, sin ejecutar suites, HTTP,
servicios, Docker, lint o Git. T159 completada como revisión con hallazgos;
no acredita aprobación ni cierre. T160 permanece pendiente.

## Matriz de trazabilidad

| RF / escenarios | Evidencia comprobada y límites |
|---|---|
| RF-06.1, ESC-06.1/2 | QueryHttpTests cubre ausencia de identidad, lista vacía y 404 simulado; RestaurantQueryIT verifica titular ajeno y dual; SnapshotQueryIT filtra varios locales/otro titular. Autorización temprana y páginas/filtro requieren H1/H2. |
| RF-06.2, ESC-06.3/4 | RestaurantQueryIT verifica encargado local/ajeno y dual; GET antiguo se prueba en servicio con LegacyQueryIT. Falta HTTP integrado del adaptador con gate apagado: H3. |
| RF-06.3, ESC-06.5/6 | SnapshotQueryIT conserva UTC histórico frente a zona actual Lima, estado cancelado y ausencia de ocupación; cursor por lotes con escritura competidora acredita el diseño U2 en XML. Falta respuesta HTTP positiva/ETag: H3. |
| RF-06.4, ESC-06.7/8/11 | LegacyQueryIT y LegacyProjectionTests cubren proyección limitada, cliente sin acceso, huérfana y tipos de referencia. La prueba de correo no atribuye identidad por inspección del filtro; falta verificación de campos exactos por HTTP: H3. |
| RF-06.5, ESC-06.9/10 | QueryFailureIT cubre vacío sin metadata, fallo real de find y v2 inválida. RestaurantQueryIT compara documentos de reservas/revisión/recibos; no compara todos los índices/documentos en HTTP: H3 y recorrido pendiente. |

Los cinco RF y once escenarios tienen enlaces; eso no demuestra que todos los
casos y controles del contrato estén suficientemente probados.

## H1 — Autorización antes de buscar el detalle gestionado

`ReservationQueryServiceImpl.managed` obtiene el actor, pero busca el documento
antes de exigir CUSTOMER o permiso de encargado para ese restaurante. Un actor
autenticado sin ambos permisos recibe 403 si el documento existe y 404 si no existe.
Esta diferencia puede revelar existencia a un perfil que debía rechazarse antes
de leer. No se observó por HTTP: es una conclusión del flujo estático.

Corregir con comprobación previa: admitir la lectura solo si el actor tiene CUSTOMER
o gestiona ese local. Mantener la comprobación posterior de titular/local dentro
de la sesión; un CUSTOMER ajeno continúa recibiendo 404. Probar que perfiles sin
permiso reciben el mismo 403 ante IDs existentes o inexistentes, sin consultar Mongo.
No cambiar reglas de negocio ni hacer pública ninguna ruta.

## H2 — Paginación, orden y filtro de /me

Las pruebas de integración usan page=0/size=20/status=null. Falta demostrar páginas
consecutivas no solapadas en el orden BSON de _id, tamaño límite, filtro CONFIRMED/
CANCELLED y rechazo de parámetros inválidos/repetidos. El código contiene esos
controles, pero no se deben declarar validados por las pruebas actuales. Reutilizar
fixtures de dos restaurantes y otro titular, incluyendo canceladas y legado que
deben excluirse de /me. Mantener el test U2 del snapshot durante escritura competidora.

## H3 — Contrato HTTP y conservación

Los dos casos HTTP actuales solo cubren /me vacío, identidad ausente, page negativo
y un 404 simulado. Faltan respuestas positivas y campos exactos de detalle gestionado,
lista mixta y legado; ETag de versión solo en gestionadas, ausencia en listas/legado;
separación de roles/locales y adaptación real del GET antiguo con gate apagado.
Completar esas pruebas con handler/router/seguridad efectivos y comparar documentos,
versiones, metadata, recibos e índices alrededor de lecturas/rechazos con Mongo efímero.
No basta añadir más aserciones sobre respuestas simuladas para acreditar autorización.

## Contrato, script y límites operativos

Se leyó OpenAPI y se contrastaron las cinco rutas, schemas, page/size/status y ETag;
no se modificó ni se ejecutó lint nuevo. La lógica U2 usa template/operador existentes,
no inicializa metadata ni inventa un restaurante. GET antiguo delega al query handler
y conserva la barrera de escrituras; H1 no afecta a esa barrera.

T158 conserva un checkpoint propio sin JWT y compara manifiestos alrededor de GET.
Legado y huérfana se prueban solo si se proporcionan referencias reales; las listas
observadas son primera página. Reinicio es declarado manualmente; igualdad de
snapshot no acredita por sí sola una zona actual distinta. Cancelada solo se acredita
si la reserva elegida tiene ese estado. No existen resultados HTTP comunicados aquí.

## Evidencia y autoría

El usuario comunicó BUILD SUCCESSFUL en compilación de las cuatro fuentes Gradle,
pruebas seleccionadas e integración de fase 3, después de corregir el genérico del
helper Principal. El agente inspeccionó XML con **259 seleccionadas y 174 de integración**,
cero fallos, errores y omitidas. Los XML específicos de consulta incluyen 2 casos
QueryHttpTests y 10 de integración (3 LegacyQueryIT, 4 QueryFailureIT, 1
RestaurantQueryIT y 2 SnapshotQueryIT). LegacyProjectionTests aporta soporte unitario.
Es evidencia del código probado, no de H1–H3 corregidos ni de HTTP real.

No se ejecutó nada operativo en esta revisión. El siguiente trabajo recomendado es
corregir H1–H3, entregar comandos y esperar resultados del usuario. T160, activación,
respaldo/restauración, reversión y aprobaciones formales siguen pendientes.
