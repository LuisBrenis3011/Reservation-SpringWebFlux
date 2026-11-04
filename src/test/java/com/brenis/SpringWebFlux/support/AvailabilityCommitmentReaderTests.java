package com.brenis.SpringWebFlux.support;

import com.brenis.SpringWebFlux.repositories.LegacyReservationCommitmentAdapter;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.Query;
import reactor.core.publisher.Flux;
import reactor.test.StepVerifier;
import java.time.Instant;
import java.util.UUID;
import static org.mockito.Mockito.*;
import static org.assertj.core.api.Assertions.*;

class AvailabilityCommitmentReaderTests {
    final UUID owner = UUID.randomUUID();
    final AvailabilityClockFixture clock = new AvailabilityClockFixture(Instant.parse("2026-11-01T10:00:00Z"));
    final ReactiveMongoTemplate template = mock(ReactiveMongoTemplate.class);
    final LegacyReservationCommitmentAdapter reader = new LegacyReservationCommitmentAdapter(template);

    void records(Document... documents) {
        when(template.find(any(Query.class), eq(Document.class), eq("reservations")))
                .thenReturn(Flux.fromArray(documents));
    }
    @ParameterizedTest @ValueSource(booleans={false,true})
    void uuidStringYBinarioBloqueanSiNoHayFinFiable(boolean binary) {
        records(AvailabilityMongoFixture.unresolvedLegacy(owner, binary, "CONFIRMED"));
        StepVerifier.create(reader.read(owner, clock.instant())).assertNext(s ->
                assertThat(s.legacyBlocked()).isTrue()).verifyComplete();
    }
    @ParameterizedTest @ValueSource(strings={"cancelled","ATTENDED","No_Show"})
    void terminalReconocidoNoBloquea(String status) {
        records(AvailabilityMongoFixture.unresolvedLegacy(owner, false, status));
        StepVerifier.create(reader.read(owner, clock.instant())).assertNext(s ->
                assertThat(s.legacyBlocked()).isFalse()).verifyComplete();
    }
    @ParameterizedTest @ValueSource(strings={"PENDING","CONFIRMED","UNKNOWN"})
    void estadoNoTerminalSinFinNoSeDaPorTerminado(String status) {
        records(AvailabilityMongoFixture.unresolvedLegacy(owner, false, status).append("date","2000-01-01"));
        StepVerifier.create(reader.read(owner, clock.instant())).assertNext(s ->
                assertThat(s.legacyBlocked()).isTrue()).verifyComplete();
    }
    @Test void huerfanoBloqueaGlobalmente() {
        records(new Document("restaurantId","not-a-uuid").append("status","PENDING"));
        StepVerifier.create(reader.read(owner, clock.instant())).assertNext(s ->
                assertThat(s.globalBlocked()).isTrue()).verifyComplete();
    }
    @Test void snapshotProtegeHastaFinExacto() {
        UUID table=UUID.randomUUID(), shift=UUID.randomUUID();
        records(AvailabilityMongoFixture.confirmedSnapshot(owner,shift,table,
                clock.instant().minusSeconds(60),clock.instant().plusSeconds(60)));
        StepVerifier.create(reader.read(owner,clock.instant())).assertNext(s -> {
            assertThat(s.protectedTableIds()).contains(table);
            assertThat(s.protectedShiftIds()).contains(shift);
        }).verifyComplete();
        clock.advance(java.time.Duration.ofSeconds(60));
        StepVerifier.create(reader.read(owner,clock.instant())).assertNext(s ->
                assertThat(s.protectedTableIds()).isEmpty()).verifyComplete();
    }
    @Test void falloNoSeConvierteEnAusenciaDeReservas() {
        when(template.find(any(Query.class),eq(Document.class),eq("reservations")))
                .thenReturn(Flux.error(new IllegalStateException("database unavailable")));
        StepVerifier.create(reader.read(owner,clock.instant())).expectError().verify();
        verify(template,never()).save(any(),anyString());
    }
    @Test void comprobacionSinRespuestaTieneLimiteDeTresSegundos() {
        when(template.find(any(Query.class),eq(Document.class),eq("reservations"))).thenReturn(Flux.never());
        StepVerifier.withVirtualTime(() -> reader.read(owner,clock.instant()))
                .thenAwait(java.time.Duration.ofSeconds(3))
                .expectErrorMatches(e -> e.getMessage().contains("COMMITMENT_CHECK_UNAVAILABLE"))
                .verify(java.time.Duration.ofSeconds(2));
    }
}

