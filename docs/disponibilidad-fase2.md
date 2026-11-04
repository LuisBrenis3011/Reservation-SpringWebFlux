# Fase 2 — infraestructura compartida

T005–T017 y T088 implementadas. Compilación de main, fixtures, test e integrationTest
comprobada sin ejecutar suites. Los endpoints de mesas/combinaciones/turnos aún no
existen: conservar AVAILABILITY_ENABLED=false. No se inició Docker ni se migraron datos.

## Cambios de entorno

La versión exige Mongo replica set desde el arranque, también con gate=false.
Preparar el entorno separado y la restauración siguiendo
[conservación y transición](disponibilidad-preparacion.md). No apuntar al destino
vacío como sustituto de los datos antiguos. Detener writers para respaldo final,
verificar restauración y luego configurar MONGODB_URI; MongoConfig ahora la consume.
Mantener MONGODB_DATABASE coherente con la base indicada en la URI y conservar
MONGODB_PASSWORD local porque la configuración de compatibilidad aún la declara.

No se requiere JWT externo con gate=false. Gate=true requiere issuer, JWK y audiencia;
las rutas nuevas usan RS256, las anteriores conservan su acceso/formato. El gate no
desactiva transacciones ni permite writes antiguos sin coordinación. Un origen
standalone producirá fallo de arranque: no es un fallo de la suite de unitarias.

## Validación por el usuario

Desde PowerShell en la raíz de SpringWebFlux:

```powershell
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test --tests '*Availability*' --tests '*ReservationCrudServiceImplTests'
.\gradlew.bat integrationTest
```

La selección de test anterior no carga el contexto completo ni depende del Mongo
local. integrationTest requiere Docker y crea bases/replicas efímeras, sin usar .env
para conexiones. Incluye casos de standalone, JWT ausente, timeout y fallos de commit;
no usar NO-SOURCE o pruebas omitidas como evidencia de aprobación.

Después de preparar el replica set local, restaurar/verificar los datos y configurar
la URI, ejecutar la suite completa:

```powershell
.\gradlew.bat test
```

contextLoads carga la aplicación real y valida el entorno local; no se reemplazó
por un mock ni se deshabilitó. Si falla por standalone/credenciales, corregir el
entorno según el procedimiento de migración; no eliminar la comprobación.

## Comportamiento y revisión

- Revision por restaurante mediante incremento real dentro de transacción snapshot/
  majority/primary. Transitorios: tres intentos con 50/100 ms; callback secuencial.
- Replay aborta incremento provisional y retorna recibo original. El resultado del
  commit incierto no se presenta como rollback: resolver con misma clave.
- Presupuesto de callback 5 s y commit limitado por plazo restante para nuevas
  escrituras. No reejecutar callback al resolver un commit desconocido.
- Inicialización atómica $setOnInsert fuera de la transacción: no reinicia revisiones;
  no crea mesas, reservas ni turnos por GET. Se comprueba restaurante existente.
- Datos legacy inciertos bloquean operaciones; renombrado LABEL_ONLY no consulta
  compromisos. Conjuntos consultan solo miembros del restaurante y protegen sus mesas.
- Planner se llama antes de la transacción; validación local y escritura de reservas
  se repiten dentro de la frontera común. No cambian DTO ni rutas antiguas.

Las firmas concretas de tests están en [pruebas comunes](disponibilidad-pruebas-comunes.md).
El test de JWT valida claims; el decoder productivo verifica firma con JWK externo.
No hay un emisor de tokens o un endpoint de login en este lote.

## Corrección de tres fallos de integración

El usuario ejecutó integración: 20 casos y 3 fallos. Se corrigieron las causas,
sin considerar todavía aprobada la suite corregida:

- La inyección recuperable y la persistente de commit usan errorCode=1 con la etiqueta
  UnknownTransactionCommitResult. El código 91 indicaba recuperación del nodo y hacía
  que la selección del driver consumiera el presupuesto; esa situación no se utiliza
  para representar un simple error de commit. Los failpoints se limpian en finally.
- write recibe Class<T> responseType, determinado por el servidor. El cuerpo del recibo
  se reconstruye mediante el convertidor de Mongo (Document se recupera como Document),
  sin cast genérico de un Map. Se mantienen igualdad de resultado, código, Location,
  revisión y ETag derivado de ella. No cambia el esquema almacenado ni el contrato HTTP.
- La carrera entre configuración y writer antiguo materializa ambas terminaciones para
  evitar cancelaciones mutuas. Si los tres intentos internos se agotan, exige error
  transitorio, revisión sin incremento parcial y ninguna reserva guardada. Después
  de terminar la competidora se permite un nuevo intento explícito del cliente.
  Si ambos triunfan directamente, también se exige una sola reserva y revisión dos.

Se añadió una regresión de replay con DTO record y tipo explícito. Los 5 segundos,
tres intentos y backoff 50/100 ms permanecen iguales. Compilación comprobada;
el agente no ejecutó suites ni inició Docker. El usuario debe repetir integrationTest
y las unitarias seleccionadas antes del commit. La fase 3 continúa sin iniciar.

Referencia de implementación: el [transaction manager reactivo de Spring Data](https://docs.spring.io/spring-data/mongodb/reference/mongodb/client-session-transactions.html)
vincula sesión al contexto Reactor y permite resolver commit sobre esa misma sesión.
