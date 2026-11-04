package com.brenis.SpringWebFlux.services;

import com.brenis.SpringWebFlux.support.*;
import org.bson.Document;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;
import reactor.test.StepVerifier;
import java.time.*;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class AvailabilityCombinationProtectionIT extends AvailabilityCombinationIntegrationSupport {
    static final Instant NOW=Instant.parse("2026-11-01T10:00:00Z");
    UUID third,fourth,combination;
    @BeforeEach void prepareCombination() {
        third=create("member-3","Tres",3).block().body().id();
        fourth=create("member-4","Cuatro",1).block().body().id();
        combination=combine("protected-combination",List.of(first,second,third)).block().body().id();
    }
    @AfterEach void restoreClock() { clock.set(NOW); }
    Document protect(Instant start,Instant end) {
        var row=combinationRepository.findByIdAndRestaurantId(combination,restaurant).block();
        var snapshot=AvailabilityMongoFixture.confirmedSnapshot(restaurant,UUID.randomUUID(),first,start,end);
        snapshot.put("combinationId",combination);
        snapshot.put("tableIds",row.tableIds());
        var history=new ArrayList<Document>();
        for(UUID tableId:row.tableIds()) {
            var table=repository.findByIdAndRestaurantId(tableId,restaurant).block();
            history.add(new Document("tableId",tableId).append("label",table.label()).append("capacity",table.capacity()));
        }
        snapshot.put("tableSnapshots",history);
        return mongo.insert(snapshot,"reservations").block();
    }
    Document stored(Document reservation) { return mongo.findById(reservation.get("_id"),Document.class,"reservations").block(); }
    @Test void esc0207_cambioLibreConservaIdentidadRestauranteYMesasFisicas() {
        long version=revision(), receipts=receiptCount();
        var response=replace(combination,"free",List.of(first,second,fourth),version).block();
        assertThat(response.httpStatus()).isEqualTo(200);
        assertThat(response.location()).isNull();
        assertThat(response.body().id()).isEqualTo(combination);
        assertThat(response.body().restaurantId()).isEqualTo(restaurant);
        assertThat(response.body().tableIds()).containsExactlyInAnyOrder(first,second,fourth);
        assertThat(response.body().capacity()).isEqualTo(7);
        assertThat(revision()).isEqualTo(version+1); assertThat(receiptCount()).isEqualTo(receipts+1);
        assertThat(combinations.read(manager,restaurant,combination).block().body()).isEqualTo(response.body());
        assertThat(tables.list(manager,restaurant).block().body().totalCapacity()).isEqualTo(10);
    }
    @ParameterizedTest @CsvSource({"3600,replace","3600,add","3600,remove",
            "-1800,replace","-1800,add","-1800,remove"})
    void esc0208_0211_protegeAgregarRetirarOSustituirEnReservaFuturaYEnCurso(long offset,String action) {
        var reservation=protect(NOW.plusSeconds(offset),NOW.plusSeconds(offset+7200));
        var history=stored(reservation);
        var before=combinationRepository.findByIdAndRestaurantId(combination,restaurant).block();
        var tablesBefore=repository.findAllByRestaurantId(restaurant).collectList().block();
        long version=revision(), receipts=receiptCount();
        List<UUID> next=switch(action) {
            case "add" -> List.of(first,second,third,fourth);
            case "remove" -> List.of(first,second);
            default -> List.of(first,second,fourth);
        };
        StepVerifier.create(replace(combination,"protected-"+action,next,version))
                .expectErrorMatches(e -> e.getMessage().contains("PROTECTED_RESERVATION")).verify();
        assertThat(combinationRepository.findByIdAndRestaurantId(combination,restaurant).block()).isEqualTo(before);
        assertThat(stored(reservation)).isEqualTo(history);
        assertThat(repository.findAllByRestaurantId(restaurant).collectList().block()).isEqualTo(tablesBefore);
        assertThat(revision()).isEqualTo(version); assertThat(receiptCount()).isEqualTo(receipts);
    }
    @ParameterizedTest @ValueSource(longs={3600,-1800})
    void conjuntoIdenticoEnOtroOrdenNoAlteraCompromisosPeroEsUnComandoNuevo(long offset) {
        var reservation=protect(NOW.plusSeconds(offset),NOW.plusSeconds(offset+7200));
        var before=stored(reservation);
        var row=combinationRepository.findByIdAndRestaurantId(combination,restaurant).block();
        long version=revision(), receipts=receiptCount();
        var accepted=replace(combination,"same-members",List.of(third,second,first),version).block();
        assertThat(accepted.body().id()).isEqualTo(combination);
        assertThat(accepted.body().tableIds()).isEqualTo(row.tableIds());
        assertThat(accepted.body().capacity()).isEqualTo(9);
        assertThat(combinationRepository.findByIdAndRestaurantId(combination,restaurant).block()).isEqualTo(row);
        assertThat(stored(reservation)).isEqualTo(before);
        assertThat(revision()).isEqualTo(version+1); assertThat(receiptCount()).isEqualTo(receipts+1);
    }
    @Test void esc0212_finExactoLiberaSinCambiarSnapshotsHistoricos() {
        Instant end=NOW.plusSeconds(600);
        var reservation=protect(NOW.minusSeconds(600),end);
        var before=stored(reservation);
        long version=revision();
        clock.set(end.minusNanos(1));
        StepVerifier.create(replace(combination,"at-end",List.of(first,second,fourth),version))
                .expectErrorMatches(e -> e.getMessage().contains("PROTECTED_RESERVATION")).verify();
        assertThat(revision()).isEqualTo(version);
        clock.set(end);
        var accepted=replace(combination,"at-end",List.of(first,second,fourth),version).block();
        assertThat(accepted.body().capacity()).isEqualTo(7);
        assertThat(accepted.body().id()).isEqualTo(combination);
        assertThat(revision()).isEqualTo(version+1);
        assertThat(stored(reservation)).isEqualTo(before);
    }
}
