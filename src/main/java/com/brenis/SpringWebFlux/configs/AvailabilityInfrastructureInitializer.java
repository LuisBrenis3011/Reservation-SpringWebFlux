package com.brenis.SpringWebFlux.configs;
import java.time.Duration;
import java.util.*;
import org.bson.Document;
import org.springframework.beans.factory.SmartInitializingSingleton;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Component;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.*;
import org.springframework.data.mongodb.core.index.Index;
import org.springframework.data.mongodb.core.query.*;
import org.springframework.dao.DuplicateKeyException;
import reactor.core.publisher.*;
import reactor.util.retry.Retry;
import com.brenis.SpringWebFlux.collections.RestaurantCollection;
import com.brenis.SpringWebFlux.repositories.LegacyReservationCommitmentAdapter;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
@Component
public class AvailabilityInfrastructureInitializer implements SmartInitializingSingleton {
    public interface IndexContributor { Mono<Void> prepare(); }
    private final ReactiveMongoTemplate mongo;
    private final AvailabilityProperties properties;
    private final ObjectProvider<IndexContributor> contributors;
    @org.springframework.beans.factory.annotation.Value("${reservations.enabled:false}")
    private boolean reservationsEnabled;
    public AvailabilityInfrastructureInitializer(ReactiveMongoTemplate mongo,AvailabilityProperties properties,
                                                 ObjectProvider<IndexContributor> contributors) {
        this.mongo=mongo; this.properties=properties; this.contributors=contributors;
    }
    @Override public void afterSingletonsInstantiated() {
        // Solo bootstrap, fuera de threads de atención WebFlux.
        prepare().block(Duration.ofSeconds(20));
    }
    private Mono<Void> collection(String name) {
        return mongo.collectionExists(name).flatMap(exists -> exists?Mono.empty():mongo.createCollection(name).then());
    }
    public Mono<Void> prepare() {
        if(properties.getMaxTransactionAttempts()!=3 || properties.getCommitmentCheckTimeout().isNegative()
                || properties.getTransactionTimeout().isNegative())
            return Mono.error(new IllegalStateException("Configuración de disponibilidad inválida"));
        if(properties.isEnabled() && (properties.getIssuerUri().isBlank() || properties.getJwkSetUri().isBlank()
                || properties.getAudience().isBlank()))
            return Mono.error(new IllegalStateException("issuer/JWK/audiencia requeridos"));
        return mongo.executeCommand(new Document("hello",1)).flatMap(hello -> {
            if(hello.get("setName")==null || hello.get("logicalSessionTimeoutMinutes")==null)
                return Mono.error(new IllegalStateException("Mongo replica set con sesiones requerido"));
            return Flux.just("restaurant_operations","operation_receipts").concatMap(this::collection).then()
                .then(mongo.indexOps("operation_receipts").createIndex(new Index()
                        .on("restaurantId",Sort.Direction.ASC).on("idempotencyKey",Sort.Direction.ASC).unique()).then())
                .thenMany(Flux.fromIterable(contributors.orderedStream().toList()).concatMap(IndexContributor::prepare)).then()
                .thenMany(mongo.find(new Query(),Document.class,"restaurants").concatMap(r -> {
                    UUID id=LegacyReservationCommitmentAdapter.uuid(r.get("_id"));
                    return id==null?Mono.<Void>error(new IllegalStateException("Restaurante con UUID inválido")):seed(id);
                })).then()
                .then(mongo.find(new Query(),Document.class,"reservations").any(r ->
                        LegacyReservationCommitmentAdapter.uuid(r.get("restaurantId"))==null))
                .flatMap(orphan -> new com.brenis.SpringWebFlux.services.impls.LegacyReservationWriteBarrier(mongo).retired().flatMap(retired -> {
                    if(reservationsEnabled && (!properties.isEnabled()||!retired))return Mono.error(new IllegalStateException("Reservas requieren disponibilidad y corte verificado"));
                    if(orphan && properties.isEnabled()&&!retired)return Mono.error(new IllegalStateException("Reservas huérfanas: activación bloqueada"));
                    return mongo.find(Query.query(Criteria.where("schemaVersion").is(2)),com.brenis.SpringWebFlux.collections.ManagedReservationCollection.class)
                        .doOnNext(new com.brenis.SpringWebFlux.validators.ReservationIntegrityValidator()::validate).then()
                        .then(mongo.find(new Query(),Document.class,"operation_receipts").any(receipt->{
                            Object key=receipt.get("idempotencyKey");
                            if(!(key instanceof String text)||!text.startsWith("rsv:"))return false;
                            Object body=receipt.get("responseBody");
                            return !text.matches("rsv:[a-f0-9]{64}")||!(body instanceof java.util.Map<?,?> map)||!"MANAGED".equals(map.get("kind"));
                        })).flatMap(collision->collision?Mono.error(new IllegalStateException("Colisión en namespace de recibos de reservas")):Mono.empty());
                }));
        });
    }
    private Mono<Void> seed(UUID id) {
        return mongo.upsert(Query.query(Criteria.where("_id").is(id)),
                new Update().setOnInsert("revision",0L).setOnInsert("schemaVersion",1),
                "restaurant_operations").then();
    }
    public Mono<Void> ensureInitialized(UUID id) {
        return mongo.exists(Query.query(Criteria.where("_id").is(id)),RestaurantCollection.class)
                .flatMap(exists -> exists?seed(id):Mono.error(new AvailabilityException("NOT_FOUND","Restaurante inexistente")))
                .retryWhen(Retry.max(2).filter(e -> e instanceof DuplicateKeyException))
                .onErrorMap(e -> e instanceof AvailabilityException?e:
                        new AvailabilityException("DEPENDENCY_UNAVAILABLE","No se pudo preparar restaurante",e));
    }
}

