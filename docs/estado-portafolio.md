# Estado y validación

Eats Hub es un proyecto en desarrollo. La gestión de mesas, combinaciones, turnos
y zona horaria tiene validación local y aprobación del responsable. El código de
reservas v2 incluye disponibilidad, confirmación, consultas, modificación y cancelación.

## Recorrido local de reservas

En una revisión de desarrollo posterior a esta instantánea pública, el responsable
ejecutó un recorrido HTTP sobre datos ficticios: consulta de disponibilidad,
confirmación, replay con la misma clave, consulta propia y rechazo a otro cliente,
modificación, rechazo de ETag obsoleto, cancelación y consulta tras reinicio.
La reserva cancelada y su ETag se conservaron tras el reinicio.

Los resultados pertenecen a esa revisión y no implican que la suite completa ni la
concurrencia hayan sido verificadas en esta instantánea. Los datos y checkpoints
privados de la ejecución no se incluyen en el repositorio.

## Pendiente

La gestión de reservas sigue en desarrollo y su gate está desactivado por defecto.
La transición desde el modelo anterior requiere validación operativa, revisión y
aprobación antes de aplicarse sobre datos existentes. No hay un servicio desplegado
públicamente ni se atribuyen métricas de rendimiento sin medición.
