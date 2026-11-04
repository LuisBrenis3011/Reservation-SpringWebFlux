package com.brenis.SpringWebFlux.configs;
import org.springframework.stereotype.Component;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import reactor.core.publisher.Mono;
@Component
public class RestaurantShiftIndexesContributor implements AvailabilityInfrastructureInitializer.IndexContributor {
    private final ReactiveMongoTemplate mongo;
    public RestaurantShiftIndexesContributor(ReactiveMongoTemplate mongo){this.mongo=mongo;}
    private Mono<Void> collection(String name){return mongo.collectionExists(name).flatMap(exists -> exists?Mono.empty():mongo.createCollection(name).then());}
    @Override public Mono<Void> prepare(){return collection("restaurant_time_zones").then(collection("restaurant_shifts"))
        .then(mongo.indexOps("restaurant_shifts").createIndex(new org.springframework.data.mongodb.core.index.Index()
            .on("restaurantId",org.springframework.data.domain.Sort.Direction.ASC).on("startInstant",org.springframework.data.domain.Sort.Direction.ASC)
            .on("endInstant",org.springframework.data.domain.Sort.Direction.ASC).named("restaurant_shift_interval")).then());}
}
