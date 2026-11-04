package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import reactor.test.StepVerifier;
import static org.assertj.core.api.Assertions.*;
class AvailabilityShiftOverlapIT extends AvailabilityShiftIntegrationSupport {
    @Test void edicionExcluyeIdentidadYRechazaRevisionOSolapamiento(){
        var first=createShift("first","2027-01-01T10:00:00","2027-01-01T11:00:00").block().body();
        createShift("second","2027-01-01T12:00:00","2027-01-01T13:00:00").block();long v=revision(),r=receiptCount();
        StepVerifier.create(edit(first.id(),"overlap","2027-01-01T12:30:00","2027-01-01T13:30:00",v)).expectErrorMatches(e -> e.getMessage().contains("SHIFT_OVERLAP")).verify();
        StepVerifier.create(edit(first.id(),"stale","2027-01-01T10:00:00","2027-01-01T11:00:00",v-1)).expectErrorMatches(e -> e.getMessage().contains("REVISION_MISMATCH")).verify();
        assertThat(revision()).isEqualTo(v);assertThat(receiptCount()).isEqualTo(r);
        assertThat(edit(first.id(),"same","2027-01-01T10:00:00","2027-01-01T11:00:00",v).block().body().id()).isEqualTo(first.id());
    }
    @Test void esc0305_0306_adyacenciaYSuperposicionEntreFechas(){
        createShift("first","2026-11-01T22:00:00","2026-11-02T02:00:00").block();
        createShift("adjacent","2026-11-02T02:00:00","2026-11-02T03:00:00").block();
        long version=revision(),receipts=receiptCount();
        StepVerifier.create(createShift("overlap","2026-11-02T01:59:59","2026-11-02T04:00:00")).expectErrorMatches(e -> e.getMessage().contains("SHIFT_OVERLAP")).verify();
        assertThat(shiftRepository.findAllByRestaurantId(restaurant).collectList().block()).hasSize(2);
        assertThat(revision()).isEqualTo(version);assertThat(receiptCount()).isEqualTo(receipts);
    }
    @Test void sinZonaNoSeCreaTurno(){
        mongo.remove(org.springframework.data.mongodb.core.query.Query.query(org.springframework.data.mongodb.core.query.Criteria.where("_id").is(restaurant)),"restaurant_time_zones").block();
        StepVerifier.create(createShift("no-zone","2026-11-01T22:00:00","2026-11-02T02:00:00")).expectErrorMatches(e -> e.getMessage().contains("VALIDATION_ERROR")).verify();
        assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
    }
}
