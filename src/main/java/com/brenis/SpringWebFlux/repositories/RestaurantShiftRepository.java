package com.brenis.SpringWebFlux.repositories;
import java.util.UUID;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import reactor.core.publisher.*;
import com.brenis.SpringWebFlux.collections.RestaurantShiftCollection;
public interface RestaurantShiftRepository extends ReactiveMongoRepository<RestaurantShiftCollection,UUID> {
    Flux<RestaurantShiftCollection> findAllByRestaurantId(UUID restaurantId);
    Mono<RestaurantShiftCollection> findByIdAndRestaurantId(UUID id,UUID restaurantId);
}
