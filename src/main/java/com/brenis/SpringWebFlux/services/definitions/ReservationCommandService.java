package com.brenis.SpringWebFlux.services.definitions;

import java.security.Principal;
import java.util.UUID;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.ManagedReservationRequest;
import com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse;

public interface ReservationCommandService {
    Mono<RestaurantOperationCoordinator.Result<ManagedReservationResponse>> cancel(
        Principal actor, UUID restaurantId, UUID reservationId, long expectedVersion, CommandMetadata command);
    Mono<RestaurantOperationCoordinator.Result<ManagedReservationResponse>> replace(
        Principal actor, UUID restaurantId, UUID reservationId, long expectedVersion,
        ManagedReservationRequest request, CommandMetadata command);
    Mono<RestaurantOperationCoordinator.Result<ManagedReservationResponse>> confirm(
        Principal actor, UUID restaurantId, ManagedReservationRequest request, CommandMetadata command);
}
