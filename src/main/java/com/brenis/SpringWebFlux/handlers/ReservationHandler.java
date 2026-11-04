package com.brenis.SpringWebFlux.handlers;

import com.brenis.SpringWebFlux.dtos.requests.ReservationRequest;
import com.brenis.SpringWebFlux.dtos.responses.ReservationResponse;
import com.brenis.SpringWebFlux.services.definitions.ReservationBusinessService;
import com.brenis.SpringWebFlux.validators.ReactiveValidator;
import jakarta.validation.ValidationException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.ServerRequest;
import org.springframework.web.reactive.function.server.ServerResponse;
import reactor.core.publisher.Mono;

import java.net.URI;
import java.util.Map;
import java.util.UUID;

@Component
@RequiredArgsConstructor
@Slf4j
public class ReservationHandler {
    private final ReservationBusinessService reservationBusinessService;
    private final ReactiveValidator validator;
    private com.brenis.SpringWebFlux.services.impls.LegacyReservationWriteBarrier writeBarrier;
    private ReservationHttpSupport reservationHttp;
    private ReservationQueryHandler reservationQuery;
    @org.springframework.beans.factory.annotation.Autowired
    void configureReservationQuery(ReservationQueryHandler query){this.reservationQuery=query;}
    @org.springframework.beans.factory.annotation.Autowired
    void configureLegacyBarrier(com.brenis.SpringWebFlux.services.impls.LegacyReservationWriteBarrier barrier,ReservationHttpSupport http){this.writeBarrier=barrier;this.reservationHttp=http;}
    private Mono<ServerResponse> write(java.util.function.Supplier<Mono<ServerResponse>> action){
        return Mono.defer(()->writeBarrier==null?Mono.<ServerResponse>error(new com.brenis.SpringWebFlux.exceptions.AvailabilityException("DEPENDENCY_UNAVAILABLE","Barrera no configurada")):writeBarrier.check().then(Mono.defer(action))).onErrorResume(e->reservationHttp==null?Mono.error(e):reservationHttp.error(e));
    }
    public Mono<ServerResponse> postReservation(ServerRequest request){return write(()->postLegacy(request));}
    public Mono<ServerResponse> updateReservation(ServerRequest request){return write(()->updateLegacy(request));}
    public Mono<ServerResponse> deleteReservation(ServerRequest request){return write(()->deleteLegacy(request));}

    private Mono<ServerResponse> postLegacy(ServerRequest request) {
        return request.bodyToMono(ReservationRequest.class)
                .flatMap(this.validator::validate)
                .flatMap(this.reservationBusinessService::createReservation)
                .flatMap(id ->
                    ServerResponse
                            .created(URI.create("/reservations/" + id))
                            .contentType(MediaType.APPLICATION_JSON)
                            .bodyValue(Map.of("Resource", "/reservations/" + id))
                )
                .doOnSuccess(response -> log.info("Created Reservation: " + response))
                .doOnError(error -> log.error("Error while creating Reservation whit error:{}", error.getMessage()));
    }

    public Mono<ServerResponse> getReservationsById(ServerRequest request) {
        return reservationQuery==null?Mono.error(new com.brenis.SpringWebFlux.exceptions.AvailabilityException("DEPENDENCY_UNAVAILABLE","Consulta segura no configurada")):reservationQuery.oldById(request);
    }

    private Mono<ServerResponse> updateLegacy(ServerRequest request) {
        final var id = request.pathVariable("id");
        return this.parseUUID(id)
                .flatMap(uuid -> request.bodyToMono(ReservationRequest.class)
                        .flatMap(this.validator::validate)
                        .flatMap(reservationRequest -> this.reservationBusinessService.updateReservation(uuid, reservationRequest)))
                .flatMap(updateReservation -> ServerResponse.ok()
                        .contentType(MediaType.APPLICATION_JSON)
                        .bodyValue(updateReservation))
                .switchIfEmpty(ServerResponse.notFound().build())
                .doOnSuccess(response -> log.info("Updated Reservation: " + response))
                .doOnError(error -> log.error("Error while updating Reservation with id " + id, error.getMessage()));


    }

    private Mono<ServerResponse> deleteLegacy(ServerRequest request) {
        final var id = request.pathVariable("id");
        return this.parseUUID(id)
                .flatMap(this.reservationBusinessService::deleteReservation)
                .then(ServerResponse.noContent().build())
                .doOnSuccess(response -> log.info("Deleted Reservation with id: " + id))
                .doOnError(error -> log.error("Error while deleting Reservation with id {}: {}", id, error.getMessage()));
    }

    public Mono<UUID> parseUUID(String id) {
        try {
            return Mono.just(UUID.fromString(id));
        } catch (IllegalArgumentException e) {
            return Mono.error(new ValidationException("Invalid UUID format: " + id));
        }
    }
}
