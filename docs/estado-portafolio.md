# Estado y publicación del portafolio

## Validación comunicada

- SPEC-001/002/003 de preparación de disponibilidad cerradas y aprobadas por el
  responsable. Las guías de entrega conservan los resultados históricos.
- El usuario comunicó doce grupos sintéticos Passed y sintaxis JavaScript Passed
  para el puente. Hubo cambios posteriores de preflight e imágenes: no se hereda
  ese resultado a las modificaciones posteriores.
- Compilación real satisfactoria y candidato Prepared
  `20261104T183001Z-1fee331299b24ac5981c58fa9193eceb`.
- Último VerifyIsolated comunicado: tres grupos Failed y C1 Pending, fallo en
  SOURCE_EXPORTED antes del entorno Docker. La corrección posterior de rutas no
  tiene resultado comunicado.

No se ejecutaron pruebas, builds, servicios ni migraciones para esta presentación.
No se declara suite actual aprobada, aislamiento demostrado, Review real, corte,
reversión real ni aprobación de SPEC-005. T130 abierta; SPEC-004–008 en desarrollo.
No hay despliegue público verificado.

Las especificaciones SDD originales viven fuera del repositorio del servicio.
Esta entrega contiene un resumen autosuficiente, sin enlaces a archivos externos
presentados como si estuvieran publicados aquí.

## Publicación con historial nuevo

Esta copia se preparó para GitHub sin el historial privado de desarrollo. Se
excluyeron `.env`, secretos, respaldos, artefactos y directorios generados. La
revisión automática no encontró coincidencias con las credenciales históricas
detectadas ni patrones de claves privadas o tokens de GitHub/AWS conocidos.
Es una revisión acotada; no una certificación de ausencia universal de secretos.

El repositorio original y sus checkpoints se conservaron. Sus credenciales
históricas siguen requiriendo rotación en el entorno local: no se modificaron
servicios ni bases de datos durante esta publicación.

El destino de esta copia es `LuisBrenis3011/Reservation-SpringWebFlux`.
Los documentos operativos anteriores incluyen referencias a commits del historial
privado; esas referencias no son enlaces a commits de este historial público.
Las especificaciones externas y evidencias privadas no se incluyeron.

## Texto para portafolio

Eats Hub es mi proyecto backend con Java 21, Spring Boot y WebFlux para catálogo
de restaurantes, disponibilidad y reservas. Partiendo de una base de curso,
trabajé en persistencia reactiva con MongoDB y Redis, permisos JWT, concurrencia
e idempotencia. La preparación de disponibilidad está aprobada; las reservas
siguen en desarrollo, con validaciones y límites documentados. Utilizo
especificaciones y asistencia de IA como parte de mi aprendizaje.
