package com.brenis.SpringWebFlux.configs;

import org.springframework.stereotype.Component;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.index.Index;
import reactor.core.publisher.Mono;

@Component
public class TableCombinationIndexesContributor implements AvailabilityInfrastructureInitializer.IndexContributor {
    private final ReactiveMongoTemplate mongo;
    public TableCombinationIndexesContributor(ReactiveMongoTemplate mongo) { this.mongo=mongo; }
    @Override public Mono<Void> prepare() {
        return mongo.collectionExists("table_combinations")
                .flatMap(exists -> exists?Mono.empty():mongo.createCollection("table_combinations").then())
                .then(mongo.indexOps("table_combinations").createIndex(new Index()
                        .on("restaurantId",Sort.Direction.ASC).on("memberKey",Sort.Direction.ASC)
                        .unique().named("restaurant_combination_members_unique")).then());
    }
}
