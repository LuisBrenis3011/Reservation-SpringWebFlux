# API y guion de demostración

Preparar el [entorno básico](ejecucion-local-portafolio.md). Los ejemplos corresponden
al router actual; no se ejecutaron al preparar esta entrega.

| Consulta | Ruta |
|---|---|
| Listado | `GET /catalog/restaurants?page=0&size=5` |
| Nombre | `GET /catalog/restaurants/The%20Golden%20Spoon` |
| Cocina | `GET /catalog/restaurants?cousinType=Italian` |
| Precio | `GET /catalog/restaurants?prices=CHEAP,MEDIUM` |
| Ciudad | `GET /catalog/restaurants?city=New%20York` |

`cousinType` conserva el nombre implementado. No combinar filtros suponiendo una
búsqueda compuesta: el router prioriza cocina, precio y ciudad, en ese orden.
Los valores de ejemplo proceden de las fixtures; si los datos cambiaron, elegir
los nombres y ciudades que devuelva el listado local.

```powershell
Invoke-RestMethod 'http://localhost:8080/catalog/restaurants?page=0&size=5'
Invoke-RestMethod 'http://localhost:8080/catalog/restaurants?cousinType=Italian'
Invoke-RestMethod 'http://localhost:8080/catalog/restaurants?prices=CHEAP,MEDIUM'
Invoke-RestMethod 'http://localhost:8080/catalog/restaurants?city=New%20York'
```

## Cinco minutos

1. Explicar el problema y que el proyecto sigue en desarrollo (30 segundos).
2. Mostrar listado y dos filtros con sus respuestas reales (1 minuto).
3. Recorrer rutas, handlers, servicios y repositorios; mostrar Reactor y la caché
   sin afirmar métricas que no se hayan medido (1 minuto).
4. Explicar ETag e idempotencia apoyándose en clases y pruebas existentes, sin
   efectuar escrituras sobre datos personales (1 minuto).
5. Mostrar disponibilidad aprobada y reservas pendientes; explicar que aún no hay
   aislamiento real acreditado ni aprobación del corte (1 minuto).

Las APIs protegidas requieren JWT y preparación adicional. No se publican tokens
ni ejemplos con credenciales incrustadas. No se adjuntan capturas: las disponibles
son terminales de preparación y errores, no una demo funcional verificada.
