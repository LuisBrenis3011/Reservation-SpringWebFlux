package com.brenis.SpringWebFlux.services.impls;
import com.brenis.SpringWebFlux.collections.ReservationCollection;
import com.brenis.SpringWebFlux.enums.ReservationStatusEnum;
import com.brenis.SpringWebFlux.exceptions.ResourceNotFoundException;
import com.brenis.SpringWebFlux.repositories.*;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.validators.ReservationValidator;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import reactor.core.publisher.*;
import java.util.*;
@RequiredArgsConstructor
@Service
public class ReservationCrudServiceImpl implements ReservationCrudService {
    private final ReservationRepository reservationRepository;
    private final RestaurantRepository restaurantRepository;
    private final ReservationValidator<ReservationCollection> reservationValidator;
    private final RestaurantOperationCoordinator coordinator;
    private LegacyReservationWriteBarrier writeBarrier;
    @org.springframework.beans.factory.annotation.Autowired
    void configureWriteBarrier(org.springframework.data.mongodb.core.ReactiveMongoTemplate mongo) {
        this.writeBarrier=new LegacyReservationWriteBarrier(mongo);
    }
    private Mono<Void> allowLegacyWrite(){return writeBarrier==null?Mono.error(new com.brenis.SpringWebFlux.exceptions.AvailabilityException("DEPENDENCY_UNAVAILABLE","Barrera no configurada")):writeBarrier.check();}
    @Override public Mono<ReservationCollection> createReservation(ReservationCollection value){return Mono.defer(()->allowLegacyWrite().then(Mono.defer(()->createLegacy(value))));}
    @Override public Mono<ReservationCollection> updateReservation(UUID id,ReservationCollection value){return Mono.defer(()->allowLegacyWrite().then(Mono.defer(()->writeBarrier.checkTarget(id))).then(Mono.defer(()->updateLegacy(id,value))));}
    @Override public Mono<Void> deleteReservation(UUID id){return Mono.defer(()->allowLegacyWrite().then(Mono.defer(()->writeBarrier.checkTarget(id))).then(Mono.defer(()->deleteLegacy(id))));}
    private Mono<ReservationCollection> existing(UUID id) {
        return reservationRepository.findById(id).switchIfEmpty(Mono.error(new ResourceNotFoundException("Reservation no found")));
    }
    private Mono<ReservationCollection> createLegacy(ReservationCollection reservation) {
        reservation.setId(UUID.randomUUID()); // una identidad por comando, estable en retries
        if(reservation.getStatus()==null) reservation.setStatus(ReservationStatusEnum.PENDING);
        UUID owner=UUID.fromString(reservation.getRestaurantId());
        return reservationValidator.applyValidation(reservation,List.of(reservationValidator.validateAvailability(),
                reservationValidator.validateRestaurantNotClosed()))
                .then(coordinator.writeLegacy(owner,ctx ->
                        allowLegacyWrite().then(reservationValidator.applyValidation(reservation,List.of(reservationValidator.validateRestaurantNotClosed())))
                                .then(Mono.defer(() -> reservationRepository.save(reservation)))));
    }
    private Mono<ReservationCollection> updateLegacy(UUID id,ReservationCollection input) {
        return existing(id).flatMap(original ->
            reservationValidator.validateRestaurantIDBeforeUpdate(original.getRestaurantId()).validate(input)
            .then(Mono.defer(() -> reservationValidator.applyValidation(input,List.of(reservationValidator.validateAvailability(),
                    reservationValidator.validateRestaurantNotClosed()))))
            .then(coordinator.writeLegacy(UUID.fromString(original.getRestaurantId()),ctx ->
                allowLegacyWrite().then(existing(id)).flatMap(current ->
                    reservationValidator.validateRestaurantIDBeforeUpdate(current.getRestaurantId()).validate(input)
                    .then(reservationValidator.applyValidation(input,List.of(reservationValidator.validateRestaurantNotClosed())))
                    .then(Mono.defer(() -> {
                        current.setCustomerName(input.getCustomerName()); current.setNotes(input.getNotes());
                        current.setDate(input.getDate()); current.setTime(input.getTime()); current.setPartySize(input.getPartySize());
                        return reservationRepository.save(current);
                    }))))));
    }
    private Mono<Void> deleteLegacy(UUID id) {
        return existing(id).flatMap(original -> coordinator.writeLegacy(UUID.fromString(original.getRestaurantId()),
                ctx -> allowLegacyWrite().then(existing(id)).flatMap(current -> {
                    if(!current.getRestaurantId().equals(original.getRestaurantId()))
                        return Mono.error(new IllegalStateException("Restaurant changed concurrently"));
                    return reservationRepository.deleteById(id);
                })));
    }
    @Override public Mono<ReservationCollection> readByReservationId(UUID id) { return existing(id); }
    @Override public Flux<ReservationCollection> readByRestaurantId(UUID restaurantId,ReservationStatusEnum status) {
        return restaurantRepository.findById(restaurantId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("Restaurant no found")))
                .flatMapMany(r -> status==null?reservationRepository.findByRestaurantId(restaurantId.toString()):
                        reservationRepository.findByRestaurantIdAndStatus(restaurantId.toString(),status));
    }
}
