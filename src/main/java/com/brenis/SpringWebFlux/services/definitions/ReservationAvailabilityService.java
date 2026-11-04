package com.brenis.SpringWebFlux.services.definitions;
import java.time.LocalDate;
import java.util.UUID;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.dtos.responses.ReservationAvailabilityResponse;
public interface ReservationAvailabilityService {
    Mono<ReservationAvailabilityResponse> list(UUID restaurant,LocalDate date,int partySize);
}
