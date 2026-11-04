package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import reactor.core.publisher.*;
import reactor.test.StepVerifier;
import java.time.Duration;
import java.util.List;
import static org.assertj.core.api.Assertions.*;
class AvailabilityShiftConcurrencyIT extends AvailabilityShiftIntegrationSupport {
    @Test void edicionFrenteAConfirmacionConservaCompromiso(){
        var first=createShift("first","2026-11-01T22:00:00","2026-11-02T02:00:00").block().body();long v=revision(),r=receiptCount();
        var snapshot=com.brenis.SpringWebFlux.support.AvailabilityMongoFixture.confirmedSnapshot(restaurant,first.id(),java.util.UUID.randomUUID(),first.startInstant(),first.endInstant());
        Sinks.One<Void> inside=Sinks.one();
        var confirmation=coordinator.writeLegacy(restaurant,ctx -> {inside.tryEmitEmpty();return Mono.delay(Duration.ofMillis(200)).then(mongo.insert(snapshot,"reservations"));});
        var editing=inside.asMono().then(edit(first.id(),"race-edit","2026-11-02T22:00:00","2026-11-03T02:00:00",v));
        var outcome=Mono.zip(confirmation.materialize(),editing.materialize()).block(Duration.ofSeconds(15));
        assertThat(outcome.getT1().hasValue()).isTrue();assertThat(outcome.getT2().isOnError()).isTrue();
        assertThat(((AvailabilityException)outcome.getT2().getThrowable()).code()).isIn("REVISION_MISMATCH","DEPENDENCY_UNAVAILABLE");
        StepVerifier.create(edit(first.id(),"after-confirm","2026-11-02T22:00:00","2026-11-03T02:00:00",revision())).expectErrorMatches(e -> e.getMessage().contains("PROTECTED_RESERVATION")).verify();
        assertThat(revision()).isEqualTo(v+1);assertThat(receiptCount()).isEqualTo(r);
        assertThat(shifts.read(manager,restaurant,first.id()).block().body().startInstant()).isEqualTo(first.startInstant());
    }
    @Test void esc0311_0312_altasSuperpuestasNoSeConfirmanAmbas(){
        var results=Mono.zip(createShift("a","2026-11-01T22:00:00","2026-11-02T02:00:00").materialize(),createShift("b","2026-11-01T23:00:00","2026-11-02T03:00:00").materialize()).block(Duration.ofSeconds(15));
        var outcomes=List.of(results.getT1(),results.getT2());
        assertThat(outcomes.stream().filter(Signal::hasValue).count()).isEqualTo(1);
        var error=outcomes.stream().filter(Signal::isOnError).findFirst().orElseThrow().getThrowable();
        assertThat(error).isInstanceOf(AvailabilityException.class);assertThat(((AvailabilityException)error).code()).isIn("SHIFT_OVERLAP","DEPENDENCY_UNAVAILABLE");
        var retry=results.getT1().isOnError()?createShift("a","2026-11-01T22:00:00","2026-11-02T02:00:00"):createShift("b","2026-11-01T23:00:00","2026-11-02T03:00:00");
        StepVerifier.create(retry).expectErrorMatches(e -> e.getMessage().contains("SHIFT_OVERLAP")).verify();
        assertThat(shiftRepository.findAllByRestaurantId(restaurant).collectList().block()).hasSize(1);assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);
    }
}
