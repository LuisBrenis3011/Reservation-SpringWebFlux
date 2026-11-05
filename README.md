# Eats Hub

API reactiva para consultar restaurantes y gestionar su disponibilidad y reservas.
Construida con Java 21, Spring Boot y WebFlux, utiliza MongoDB como fuente de datos
y Redis para caché.

## Qué resuelve

Un restaurante necesita organizar mesas, combinaciones, turnos y zona horaria antes
de aceptar reservas. Eats Hub modela esa oferta y gestiona el ciclo de vida de una
reserva, con controles para proteger la información y manejar reintentos.

## Funcionalidades

- Consulta de restaurantes por nombre, cocina, precio y ciudad.
- Gestión de mesas, combinaciones, turnos y zona horaria.
- Consulta de disponibilidad y operaciones de confirmación, consulta, modificación
  y cancelación de reservas v2.
- Identidad y permisos mediante JWT; control de versiones con ETag e If-Match.
- Claves de idempotencia y recibos persistidos para reconocer reintentos.

## Arquitectura y tecnologías

Las rutas funcionales de WebFlux reciben las peticiones; los handlers las traducen
a operaciones de servicio. Los servicios aplican las reglas de negocio y coordinan
la persistencia reactiva en MongoDB. Redis se utiliza para caché del catálogo.

Java 21 · Spring Boot 4.0.1 · WebFlux · Reactor · MongoDB · Redis · Spring Security
OAuth2/JWT · Gradle · JUnit · Testcontainers · MapStruct · Lombok.

## Ejecutar y consultar la API

- [Configuración local](docs/ejecucion-local-portafolio.md)
- [Rutas y ejemplos de la API](docs/demo-portafolio.md)
- [Estado y validación](docs/estado-portafolio.md)

El catálogo puede ejecutarse con MongoDB y Redis locales. Las operaciones protegidas
de disponibilidad y reservas requieren identidad y configuración adicionales.
No hay una API pública desplegada.

## Estado del proyecto

La gestión de mesas, combinaciones y turnos fue validada y aprobada localmente.
En una revisión de desarrollo posterior a esta instantánea pública se ejecutó un
recorrido local con datos ficticios: disponibilidad, confirmación, replay, consulta,
privacidad, modificación, cancelación y consulta tras reinicio. La gestión de
reservas sigue en desarrollo: ese recorrido no acredita todas las pruebas de
concurrencia ni la transición operativa de los datos anteriores.

El gate de reservas permanece desactivado por defecto. El planificador utilizado
por el contrato antiguo simula disponibilidad. Consulta el estado detallado antes
de ejecutar operaciones sobre datos existentes.

## Desarrollo

Proyecto personal de aprendizaje iniciado a partir de una base de curso. Mi trabajo
se centra en ampliar el dominio de disponibilidad y reservas, sus reglas de negocio,
seguridad, pruebas y documentación técnica.
