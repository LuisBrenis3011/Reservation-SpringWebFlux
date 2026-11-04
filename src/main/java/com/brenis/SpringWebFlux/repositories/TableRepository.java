package com.brenis.SpringWebFlux.repositories;

import com.brenis.SpringWebFlux.collections.TableCollection;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import reactor.core.publisher.*;
import java.util.UUID;

public interface TableRepository extends ReactiveMongoRepository<TableCollection,UUID> {
    Flux<TableCollection> findAllByRestaurantId(UUID restaurantId);
    Mono<TableCollection> findByIdAndRestaurantId(UUID id,UUID restaurantId);
    Mono<Boolean> existsByRestaurantIdAndLabelKey(UUID restaurantId,String labelKey);
}

