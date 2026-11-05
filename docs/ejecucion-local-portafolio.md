# Configuración y ejecución local

## Requisitos

- JDK 21 y `JAVA_HOME` apuntando a su instalación.
- Docker y Docker Compose.
- Puertos locales 27017, 6379 y 8080 disponibles.

El proyecto incluye Gradle Wrapper. La primera ejecución puede descargar Gradle
y las dependencias necesarias. Los comandos siguientes se ejecutan desde la raíz
del proyecto en PowerShell.

## Configuración

En una copia nueva del repositorio, crea el archivo de configuración local:

```powershell
Copy-Item .env.example .env
notepad .env
```

Si `.env` ya existe, consérvalo. Cambia los valores de ejemplo por contraseñas
locales distintas y no reutilizadas. Usa el formato `CLAVE=valor` sin comillas;
para este entorno compartido por Spring y Compose se recomiendan valores
alfanuméricos. Mantén `AVAILABILITY_ENABLED=false` y `RESERVATIONS_ENABLED=false`
para el recorrido básico del catálogo. No compartas ni subas `.env` a Git.

## Iniciar el catálogo

```powershell
java --version
docker compose --env-file .env -f src/main/resources/docker-compose.yml config --quiet
docker compose --env-file .env -f src/main/resources/docker-compose.yml up -d mongodb redis
.\gradlew.bat bootRun
```

Espera a que MongoDB y Redis estén disponibles antes de iniciar el backend. Compose
define servicios adicionales, pero los comandos anteriores solo inician las dos
dependencias del catálogo. Mantén abierta la terminal del backend y, en otra,
consulta los restaurantes:

```powershell
Invoke-RestMethod 'http://localhost:8080/catalog/restaurants?page=0&size=5'
```

El inicializador de Mongo incluye datos de ejemplo. Si ya existe una base local,
sus datos pueden ser diferentes. Mongo inicializa credenciales y datos al crear
almacenamiento nuevo; editar `.env` no cambia la contraseña de una base existente.
No es necesario borrar datos para ejecutar este recorrido.

Para la configuración de mesas y turnos se requiere además un replica set y un
emisor JWT. Consulta [identidad local](identidad-local.md). El gate de reservas
v2 está desactivado por defecto y su activación requiere preparación adicional.

## Pruebas

```powershell
.\gradlew.bat test
.\gradlew.bat integrationTest
```

Las pruebas de integración utilizan Testcontainers y necesitan Docker. Los informes
se generan bajo `build/reports/tests/`. Consulta el [estado de validación](estado-portafolio.md)
para distinguir los resultados registrados de los pendientes.
