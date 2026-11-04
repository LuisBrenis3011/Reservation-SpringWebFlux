package com.brenis.SpringWebFlux.validators;

import com.brenis.SpringWebFlux.clientes.PlannerMSClient;
import com.brenis.SpringWebFlux.collections.ReservationCollection;
import com.brenis.SpringWebFlux.collections.RestaurantCollection;
import com.brenis.SpringWebFlux.exceptions.BusinessException;
import com.brenis.SpringWebFlux.repositories.RestaurantRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

@Component
@Slf4j
@RequiredArgsConstructor
public class ReservationValidator<T> {

    private final RestaurantRepository restaurantRepository;
    private final PlannerMSClient client;

    public <T>Mono<Void> applyValidation(T input, List<BusinessValidator<T>> validations) {
        if(validations.isEmpty()){
            return Mono.empty();
        }
        return validations.stream()
                .reduce(Mono.empty(), (chain, validator) -> chain.then(validator.validate(input)), Mono::then);
    }

    public BusinessValidator<ReservationCollection> validateRestaurantNotClosed(){
        log.info("Validating restaurant not closed");
        return reservation -> {
            final var restaurantId = UUID.fromString(reservation.getRestaurantId());
            return this.restaurantRepository.findById(restaurantId)
                    .switchIfEmpty(Mono.error(new BusinessException("Restaurant not found")))
                    .flatMap(restaurant -> {
                        if(this.isRestaurantClosed(restaurant, reservation.getTime())){
                            return Mono.error(new BusinessException("Restaurant already closed"));
                        }
                        return Mono.empty();
                    });
        };
    }

    public BusinessValidator<ReservationCollection> validateAvailability(){
        log.info("Validating availability");
        return reserva -> {
            final var restaurantID= UUID.fromString(reserva.getRestaurantId());
            return this.client.verifyAvailability(reserva.getDate(), reserva.getTime(), restaurantID)
                    .filter(available -> available)
                    .switchIfEmpty(Mono.error(new BusinessException("No availability...")))
                    .flatMap(available -> Mono.empty());
        };
    }

    public BusinessValidator<ReservationCollection> validateRestaurantIDBeforeUpdate(String originalRestaurantId){
        log.info("Validating restaurant ID before update");
        return reserva ->{
            if (!UUID.fromString(originalRestaurantId).equals(UUID.fromString(reserva.getRestaurantId()))) {
                return Mono.error(new BusinessException("Restaurant ID must be the same as the original Restaurant"));
            }
            return Mono.empty();
        };
    }

    private boolean isRestaurantClosed(RestaurantCollection restaurant, String reservationTime){
        try{
            if(Objects.isNull(restaurant.getCloseAt()) || Objects.isNull(reservationTime)){
                return true;
            }

            LocalTime closeLocalTime = LocalTime.parse(restaurant.getCloseAt(), DateTimeFormatter.ofPattern("HH:mm"));
            LocalTime reservationLocalTime = LocalTime.parse(reservationTime, DateTimeFormatter.ofPattern("HH:mm"));

            return reservationLocalTime.isAfter(closeLocalTime);


        }catch (Exception e){
            log.error(e.getMessage(), e);
            return true;
        }
    }


}
