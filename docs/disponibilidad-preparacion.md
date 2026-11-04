# Preparación de disponibilidad — T001–T004

La preparación inicial de T001–T004 está integrada con la fase 2. MongoConfig ya consume mongodb.uri y los writers antiguos requieren replica set. No hay endpoints funcionales nuevos todavía; mantener availability.enabled=false. Ver [estado actual y validación](disponibilidad-fase2.md).

## Validación por el usuario

Desde PowerShell en la raíz de SpringWebFlux:

```powershell
.\gradlew.bat compileJava compileTestFixturesJava compileTestJava compileIntegrationTestJava
.\gradlew.bat test
.\gradlew.bat integrationTest
```

El primer comando solo compila. integrationTest está separado de test y no está
enganchado a check para no iniciar Docker implícitamente. Todavía no hay pruebas
de integración: NO-SOURCE no demuestra cobertura. La tarea descubrirá tanto *IT
como *Tests bajo src/integrationTest/java. Los fixtures están disponibles en ambos
source sets; no crean contenedores al cargar clases. AvailabilityMongoFixture.start()
crea un replica set efímero; close() elimina únicamente ese contenedor de prueba.
mockJwt evita la decodificación real: los tests futuros de firma/issuer necesitarán
un decoder real o claves efímeras, no solo este mock.

## Mongo separado de desarrollo

El archivo src/main/resources/docker-compose.replica.yml utiliza proyecto distinto,
volumen persistente nuevo y puerto 27018 ligado a loopback. No sustituye el Compose
actual ni ejecuta restauraciones. Es un replica set de un miembro para Java en el
host Windows; localhost:27018 no sirve para una aplicación dentro de otro contenedor.

Preparar manualmente un keyfile con 756 bytes aleatorios codificados en base64,
sin BOM, dentro de secrets/mongo-keyfile. Por ejemplo, desde PowerShell:

```powershell
New-Item -ItemType Directory -Force secrets | Out-Null
if (Test-Path secrets/mongo-keyfile) { throw 'Ya existe: conservar el keyfile actual' }
$keyBytes = New-Object byte[] 756
$generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $generator.GetBytes($keyBytes) } finally { $generator.Dispose() }
$keyPath = Join-Path (Get-Location) 'secrets/mongo-keyfile'
[System.IO.File]::WriteAllText($keyPath, [Convert]::ToBase64String($keyBytes), [System.Text.UTF8Encoding]::new($false))
```

Definir MONGODB_REPLICA_KEYFILE con esa ruta absoluta en .env y conservar credenciales
locales. El contenedor copia el secreto y ajusta permisos sobre su copia interna.
Docker Compose lee .env; no ejecutar config sin --quiet porque puede mostrar secretos.

```powershell
docker compose --env-file .env -p eats-availability -f src/main/resources/docker-compose.replica.yml config --quiet
```

Solo cuando corresponda preparar el entorno nuevo:

```powershell
docker compose --env-file .env -p eats-availability -f src/main/resources/docker-compose.replica.yml up -d
docker compose --env-file .env -p eats-availability -f src/main/resources/docker-compose.replica.yml exec mongodb-replica mongosh --port 27018 --authenticationDatabase admin -u master -p
```

En el segundo comando, sustituir master si se cambió MONGODB_USERNAME; -p solicita
contraseña interactivamente. Dentro de mongosh, solo para el replica set nuevo vacío:

```javascript
rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'localhost:27018'}]})
rs.status()
```

No repetir rs.initiate si ya está inicializado. La comprobación ping de Compose no
acredita PRIMARY: verificar rs.status(). Esperar PRIMARY antes de restaurar datos.
Usar URI con replicaSet=rs0 y authSource=admin; codificar usuario/contraseña para URI.
El volumen inicializado conserva credenciales: cambiar .env no cambia sus usuarios.

## Conservación, transición y reversión

1. Inventariar origen y destino, conteos, tipos UUID/fechas y reservas no clasificables.
2. Hacer respaldo completo con mongodump y herramientas oficiales compatibles; guardar
   fuera de Git en backups/ o ubicación privada y probar una restauración aislada.
3. En la migración final, detener TODOS los writers antes del respaldo definitivo;
   restaurar en el destino nuevo y verificar conteos, UUID, fechas y datos antes de
   cambiar URI. No usar una copia de prueba desactualizada como copia final.
4. Desplegar juntos los writers coordinados con rutas nuevas desactivadas; verificar
   reservas antiguas y luego identidad/índices/guards antes de activar disponibilidad.
5. Mantener el standalone intacto. No ejecutar down -v, borrar contenedores o mezclar
   writers sin guard. Si el destino ya recibió nuevas escrituras, no volver simplemente
   a la copia antigua: detener writers y reconciliar preservando los datos nuevos.

Los comandos de respaldo/restauración dependen de credenciales, versiones y ubicación
reales; este bloque no los ejecuta ni inventa una conversión automática.

Referencias: [fixtures de Gradle](https://docs.gradle.org/current/userguide/java_test_fixtures_plugin.html)
y [MongoDB de Testcontainers](https://java.testcontainers.org/modules/databases/mongodb/).
