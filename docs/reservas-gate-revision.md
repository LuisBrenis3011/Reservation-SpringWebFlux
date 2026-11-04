## Resultado comunicado por el usuario — 2026-11-02

Comprobación pura de este recorrido exitosa; el chequeo node del helper de gate también terminó sin errores. No acredita HTTP, Mongo o reinicio. Registrado por el agente a partir de la salida del usuario.

---

## T128 preparada — 2026-11-02

SPEC-005 40/42, lote 97/103. Se preparó el recorrido de gates y comprobaciones
puras; no se ejecutaron. T129/T130 y T191 abiertas; sin activación ni cierre.
T126/T127 siguen pendientes de resultados comunicados por el usuario.

Test-LocalReservationGate.ps1 usa checkpoint propio
secrets/local-identity/reservation-integral-gate-checkpoint.json y lock exclusivo.
Exige checkpoints 004–008 existentes, baseline/reinicio registrado, hashes sin
cambios y ninguna intención pendiente en confirmación/cancelación. No reemplaza
esos checkpoints ni almacena JWT. El responsable declara -NoOtherWriters:
no deben coexistir otros escritores durante todo el ensayo.

Baseline exige gates habilitados, corte persistente comprobado, LegacyId existente
del restaurante A legible por encargado y una reserva propia del checkpoint 005.
Conserva manifiesto completo, política, hashes, lectura antigua, disponibilidad y
snapshot/ETag de la reserva. Disabled/Enabled se ejecutan después de cambios y
reinicios MANUALES, no comprobados por el proceso; el operador declara esos reinicios.
Comparan manifiesto, política y lectura antigua. Enabled compara reserva, ETag y
proyección temporal/disponibilidad con Baseline; observedAt y ventana no se usan
como datos persistidos. 404 se prueba con gate apagado, 401 en rutas protegidas
al reactivar y 200 en disponibilidad pública. Solo se acredita el detalle
de la reserva seleccionada; el manifiesto protege los demás documentos.

Cada POST/PUT antiguo se hace sin cuerpo. DELETE usa UUID aleatorio cuyo formato,
ausencia como string/BSON UUID y corte se comprueban inmediatamente antes mediante
read-reservation-gate-probe.js de solo lectura. Se repite preflight antes de cada
solicitud y se exige 410/LEGACY_WRITES_RETIRED y manifiesto inalterado. Esto requiere
exclusión operativa de otros escritores; no es bloqueo distribuido ni evita una
carrera externa si se incumple -NoOtherWriters. Nunca apuntar DELETE a LegacyId real.
No se migran, borran o crean fixtures de negocio ni se cambia .env/gate automáticamente.

Prerequisitos futuros: completar T129, SHA/JAR puente y respaldo restaurable; los
cinco recorridos y reinicios deberán estar realmente completos antes del baseline.
No ejecutar etapas mientras falte esa preparación. Tokens en memoria de la misma
PowerShell: EATS_HUB_TOKEN_A y EATS_HUB_TOKEN_CUSTOMER_A; renovar con misma identidad.
LegacyId es UUID de una reserva antigua verificable y autorizada para el encargado,
no el opaque legacyRef ni UUID inventado. Obtenerlo por procedimiento autorizado.

Desde el servicio, SOLO cuando el responsable haya cumplido los requisitos:

    & .\scripts\dev\Test-LocalReservationGate.ps1 -Stage Baseline -LegacyId 'UUID-LEGADO-AUTORIZADO' -AllowDatabaseReads -NoOtherWriters -ActivationPrerequisitesConfirmed

Cambiar reservations.enabled a false y reiniciar manualmente en IntelliJ 8082:

    & .\scripts\dev\Test-LocalReservationGate.ps1 -Stage Disabled -AllowDatabaseReads -NoOtherWriters -ActivationPrerequisitesConfirmed

Reactivar reservations.enabled, reiniciar manualmente en IntelliJ 8082:

    & .\scripts\dev\Test-LocalReservationGate.ps1 -Stage Enabled -AllowDatabaseReads -NoOtherWriters -ActivationPrerequisitesConfirmed

No borrar checkpoint ni modificar claves/IDs ante fallo. Los reinicios se declaran,
no se observan automáticamente. Si se interrumpe una etapa antes de guardar,
se puede reintentar con los mismos parámetros y datos íntegros.

Comprobaciones puras redactadas: orden/duplicados de etapas, políticas válidas y
fallidas, snapshots semánticos/ETag, hashes, Base64 y preflight simulado.
No interactúan con HTTP, Docker o Mongo; preflight simulado no acredita ejecución
del helper JS ni previene por sí mismo carreras de escritores externos.

Validación ahora, desde el servicio y sin iniciar aplicación:

    powershell.exe -NoProfile -File .\scripts\dev\Test-ReservationGateAssertions.ps1
    node --check scripts/dev/read-reservation-gate-probe.js

El agente solo ejecutó el parser de PowerShell 5.1; no ejecutó scripts, pruebas,
HTTP, Docker, compilaciones o servicios. T126/T127 pendientes de resultados
comunicados por el usuario. Gate real, corte, restauración y cierre siguen pendientes.

---

# T128 — revisión preparatoria (pendiente de implementación)

Fecha: 2026-11-02. Inspección del agente, sin ejecutar HTTP, servicios, Docker o suites.
T126 y T127 siguen pendientes de resultados comunicados por el usuario.

## Dependencias y observaciones

T142, T126, T158, T173 y T189 están marcadas como preparación. Su ejecución real
y sus checkpoints completos todavía no están acreditados; no se deben inventar.
T129 sigue abierta y debe fijar secuencia de activación integral antes del recorrido.

ReservationSecurityConfig oculta con 404 las rutas nuevas cuando reservations.enabled
está apagado; con el gate encendido exige autenticación, salvo disponibilidad pública.
La API antigua /reservation/** mantiene su cadena de seguridad. ReservationHandler
llama LegacyReservationWriteBarrier antes de POST/PUT/DELETE y traduce el corte
persistente a 410; si no puede verificarlo debe fallar cerrado. El gate no revierte
el corte. La lectura antigua GET /reservation/{id} se adapta a consulta autorizada.

## Comportamiento que debe implementar el recorrido

1. Baseline con gate activo y corte persistente previamente acreditado. Congelar en
   checkpoint propio identidad, hashes de checkpoints de 004–008 realmente completos,
   política, manifiesto íntegro, consulta antigua autorizada y proyecciones de las
   reservas existentes; no guardar JWT. Exigir explícitamente fixture antigua propia.
2. El operador cambia el gate y reinicia manualmente. Disabled verifica catálogo,
   404 antes de autenticación en disponibilidad y operaciones nuevas, lectura antigua
   autorizada y escrituras antiguas 410 tras comprobar de nuevo la política. Las
   solicitudes de prueba deben ser no destructivas aun si la barrera fallara.
3. El operador reactiva el gate y reinicia manualmente. Enabled comprueba 401 de
   rutas protegidas sin token, disponibilidad pública cuando corresponda, lectura
   antigua autorizada y escritura antigua 410 con política nuevamente verificada.
   Comparar cuerpos semánticos, snapshots y ETag con baseline y manifiestos completos.
4. Checkpoint propio con lock, actualizaciones atómicas, IDs/identidades congeladas y
   verificación de hashes en cada etapa. No sobrescribir evidencia previa, no ejecutar
   escrituras HTTP de prueba hasta acreditar corte y objetivo inocuo, ni alterar .env.
   Reanudar solo si etapa anterior, identidad, política y datos permanecen coherentes.

No se ha creado el script T128 ni ejecutado pruebas. No marcar T128 como completa.
Pendiente de preparación: helpers de comparación de snapshots, preflight del objetivo
inocuo y dobles puros de fallo de política/cambio entre etapas, sin servicios reales.
