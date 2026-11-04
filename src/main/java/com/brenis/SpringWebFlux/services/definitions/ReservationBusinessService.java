package com.brenis.SpringWebFlux.services.definitions;

import com.brenis.SpringWebFlux.collections.ReservationCollection;
import com.brenis.SpringWebFlux.dtos.requests.ReservationRequest;
import com.brenis.SpringWebFlux.dtos.responses.ReservationResponse;
import com.brenis.SpringWebFlux.enums.ReservationStatusEnum;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface ReservationBusinessService {

    Mono<String> createReservation(ReservationRequest reservation);
    Mono<ReservationResponse> readByReservationId(UUID id);
    Flux<ReservationResponse> readByRestaurantId(UUID restaurantId, ReservationStatusEnum status);
    Mono<ReservationResponse> updateReservation(UUID id, ReservationRequest reservation);
    Mono<Void> deleteReservation(UUID id);

}
