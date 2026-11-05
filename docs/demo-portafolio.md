# API de Eats Hub

El servicio expone rutas bajo `/catalog`. Para iniciar las dependencias y el backend,
consulta la [configuración local](ejecucion-local-portafolio.md).

## Restaurantes

| Operación | Ruta |
|---|---|
| Listar | `GET /catalog/restaurants?page=0&size=5` |
| Buscar por nombre | `GET /catalog/restaurants/{nombre}` |
| Filtrar por cocina | `GET /catalog/restaurants?cousinType=Italian` |
| Filtrar por precio | `GET /catalog/restaurants?prices=CHEAP,MEDIUM` |
| Filtrar por ciudad | `GET /catalog/restaurants?city=New%20York` |

Ejemplo para PowerShell:

```powershell
Invoke-RestMethod 'http://localhost:8080/catalog/restaurants?page=0&size=5'
```

El parámetro se llama `cousinType` en el contrato actual. Cuando se combinan filtros,
el router prioriza cocina, precio y ciudad en ese orden.

## Disponibilidad y reservas

| Operación | Ruta |
|---|---|
| Consultar disponibilidad | `GET /catalog/restaurants/{restaurantId}/availability` |
| Confirmar | `POST /catalog/restaurants/{restaurantId}/reservations` |
| Mis reservas | `GET /catalog/me/reservations` |
| Consultar detalle | `GET /catalog/restaurants/{restaurantId}/reservations/{reservationId}` |
| Modificar | `PUT /catalog/restaurants/{restaurantId}/reservations/{reservationId}` |
| Cancelar | `POST /catalog/restaurants/{restaurantId}/reservations/{reservationId}/cancellation` |

Las operaciones protegidas requieren JWT y el entorno de reservas configurado.
Los comandos utilizan `Idempotency-Key`; la modificación y cancelación requieren
`If-Match` con el ETag vigente. El gate de reservas está apagado por defecto.
La activación sobre datos existentes tiene requisitos adicionales descritos en la
[documentación de estado](estado-portafolio.md).
