package com.brenis.SpringWebFlux.services.definitions;
import java.security.Principal;
import java.util.UUID;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.dtos.responses.ReservationListResponse;
import com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse;
import com.brenis.SpringWebFlux.dtos.responses.LegacyReservationResponse;
public interface ReservationQueryService {
    Mono<ReservationListResponse> mine(Principal actor,int page,int size,String status);
    Mono<ReservationListResponse> byRestaurant(Principal actor,UUID restaurant,int page,int size);
    Mono<ManagedReservationResponse> managed(Principal actor,UUID restaurant,UUID reservation);
    Mono<LegacyReservationResponse> legacy(Principal actor,UUID restaurant,String reference);
    Mono<Object> oldById(Principal actor,UUID id);
}
