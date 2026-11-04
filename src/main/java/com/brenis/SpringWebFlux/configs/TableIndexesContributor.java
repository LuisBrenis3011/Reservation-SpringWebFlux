package com.brenis.SpringWebFlux.configs;

import org.springframework.stereotype.Component;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.index.Index;
import reactor.core.publisher.Mono;

@Component
public class TableIndexesContributor implements AvailabilityInfrastructureInitializer.IndexContributor {
    private final ReactiveMongoTemplate mongo;
    public TableIndexesContributor(ReactiveMongoTemplate mongo) { this.mongo=mongo; }
    @Override public Mono<Void> prepare() {
        return mongo.collectionExists("restaurant_tables")
                .flatMap(exists -> exists?Mono.empty():mongo.createCollection("restaurant_tables").then())
                .then(mongo.indexOps("restaurant_tables").createIndex(new Index()
                        .on("restaurantId",Sort.Direction.ASC).on("labelKey",Sort.Direction.ASC)
                        .unique().named("restaurant_table_label_unique")).then());
    }
}

