package com.brenis.SpringWebFlux.services;

import com.brenis.SpringWebFlux.support.*;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.junit.jupiter.params.provider.CsvSource;
import reactor.test.StepVerifier;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class AvailabilityCombinationLegacyIT extends AvailabilityCombinationIntegrationSupport {
    @ParameterizedTest @ValueSource(booleans={false,true})
    void esc0216_legadoStringOBinarioBloqueaAltaSinAdaptarDatos(boolean binary) {
        var fixture=AvailabilityMongoFixture.unresolvedLegacy(restaurant,binary,"CONFIRMED");
        mongo.insert(fixture,"reservations").block();
        var before=mongo.findById(fixture.get("_id"),Document.class,"reservations").block();
        StepVerifier.create(combine("legacy",List.of(first,second)))
                .expectErrorMatches(e -> e.getMessage().contains("LEGACY_RESERVATION_BLOCK")).verify();
        assertThat(storedCombinations()).isEmpty();
        assertThat(revision()).isEqualTo(2); assertThat(receiptCount()).isEqualTo(2);
        assertThat(mongo.findById(fixture.get("_id"),Document.class,"reservations").block()).isEqualTo(before);
    }
    @Test void esc0215_consultaPermaneceDisponibleDuranteTransicion() {
        var saved=combine("before-legacy",List.of(first,second)).block().body();
        var fixture=AvailabilityMongoFixture.unresolvedLegacy(restaurant,false,"CONFIRMED");
        mongo.insert(fixture,"reservations").block();
        var before=mongo.findById(fixture.get("_id"),Document.class,"reservations").block();
        assertThat(combinations.read(manager,restaurant,saved.id()).block().body().capacity()).isEqualTo(6);
        assertThat(combinations.list(manager,restaurant).block().body().items()).hasSize(1);
        StepVerifier.create(combine("blocked",List.of(first,second)))
                .expectErrorMatches(e -> e.getMessage().contains("LEGACY_RESERVATION_BLOCK")).verify();
        assertThat(storedCombinations()).hasSize(1);
        assertThat(revision()).isEqualTo(3); assertThat(receiptCount()).isEqualTo(3);
        assertThat(mongo.findById(fixture.get("_id"),Document.class,"reservations").block()).isEqualTo(before);
    }
    @Test void fechaAntiguaSinFinFiableNoSeSuponeFinalizada() {
        var fixture=AvailabilityMongoFixture.unresolvedLegacy(restaurant,false,"CONFIRMED");
        fixture.put("date","2000-01-01");
        mongo.insert(fixture,"reservations").block();
        StepVerifier.create(combine("unknown-end",List.of(first,second)))
                .expectErrorMatches(e -> e.getMessage().contains("LEGACY_RESERVATION_BLOCK")).verify();
        assertThat(storedCombinations()).isEmpty(); assertThat(revision()).isEqualTo(2);
    }
    @ParameterizedTest @CsvSource({"false,false","false,true","true,false","true,true"})
    void esc0216_putIdenticoOCambiadoNoEvitaLegadoStringOBinario(boolean binary,boolean identical) {
        UUID third=create("third","Tres",3).block().body().id();
        var target=combine("before-legacy",List.of(first,second)).block().body();
        var fixture=AvailabilityMongoFixture.unresolvedLegacy(restaurant,binary,"CONFIRMED");
        mongo.insert(fixture,"reservations").block();
        var history=mongo.findById(fixture.get("_id"),Document.class,"reservations").block();
        var row=combinationRepository.findByIdAndRestaurantId(target.id(),restaurant).block();
        long version=revision(), receipts=receiptCount();
        StepVerifier.create(replace(target.id(),"put-legacy",identical?List.of(second,first):List.of(first,third),version))
                .expectErrorMatches(e -> e.getMessage().contains("LEGACY_RESERVATION_BLOCK")).verify();
        assertThat(combinations.read(manager,restaurant,target.id()).block().body().capacity()).isEqualTo(6);
        assertThat(combinationRepository.findByIdAndRestaurantId(target.id(),restaurant).block()).isEqualTo(row);
        assertThat(mongo.findById(fixture.get("_id"),Document.class,"reservations").block()).isEqualTo(history);
        assertThat(revision()).isEqualTo(version); assertThat(receiptCount()).isEqualTo(receipts);
    }
}
