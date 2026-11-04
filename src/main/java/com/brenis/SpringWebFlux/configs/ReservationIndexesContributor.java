package com.brenis.SpringWebFlux.configs;
import org.springframework.stereotype.Component;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.index.*;
import org.bson.Document;
import reactor.core.publisher.Mono;

@Component
public class ReservationIndexesContributor implements AvailabilityInfrastructureInitializer.IndexContributor {
    private final ReactiveMongoTemplate mongo;
    public ReservationIndexesContributor(ReactiveMongoTemplate mongo){this.mongo=mongo;}
    @Override public Mono<Void> prepare(){
        var active=PartialIndexFilter.of(new Document("schemaVersion",2).append("status","CONFIRMED"));
        return mongo.collectionExists("reservations").flatMap(exists->exists?Mono.empty():mongo.createCollection("reservations").then())
            .then(mongo.indexOps("reservations").createIndex(new Index().on("restaurantId",Sort.Direction.ASC).on("shiftId",Sort.Direction.ASC).on("tableIds",Sort.Direction.ASC).unique().partial(active).named("rsv_active_table_unique")))
            .then(mongo.indexOps("reservations").createIndex(new Index().on("restaurantId",Sort.Direction.ASC).on("shiftId",Sort.Direction.ASC).on("customerIssuer",Sort.Direction.ASC).on("customerSubject",Sort.Direction.ASC).unique().partial(active).named("rsv_active_customer_unique")))
            .then(mongo.indexOps("reservations").createIndex(new Index().on("schemaVersion",Sort.Direction.ASC).on("customerIssuer",Sort.Direction.ASC).on("customerSubject",Sort.Direction.ASC).on("_id",Sort.Direction.ASC).named("rsv_customer_list")))
            .then(mongo.indexOps("reservations").createIndex(new Index().on("restaurantId",Sort.Direction.ASC).on("_id",Sort.Direction.ASC).named("rsv_restaurant_list"))).then();
    }
}
