package com.brenis.SpringWebFlux.services;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.*;
import reactor.test.StepVerifier;
import org.springframework.transaction.reactive.TransactionalOperator;
import com.brenis.SpringWebFlux.repositories.*;
import com.brenis.SpringWebFlux.collections.*;
import com.brenis.SpringWebFlux.services.impls.*;
import com.brenis.SpringWebFlux.validators.ReservationTimePolicy;
import com.brenis.SpringWebFlux.configs.AvailabilityProperties;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.assertj.core.api.Assertions.*;
class ReservationAvailabilityFallbackTests {
    @Test @SuppressWarnings({"unchecked","rawtypes"})
    void fallbackEsperaRollbackYAbreSegundaLecturaSoloDeOferta(){
        var restaurants=mock(RestaurantRepository.class);var shifts=mock(RestaurantShiftRepository.class);
        var tables=mock(TableRepository.class);var combinations=mock(TableCombinationRepository.class);
        var occupancy=mock(ReservationOccupancyReader.class);var tx=mock(TransactionalOperator.class);
        var now=Instant.parse("2026-11-01T10:00:00Z");var owner=UUID.randomUUID();var shift=UUID.randomUUID();
        var rollback=Sinks.<Void>empty();var subscriptions=new java.util.concurrent.atomic.AtomicInteger();
        when(tx.transactional(any(Mono.class))).thenAnswer(call->{Mono<Object> source=call.getArgument(0);
            return Mono.defer(()->{subscriptions.incrementAndGet();return source.onErrorResume(error->rollback.asMono().then(Mono.error(error)));});});
        when(restaurants.existsById(owner)).thenReturn(Mono.just(true));
        when(shifts.findAllByRestaurantId(owner)).thenReturn(Flux.just(new RestaurantShiftCollection(shift,owner,"2026-11-01T13:00:00","2026-11-01T14:00:00","UTC",now.plusSeconds(10800),now.plusSeconds(14400))));
        when(tables.findAllByRestaurantId(owner)).thenReturn(Flux.just(new TableCollection(UUID.randomUUID(),owner,"Mesa","mesa",4)));
        when(combinations.findAllByRestaurantId(owner)).thenReturn(Flux.empty());
        when(occupancy.read(eq(owner),eq(shift),isNull(),eq(now))).thenReturn(Mono.error(new IllegalStateException("sesion abortada")));
        var service=new ReservationAvailabilityServiceImpl(restaurants,shifts,tables,combinations,occupancy,new ReservationAssignmentPolicy(),new ReservationTimePolicy(),tx,Clock.fixed(now,ZoneOffset.UTC),new AvailabilityProperties());
        StepVerifier.create(service.list(owner,LocalDate.parse("2026-11-01"),2)).expectSubscription().expectNoEvent(Duration.ofMillis(10))
            .then(()->{assertThat(subscriptions).hasValue(1);rollback.tryEmitEmpty();})
            .assertNext(result->{assertThat(subscriptions).hasValue(2);assertThat(result.items().getFirst().availability()).isEqualTo("UNDETERMINED");assertThat(result.items().getFirst().reservable()).isFalse();}).verifyComplete();
        verify(restaurants,times(2)).existsById(owner);verify(shifts,times(2)).findAllByRestaurantId(owner);
        verify(occupancy,times(1)).read(eq(owner),eq(shift),isNull(),eq(now));
    }
}
