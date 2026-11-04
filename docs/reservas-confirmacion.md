## Resultado comunicado por el usuario — 2026-11-02

Comprobación pura de este recorrido exitosa; el chequeo node del helper de gate también terminó sin errores. No acredita HTTP, Mongo o reinicio. Registrado por el agente a partir de la salida del usuario.

---

# Confirmación de reservas — T126 preparada

Fecha: 2026-11-02. Autor: agente (implementación/inspección).
T126 es preparación del recorrido, no evidencia de ejecución ni activación.
SPEC-005 38/42; lote 95/103. T127–T130 pendientes; T191 de 008 abierta.

## Preparación realizada

Test-LocalReservationConfirmation.ps1 reutiliza funciones de transporte existentes
mediante AST (solo esas funciones, sin ejecutar el recorrido de cancelación),
comparadores estructurales/temporales de H1–H3 y manifiesto de confirmación de solo
lectura. No modifica los helpers compartidos ni el contrato/backend.

Incluye 401 sin token, 403 sin perfil/encargado sin CUSTOMER, grupo inválido422,
POST201 con versión1/ETag/Location, asignación y snapshot válidos contra oferta,
recibo exclusivo y revisión +1, duplicado activo409 y conflicto de clave409.
Cuenta dual opcional con turno distinto permite replay tras otra escritura.
Cada rechazo/replay compara manifiesto completo sin nuevas escrituras.
Cada POST aceptado protege documentos previos, índices, recibos, opciones,
política y metadatos no afectados usando el helper de confirmación existente.
No comprueba por sí solo que la opción sea óptima entre todas las alternativas:
el desempate/asignador tiene pruebas automatizadas; revisión total en T130.

Checkpoint propio secrets/local-identity/reservation-confirmation-http-checkpoint.json,
sin JWT, con bloqueo exclusivo y guardado atómico compatible con PowerShell5.1.
Congela identidad, turno, cuerpo y clave antes de escribir. Al reanudar recupera
primero la intención pendiente y verifica delta/recibo; no inventa otra clave.
Sin recibo, exige estado anterior conservado y plazo vigente; con recibo,
recupera respuesta original sin repetir negocio. Cambiar identidad o parámetros
detiene el ensayo. Checkpoints desconocidos se conservan y rechazan.
El reinicio solo consulta, contrasta cuerpo/ETag con cada POST, y conserva el
manifiesto final. Un reinicio es declaración del operador, no observación del agente.

## Prerrequisitos y pasos manuales futuros

NO ejecutar HTTP todavía: primero T127, T128 y T129, respaldo restaurable, corte
persistente verificado, SHA/JAR puente compatible e identidades preparadas.
Este script no activa gates ni configura Keycloak. Solo después de esas condiciones,
el responsable activa manualmente los gates y reinicia IntelliJ en 8082.

Restaurante A debe tener metadata/índices existentes y oferta verificada; no se crea
infraestructura ni configuración para superar un rechazo. Elegir turno propio,
futuro dentro de [ahora+2h, ahora+90d], con plazas libres para PartySize (1–20).
No debe existir una confirmada del mismo cliente en ese turno ni bloqueo por legado.
Proporcionar margen temporal para terminar el ensayo; plazos se comprueban al aceptar.
DualShiftId es opcional y debe ser otro turno libre; EATS_HUB_TOKEN_DUAL con CUSTOMER.
Faltando ese parámetro, el script registra el caso dual como pendiente, no aprobado.
Tokens necesarios en la misma terminal: EATS_HUB_TOKEN_CUSTOMER_A,
EATS_HUB_TOKEN_A y EATS_HUB_TOKEN_NO_ROLE; añadir DUAL si corresponde.
Obtenerlos con Get-LocalToken.ps1 y los usuarios locales ya preparados.
Evitar otros escritores hasta comprobar el reinicio. Se conservan una o dos reservas
nuevas; no se cancela ni borra ninguna fixture anterior.

Desde <WORKSPACE>\SpringWebFlux, después de completar prerequisitos
(sustituir los UUID, no ejecutar literalmente los marcadores):

    & .\scripts\dev\Test-LocalReservationConfirmation.ps1 -ShiftId 'UUID-TURNO-LIBRE' -PartySize 2 -DualShiftId 'UUID-OTRO-TURNO-LIBRE' -AllowFixtureWrites -AllowDatabaseReads -DedicatedFixtures -ActivationPrerequisitesConfirmed

Reanudar con los mismos parámetros si se interrumpe; renovar token con la misma
identidad si expira. No borrar ni alterar checkpoint/clave para forzar resultados.
Al terminar, reiniciar manualmente Eats Hub en IntelliJ 8082, conservando gates:

    & .\scripts\dev\Test-LocalReservationConfirmation.ps1 -AfterRestart -AllowDatabaseReads -ActivationPrerequisitesConfirmed

## Comprobaciones y evidencia

Comprobaciones puras redactadas en Test-ReservationConfirmationAssertions.ps1:
tres interrupciones (antes de POST, respuesta perdida, guardado interrumpido),
identidad equivocada, recuperación con una sola escritura, repetición sin efectos,
deriva externa, formato de checkpoint y comparación POST/GET.
Usan funciones reales de etapa con dobles explícitos; no ejecutan HTTP ni Mongo.

Validación del agente: análisis de sintaxis PowerShell5.1; scripts NO ejecutados.
No hay evidencia de comprobación pura ni recorrido de T126 ejecutados por el usuario.
Resultados 275/210 y comprobaciones H1–H3 anteriores conservan su alcance histórico.

Ejecutar ahora solo la comprobación pura, sin aplicación ni Docker necesarios:

    powershell.exe -NoProfile -File .\scripts\dev\Test-ReservationConfirmationAssertions.ps1

No recompilar Java por estos scripts. Bordes exactos 2h/90d, última mesa concurrente,
revocación antes de replay, ocupación incierta y corte de API antigua requieren sus
pruebas/ensayos específicos; no los acredita este script secuencial.
T127/T128/T129 preparan recuperación, gates y secuencia integral; T130 revisa evidencia.
Ninguna spec se cierra automáticamente. No se ejecutaron servicios, suites, HTTP,
Docker, corte ni acciones Git.
