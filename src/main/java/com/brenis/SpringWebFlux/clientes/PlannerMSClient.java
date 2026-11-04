package com.brenis.SpringWebFlux.clientes;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

@Component
@Slf4j
public class PlannerMSClient {
    private static final String UNAVAILABLE_RESTAURANT_ID = "dfcbe98d-392b-4b93-9a49-27005223d15d"; //Always is FULL

    public Mono<Boolean> verifyAvailability(String date, String time, UUID restaurantId) {
        return Mono.fromCallable(() -> !UNAVAILABLE_RESTAURANT_ID.equals(restaurantId.toString()))
                .delayElement(getRandomDuration())
                .doOnNext(reservation -> log.info("Cheking availability for restaurant {}, date {}, time {}", restaurantId, date, time));
    }

    private Duration getRandomDuration() {
        final var randomint = ThreadLocalRandom.current().nextInt(20, 1000);
        return Duration.ofMillis(randomint);
    }
}
