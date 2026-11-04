package com.brenis.SpringWebFlux.repositories;

import com.brenis.SpringWebFlux.collections.ReservationCollection;
import com.brenis.SpringWebFlux.enums.ReservationStatusEnum;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import reactor.core.publisher.Flux;

import java.util.UUID;

public interface ReservationRepository extends ReactiveMongoRepository<ReservationCollection, UUID> {

    Flux<ReservationCollection> findByRestaurantId(String restaurantId);

    Flux<ReservationCollection> findByRestaurantIdAndStatus(String restaurantId, ReservationStatusEnum status);

}
