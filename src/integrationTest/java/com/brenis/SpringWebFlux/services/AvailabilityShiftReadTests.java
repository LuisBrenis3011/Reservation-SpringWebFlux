package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import reactor.test.StepVerifier;
import java.time.*;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;
class AvailabilityShiftReadTests extends AvailabilityShiftIntegrationSupport {
    @Test void esc0307_0308_snapshotEstableEHistoria(){
        assertThat(shifts.list(manager,restaurant).block().body().items()).isEmpty();
        var saved=createShift("night","2026-11-01T22:00:00","2026-11-02T02:00:00").block();
        // Fixture de lectura: una zona actual distinta no reinterpreta el snapshot.
        mongo.save(new com.brenis.SpringWebFlux.collections.RestaurantTimeZoneCollection(restaurant,"Asia/Tokyo")).block();
        clock.set(Instant.parse("2026-12-01T00:00:00Z"));
        assertThat(shifts.read(manager,restaurant,saved.body().id()).block().body()).isEqualTo(saved.body());
        assertThat(saved.body().zoneId()).isEqualTo("America/Lima");
        assertThat(saved.body().startInstant()).isEqualTo(Instant.parse("2026-11-02T03:00:00Z"));
        assertThat(shifts.list(manager,restaurant).block().body().items()).containsExactly(saved.body());
        assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);
        StepVerifier.create(shifts.read(manager,restaurant,UUID.randomUUID())).expectErrorMatches(e -> e.getMessage().contains("NOT_FOUND")).verify();
        var other=shiftRepository.insert(new com.brenis.SpringWebFlux.collections.RestaurantShiftCollection(UUID.randomUUID(),UUID.randomUUID(),"2026-11-01T22:00:00","2026-11-02T02:00:00","America/Lima",saved.body().startInstant(),saved.body().endInstant())).block();
        StepVerifier.create(shifts.read(manager,restaurant,other.id())).expectErrorMatches(e -> e.getMessage().contains("NOT_FOUND")).verify();
        assertThat(shifts.list(manager,restaurant).block().body().items()).hasSize(1);
    }
    @Test void aislamientoYReplayHistorico(){
        var saved=createShift("one","2026-11-01T22:00:00","2026-11-02T02:00:00").block();
        createShift("two","2026-11-02T03:00:00","2026-11-02T04:00:00").block();
        assertThat(createShift("one","2026-11-01T22:00:00","2026-11-02T02:00:00").block()).isEqualTo(saved);
        StepVerifier.create(shifts.list(manager,UUID.randomUUID())).expectErrorMatches(e -> e.getMessage().contains("FORBIDDEN")).verify();
        StepVerifier.create(createShift("one","2026-11-03T03:00:00","2026-11-03T04:00:00")).expectErrorMatches(e -> e.getMessage().contains("IDEMPOTENCY_CONFLICT")).verify();
        assertThat(revision()).isEqualTo(3);assertThat(receiptCount()).isEqualTo(3);
    }
}
