# Ejecutar la demo básica

Requisitos: JDK 21, Docker con Compose y puertos locales 27017, 6379 y 8080 libres.
El wrapper proporciona Gradle; la primera ejecución puede descargar dependencias.
Ejecutar desde la raíz del servicio en PowerShell. No se ejecutaron estos pasos
durante la preparación de la presentación.

## Configuración

Conservar `.env` si ya existe. En una copia nueva:

```powershell
Copy-Item .env.example .env
notepad .env
```

Reemplazar todos los valores `replace-with-...` por contraseñas locales distintas
y no reutilizadas. No subir `.env` ni pegarlo en incidencias. Usar `CLAVE=valor`
sin comillas; para este lector compartido utilizar contraseñas alfanuméricas.
Mantener `AVAILABILITY_ENABLED=false` y `RESERVATIONS_ENABLED=false`.
No utilizar las credenciales históricas del proyecto.

Comprobar `JAVA_HOME` con JDK 21. Estos comandos son instrucciones, no resultados:

```powershell
java --version
docker compose --env-file .env -f src/main/resources/docker-compose.yml config --quiet
docker compose --env-file .env -f src/main/resources/docker-compose.yml up -d mongodb redis
.\gradlew.bat bootRun
```

Compose define otros servicios, pero estos comandos solo inician MongoDB y Redis.
El inicializador Mongo incorpora los datos de ejemplo existentes. Esperar las
dependencias antes de iniciar Spring. En IntelliJ utilizar JDK 21 y la raíz del
servicio como directorio de trabajo. Desde otra terminal:

```powershell
Invoke-RestMethod 'http://localhost:8080/catalog/restaurants?page=0&size=5'
```

No se adjunta una respuesta inventada: depende de los datos locales.

## Conservación de datos

- No ejecutar `down -v` ni borrar bases o contenedores para resolver errores.
- Mongo inicializa credenciales y datos sobre almacenamiento nuevo. Editar `.env`
  no actualiza la contraseña de una base existente.
- Si un puerto está ocupado, adaptar las variables de Compose y Spring. Para
  el backend puede usarse `SERVER_PORT`; adaptar también las URLs de ejemplo.
- Mesas y turnos requieren configuración adicional: seguir
  [identidad local](identidad-local.md) y las guías enlazadas antes de activar gates.
- El ensayo del puente necesita Gradle local compatible además del wrapper;
  ese requisito no corresponde a la demo básica.

## Pruebas disponibles

```powershell
.\gradlew.bat test
.\gradlew.bat integrationTest
```

La integración utiliza Testcontainers y requiere Docker. Revisar los requisitos
de cada suite; no se afirma que la suite completa del árbol actual haya pasado.
Los informes se generan en `build/reports/tests/`, excluido de Git.
