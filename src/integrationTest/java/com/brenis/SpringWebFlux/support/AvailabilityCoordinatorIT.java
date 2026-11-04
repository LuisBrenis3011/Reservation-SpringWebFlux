package com.brenis.SpringWebFlux.support;

import com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.collections.RestaurantCollection;
import com.mongodb.MongoException;
import org.bson.Document;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;
import reactor.core.publisher.*;
import reactor.test.StepVerifier;
import java.time.Duration;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.data.mongodb.core.query.Criteria.where;
import static org.springframework.data.mongodb.core.query.Query.query;

@SpringJUnitConfig(AvailabilityIntegrationConfiguration.class)
class AvailabilityCoordinatorIT {
    @Autowired RestaurantOperationCoordinator coordinator;
    @Autowired ReactiveMongoTemplate mongo;
    @Autowired com.brenis.SpringWebFlux.configs.AvailabilityInfrastructureInitializer initializer;
    UUID restaurant;

    @BeforeEach void prepare() {
        restaurant=UUID.randomUUID();
        mongo.save(RestaurantCollection.builder().id(restaurant).name("Test").closeAt("23:59").build()).block();
        admin(new Document("configureFailPoint","failCommand").append("mode","off")).block();
        if (!Boolean.TRUE.equals(mongo.collectionExists("availability_probe").block()))
            mongo.createCollection("availability_probe").block();
    }
    Mono<Document> admin(Document command) {
        return mongo.getMongoDatabaseFactory().getMongoDatabase("admin")
                .flatMap(db -> Mono.from(db.runCommand(command)));
    }
    CommandMetadata command(String key, Long revision) {
        return new CommandMetadata(key,"POST:/probe:body:"+key,revision,201,"/catalog/probe/"+key);
    }
    Mono<RestaurantOperationCoordinator.Result<Document>> write(String key) {
        return coordinator.write(restaurant,Document.class,command(key,null),ctx ->
                mongo.insert(new Document("_id",key).append("restaurantId",restaurant),"availability_probe"));
    }
    long revision() {
        Document doc=mongo.findById(restaurant,Document.class,"restaurant_operations").block();
        return ((Number)doc.get("revision")).longValue();
    }
    @Test void inicializarRestaurantePosteriorEsIdempotenteYNoReiniciaRevision() {
        initializer.ensureInitialized(restaurant).block(); assertThat(revision()).isZero();
        write(UUID.randomUUID().toString()).block(); long previous=revision();
        Flux.merge(initializer.ensureInitialized(restaurant),initializer.ensureInitialized(restaurant))
                .then().block(Duration.ofSeconds(10));
        assertThat(revision()).isEqualTo(previous);
    }
    @Test void restauranteInexistenteNoObtieneMetadatos() {
        UUID missing=UUID.randomUUID();
        StepVerifier.create(initializer.ensureInitialized(missing))
                .expectErrorMatches(e -> e.getMessage().contains("NOT_FOUND")).verify();
        assertThat(mongo.findById(missing,Document.class,"restaurant_operations").block()).isNull();
    }
    @Test void falloDePreparacionNoEjecutaCallback() {
        admin(new Document("configureFailPoint","failCommand").append("mode",new Document("times",1))
                .append("data",new Document("failCommands",java.util.List.of("update")).append("errorCode",2))).block();
        AtomicInteger calls=new AtomicInteger();
        try {
            StepVerifier.create(coordinator.write(restaurant,Document.class,command(UUID.randomUUID().toString(),null),ctx -> {
                calls.incrementAndGet(); return Mono.just(new Document());
            })).expectErrorMatches(e -> e.getMessage().contains("DEPENDENCY_UNAVAILABLE")).verify();
            assertThat(calls).hasValue(0);
        } finally { admin(new Document("configureFailPoint","failCommand").append("mode","off")).block(); }
    }
    @Test void replayNoIncrementaRevisionInclusoTrasOtroComando() {
        String key=UUID.randomUUID().toString();
        var original=write(key).block();
        write(UUID.randomUUID().toString()).block();
        long before=revision();
        var replay=write(key).block();
        assertThat(revision()).isEqualTo(before);
        assertThat(replay).isEqualTo(original);
        assertThat(mongo.count(query(where("_id").is(key)),"availability_probe").block()).isEqualTo(1L);
    }
    record TypedReply(String label,int capacity) {}
    @Test void replayReconstruyeDtoConTipoExplicitoYConservaMetadata() {
        String key=UUID.randomUUID().toString();
        var metadata=command(key,null);
        var original=coordinator.write(restaurant,TypedReply.class,metadata,
                ctx -> Mono.just(new TypedReply("Mesa de prueba",4))).block();
        write(UUID.randomUUID().toString()).block();
        long before=revision();
        var replay=coordinator.write(restaurant,TypedReply.class,metadata,
                ctx -> Mono.<TypedReply>error(new AssertionError("Replay no debe ejecutar callback"))).block();
        assertThat(replay.body()).isExactlyInstanceOf(TypedReply.class);
        assertThat(replay).isEqualTo(original);
        assertThat(replay.httpStatus()).isEqualTo(201);
        assertThat(replay.location()).isEqualTo(metadata.location());
        assertThat(revision()).isEqualTo(before);
    }
    @Test void mismaClaveConFingerprintDistintoSeRechaza() {
        String key=UUID.randomUUID().toString();
        write(key).block(); long before=revision();
        StepVerifier.create(coordinator.write(restaurant,Document.class,
                new CommandMetadata(key,"different",null,201,"/catalog/probe"),
                ctx -> Mono.just(new Document())))
                .expectErrorMatches(e -> e.getMessage().contains("IDEMPOTENCY_CONFLICT")).verify();
        assertThat(revision()).isEqualTo(before);
    }
    @Test void revisionObsoletaNoCambiaDatos() {
        write(UUID.randomUUID().toString()).block(); long before=revision();
        StepVerifier.create(coordinator.write(restaurant,Document.class,command(UUID.randomUUID().toString(),0L),
                ctx -> mongo.insert(new Document("_id","must-not-exist"),"availability_probe")))
                .expectErrorMatches(e -> e.getMessage().contains("REVISION_MISMATCH")).verify();
        assertThat(revision()).isEqualTo(before);
        assertThat(mongo.findById("must-not-exist",Document.class,"availability_probe").block()).isNull();
    }
    @Test void errorDespuesDeEscrituraRevierteDocumentoYRevision() {
        write(UUID.randomUUID().toString()).block(); long before=revision();
        String id=UUID.randomUUID().toString();
        StepVerifier.create(coordinator.write(restaurant,Document.class,command(id,null),ctx ->
                mongo.insert(new Document("_id",id),"availability_probe")
                        .then(Mono.<Document>error(new IllegalArgumentException("reject")))))
                .expectError().verify();
        assertThat(revision()).isEqualTo(before);
        assertThat(mongo.findById(id,Document.class,"availability_probe").block()).isNull();
    }
    @Test void lecturasSnapshotNoIncrementanRevision() {
        write(UUID.randomUUID().toString()).block(); long before=revision();
        var view=coordinator.readSnapshot(restaurant,ctx ->
                mongo.find(query(where("restaurantId").is(restaurant)),Document.class,"availability_probe")
                        .collectList()).block();
        assertThat(view.revision()).isEqualTo(before);
        assertThat(view.body()).hasSize(1);
        assertThat(revision()).isEqualTo(before);
    }
    @Test void replaysConcurrentesEjecutanCallbackUnaSolaVez() {
        String key=UUID.randomUUID().toString();
        AtomicInteger accepted=new AtomicInteger();
        var operation=Mono.defer(() -> coordinator.write(restaurant,Document.class,command(key,null),ctx ->
                mongo.insert(new Document("_id",key),"availability_probe")
                        .doOnSuccess(value -> accepted.incrementAndGet())));
        // delay suscripción no garantiza carrera; Flux.merge sí mantiene ambas activas.
        var results=Flux.merge(operation,operation).collectList().block(Duration.ofSeconds(15));
        assertThat(results).hasSize(2);
        assertThat(results.get(0).body()).isExactlyInstanceOf(Document.class);
        assertThat(results.get(1).body()).isExactlyInstanceOf(Document.class);
        assertThat(results.get(0)).isEqualTo(results.get(1));
        assertThat(revision()).isEqualTo(1L);
        assertThat(mongo.count(query(where("_id").is(key)),"availability_probe").block()).isEqualTo(1L);
    }
    @Test void snapshotNoMezclaValoresDeUnWriteConcurrente() {
        String key=UUID.randomUUID().toString(); write(key).block();
        Sinks.One<Void> reading=Sinks.one(), changed=Sinks.one();
        var read=coordinator.readSnapshot(restaurant,ctx ->
                mongo.findById(key,Document.class,"availability_probe").flatMap(first -> {
                    reading.tryEmitEmpty();
                    return changed.asMono().then(mongo.findById(key,Document.class,"availability_probe"))
                            .map(second -> first.equals(second));
                }));
        var write=reading.asMono().then(coordinator.write(restaurant,Document.class,
                command(UUID.randomUUID().toString(),null),ctx ->
                        mongo.updateFirst(query(where("_id").is(key)),
                                new org.springframework.data.mongodb.core.query.Update().set("changed",true),
                                "availability_probe").thenReturn(new Document("ok",true))))
                .doOnSuccess(value -> changed.tryEmitEmpty());
        var results=Mono.zip(read,write).block(Duration.ofSeconds(15));
        assertThat(results.getT1().body()).isTrue();
        assertThat(mongo.findById(key,Document.class,"availability_probe").block().getBoolean("changed")).isTrue();
    }
    @Test void reintentoTransitorioSeLimitaATresIntentos() {
        AtomicInteger attempts=new AtomicInteger();
        StepVerifier.create(coordinator.write(restaurant,Document.class,command(UUID.randomUUID().toString(),null),ctx ->
                Mono.defer(() -> {
                    attempts.incrementAndGet();
                    MongoException e=new MongoException(112,"WriteConflict");
                    e.addLabel("TransientTransactionError");
                    return Mono.error(e);
                }))).expectError().verify(Duration.ofSeconds(10));
        assertThat(attempts).hasValue(3);
        assertThat(revision()).isZero();
    }
    @Test void presupuestoTotalLimitaOperacionQueNoTermina() {
        write(UUID.randomUUID().toString()).block(); long before=revision();
        StepVerifier.create(coordinator.write(restaurant,Document.class,command(UUID.randomUUID().toString(),null),
                ctx -> Mono.<Document>never())).expectError().verify(Duration.ofSeconds(8));
        assertThat(revision()).isEqualTo(before);
    }
    @Test void commitInciertoSeResuelveSinRepetirCallback() {
        admin(new Document("configureFailPoint","failCommand")
                .append("mode",new Document("times",1))
                .append("data",new Document("failCommands",java.util.List.of("commitTransaction"))
                        .append("errorCode",1).append("errorLabels",java.util.List.of("UnknownTransactionCommitResult")))).block();
        AtomicInteger calls=new AtomicInteger();
        try {
            var result=coordinator.write(restaurant,Document.class,command(UUID.randomUUID().toString(),null),ctx -> {
                calls.incrementAndGet(); return Mono.just(new Document("ok",true));
            }).block(Duration.ofSeconds(15));
            assertThat(result.body().getBoolean("ok")).isTrue();
            assertThat(calls).hasValue(1);
            assertThat(revision()).isEqualTo(1L);
        } finally {
            admin(new Document("configureFailPoint","failCommand").append("mode","off")).block();
        }
    }
    @Test void resultadoDesconocidoNoPrometeRollbackYSeResuelveConMismaClave() {
        admin(new Document("configureFailPoint","failCommand").append("mode","alwaysOn")
                .append("data",new Document("failCommands",java.util.List.of("commitTransaction"))
                        .append("errorCode",1).append("errorLabels",java.util.List.of("UnknownTransactionCommitResult")))).block();
        String key=UUID.randomUUID().toString();
        try {
            StepVerifier.create(write(key)).expectErrorMatches(e ->
                    e.getMessage().contains("OPERATION_OUTCOME_UNKNOWN")).verify(Duration.ofSeconds(15));
        } finally {
            admin(new Document("configureFailPoint","failCommand").append("mode","off")).block();
        }
        // No afirmar ausencia de cambios antes de resolver el recibo.
        var resolved=write(key).block(Duration.ofSeconds(15));
        assertThat(resolved.body().getString("_id")).isEqualTo(key);
        assertThat(mongo.count(query(where("_id").is(key)),"availability_probe").block()).isEqualTo(1L);
    }
}

