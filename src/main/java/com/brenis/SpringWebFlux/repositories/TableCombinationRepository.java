package com.brenis.SpringWebFlux.repositories;

import com.brenis.SpringWebFlux.collections.TableCombinationCollection;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import reactor.core.publisher.*;
import java.util.UUID;

public interface TableCombinationRepository extends ReactiveMongoRepository<TableCombinationCollection,UUID> {
    Flux<TableCombinationCollection> findAllByRestaurantId(UUID restaurantId);
    Mono<TableCombinationCollection> findByIdAndRestaurantId(UUID id,UUID restaurantId);
    Mono<Boolean> existsByRestaurantIdAndMemberKey(UUID restaurantId,String memberKey);
    Mono<Boolean> existsByRestaurantIdAndMemberKeyAndIdNot(UUID restaurantId,String memberKey,UUID id);
}
