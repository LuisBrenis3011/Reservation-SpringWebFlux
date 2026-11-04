package com.brenis.SpringWebFlux.services.impls;

import com.brenis.SpringWebFlux.dtos.requests.ReservationRequest;
import com.brenis.SpringWebFlux.dtos.responses.ReservationResponse;
import com.brenis.SpringWebFlux.enums.ReservationStatusEnum;
import com.brenis.SpringWebFlux.mappers.ReservationMapper;
import com.brenis.SpringWebFlux.repositories.ReservationRepository;
import com.brenis.SpringWebFlux.services.definitions.ReservationBusinessService;
import com.brenis.SpringWebFlux.services.definitions.ReservationCrudService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class ReservationBusinessServiceImpl implements ReservationBusinessService {

    private final ReservationCrudService reservationCrudService;
    private final ReservationMapper reservationMapper;

    @Override
    public Mono<String> createReservation(ReservationRequest reservation) {

        return Mono.just(reservation)
                .transform(this.reservationMapper::toCollectionMono)
                .flatMap(this.reservationCrudService::createReservation)
                .map(saveCollection -> {
                    log.info("Reservation created with id {}", saveCollection.getId());
                    return saveCollection.getId().toString();
                });

    }

    @Override
    public Mono<ReservationResponse> readByReservationId(UUID id) {

        return this.reservationCrudService.readByReservationId(id)
                .transform(this.reservationMapper::toResponseMono)
                .doOnSuccess(response -> log.info("Read reservation with id {}", id));
    }

    @Override
    public Flux<ReservationResponse> readByRestaurantId(UUID restaurantId, ReservationStatusEnum status) {
        return this.reservationCrudService.readByRestaurantId(restaurantId, status)
                .transform(this.reservationMapper::toResponseFlux)
                .doOnComplete(()->log.info("Reading reservations by restaurant id {} and status {}", restaurantId, status));
    }

    @Override
    public Mono<ReservationResponse> updateReservation(UUID id, ReservationRequest reservation) {
        log.info("Updating reservation with id {}", id);
        return Mono.just(reservation)
                .transform(this.reservationMapper::toCollectionMono)
                .flatMap(reservationCollection -> this.reservationCrudService.updateReservation(id, reservationCollection))
                .transform(this.reservationMapper::toResponseMono)
                .doOnNext(response -> log.info("Updating reservation with id {}", id));
    }

    @Override
    public Mono<Void> deleteReservation(UUID id) {
        log.info("Deleting reservation with id {}", id);
        return this.reservationCrudService.deleteReservation(id)
                .doOnSuccess(response -> log.info("Deleted reservation with id {}", id));
    }
}
