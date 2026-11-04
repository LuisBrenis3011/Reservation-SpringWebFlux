package com.brenis.SpringWebFlux.services.definitions;

import com.brenis.SpringWebFlux.collections.ReservationCollection;
import com.brenis.SpringWebFlux.enums.ReservationStatusEnum;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface ReservationCrudService {

    Mono<ReservationCollection> createReservation(ReservationCollection reservation);
    Flux<ReservationCollection> readByRestaurantId(UUID restaurantId, ReservationStatusEnum status);
    Mono<ReservationCollection> updateReservation(UUID id, ReservationCollection reservation);
    Mono<Void> deleteReservation(UUID id);
    Mono<ReservationCollection> readByReservationId(UUID id);
}
