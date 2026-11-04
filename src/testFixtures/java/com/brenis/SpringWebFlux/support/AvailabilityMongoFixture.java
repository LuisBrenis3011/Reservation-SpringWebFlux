package com.brenis.SpringWebFlux.support;

import org.bson.BsonBinary;
import org.bson.Document;
import org.bson.UuidRepresentation;
import org.bson.types.Binary;
import org.testcontainers.mongodb.MongoDBContainer;
import org.testcontainers.utility.DockerImageName;

import java.time.Instant;
import java.util.Date;
import java.util.List;
import java.util.UUID;

/** Mongo aislado por instancia; crear la fixture no inicia Docker. Cerrar al terminar. */
public final class AvailabilityMongoFixture implements AutoCloseable {
    private final MongoDBContainer container;
    private final boolean replicaSet;
    private final String database = "availability_" + UUID.randomUUID().toString().replace("-", "");

    public AvailabilityMongoFixture() { this(true); }

    /** false permite comprobar el rechazo de standalone en un contenedor efímero. */
    public AvailabilityMongoFixture(boolean replicaSet) {
        this.replicaSet = replicaSet;
        container = new MongoDBContainer(DockerImageName.parse("mongo:8.0.8"));
        if (replicaSet) container.withReplicaSet();
    }

    /** Fallos de comandos solo en el Mongo efímero de integración, nunca en datos locales. */
    public AvailabilityMongoFixture enableCommandFailpoints() {
        if (container.isRunning()) throw new IllegalStateException("Configurar antes de start()");
        container.withCommand("--replSet", "docker-rs", "--setParameter", "enableTestCommands=1");
        return this;
    }

    public AvailabilityMongoFixture start() {
        container.start();
        return this;
    }

    public String database() { return database; }
    public String replicaSetUri() {
        return container.getReplicaSetUrl(database) + (replicaSet
                ? "?replicaSet=docker-rs&directConnection=true" : "?directConnection=true");
    }
    @Override public void close() { container.stop(); }

    /** Reserva sin asignación: la hora aislada no demuestra su finalización. */
    public static Document unresolvedLegacy(UUID restaurantId, boolean binaryRestaurantId, String status) {
        Object owner = binaryRestaurantId ? standardUuid(restaurantId) : restaurantId.toString();
        return new Document("_id", UUID.randomUUID().toString())
                .append("restaurantId", owner).append("status", status)
                .append("date", "2026-11-01").append("time", "12:00");
    }

    /** BSON de prueba, no adaptación de registros de la aplicación. */
    public static Document confirmedSnapshot(UUID restaurantId, UUID shiftId, UUID tableId,
                                             Instant start, Instant end) {
        return new Document("_id", standardUuid(UUID.randomUUID()))
                .append("restaurantId", standardUuid(restaurantId))
                .append("status", "CONFIRMED")
                .append("shiftId", standardUuid(shiftId))
                .append("tableIds", List.of(standardUuid(tableId)))
                .append("startInstant", Date.from(start)).append("endInstant", Date.from(end))
                .append("zoneId", "UTC")
                .append("localStart", java.time.format.DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ss")
                        .format(start.atOffset(java.time.ZoneOffset.UTC)))
                .append("localEnd", java.time.format.DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ss")
                        .format(end.atOffset(java.time.ZoneOffset.UTC)))
                .append("tableSnapshots", List.of(new Document("tableId", standardUuid(tableId))
                        .append("label", "Mesa de prueba").append("capacity", 4L)));
    }

    private static Binary standardUuid(UUID id) {
        BsonBinary value = new BsonBinary(id, UuidRepresentation.STANDARD);
        return new Binary(value.getType(), value.getData());
    }
}
