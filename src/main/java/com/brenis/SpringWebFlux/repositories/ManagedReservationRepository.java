package com.brenis.SpringWebFlux.repositories;

import java.util.UUID;
import org.springframework.stereotype.Repository;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.*;
import reactor.core.publisher.*;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection;
import com.brenis.SpringWebFlux.enums.ManagedReservationStatus;
import static org.springframework.data.mongodb.core.query.Criteria.where;

@Repository
public class ManagedReservationRepository {
    private final ReactiveMongoTemplate mongo;
    public ManagedReservationRepository(ReactiveMongoTemplate mongo){this.mongo=mongo;}
    public Mono<ManagedReservationCollection> find(UUID restaurant,UUID id){
        return mongo.findOne(Query.query(where("schemaVersion").is(2).and("restaurantId").is(restaurant).and("_id").is(id)),ManagedReservationCollection.class);
    }
    public Flux<ManagedReservationCollection> mine(String issuer,String subject){
        return mongo.find(Query.query(where("schemaVersion").is(2).and("customerIssuer").is(issuer).and("customerSubject").is(subject)),ManagedReservationCollection.class);
    }
    public Mono<ManagedReservationCollection> insert(ManagedReservationCollection value){return mongo.insert(value);}
    public Mono<Boolean> replace(ManagedReservationCollection value,long expectedVersion){
        var q=Query.query(where("schemaVersion").is(2).and("_id").is(value.id()).and("restaurantId").is(value.restaurantId())
                .and("customerIssuer").is(value.customerIssuer()).and("customerSubject").is(value.customerSubject())
                .and("version").is(expectedVersion).and("status").is(ManagedReservationStatus.CONFIRMED));
        return mongo.findAndReplace(q,value).map(saved->true).defaultIfEmpty(false);
    }
}
