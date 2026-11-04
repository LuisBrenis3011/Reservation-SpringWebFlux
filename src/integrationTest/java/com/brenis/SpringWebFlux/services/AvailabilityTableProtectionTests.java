package com.brenis.SpringWebFlux.services;

import com.brenis.SpringWebFlux.support.*;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import org.bson.Document;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import reactor.test.StepVerifier;
import java.time.*;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class AvailabilityTableProtectionTests extends AvailabilityTableIntegrationSupport {
    static final Instant NOW=Instant.parse("2026-11-01T10:00:00Z");
    @BeforeEach void fixedClock() { clock.set(NOW); }
    @AfterEach void restoreClock() { clock.set(NOW); }
    Document protect(UUID table,Instant start,Instant end,boolean combination) {
        var snapshot=AvailabilityMongoFixture.confirmedSnapshot(restaurant,UUID.randomUUID(),table,start,end);
        var first=repository.findByIdAndRestaurantId(table,restaurant).block();
        var tableSnapshots=new ArrayList<Document>();
        tableSnapshots.add(new Document("tableId",table).append("label",first.label()).append("capacity",first.capacity()));
        if(combination) {
            UUID combinationId=UUID.randomUUID();
            var second=create("second","Mesa 2",2).block().body();
            mongo.insert(new Document("_id",combinationId).append("restaurantId",restaurant)
                    .append("tableIds",List.of(table,second.id())),"table_combinations").block();
            var ids=new ArrayList<Object>((List<?>)snapshot.get("tableIds"));
            ids.add(second.id());
            snapshot.put("tableIds",ids);
            snapshot.put("combinationId",combinationId);
            tableSnapshots.add(new Document("tableId",second.id()).append("label",second.label()).append("capacity",second.capacity()));
        }
        snapshot.put("tableSnapshots",tableSnapshots);
        return mongo.insert(snapshot,"reservations").block();
    }
    Document stored(Document reservation) {
        return mongo.findById(reservation.get("_id"),Document.class,"reservations").block();
    }
    @ParameterizedTest @CsvSource({"false,3600","true,3600","false,-1800","true,-1800"})
    void esc0110_0113_protegeCapacidadDirectaOCombinadaFuturaYEnCurso(boolean combined,long offset) {
        var table=create("first","Mesa 1",4).block().body();
        Instant start=NOW.plusSeconds(offset), end=start.plusSeconds(7200);
        var reservation=protect(table.id(),start,end,combined);
        var before=stored(reservation);
        long version=revision(), receipts=receiptCount();
        for(long capacity:List.of(2L,8L)) {
            StepVerifier.create(patch(table.id(),"blocked-"+capacity,new TablePatchRequest("No debe guardarse",capacity),version))
                    .expectErrorMatches(e -> e.getMessage().contains("PROTECTED_RESERVATION")).verify();
            assertThat(repository.findByIdAndRestaurantId(table.id(),restaurant).block().capacity()).isEqualTo(4);
            assertThat(repository.findByIdAndRestaurantId(table.id(),restaurant).block().label()).isEqualTo("Mesa 1");
            assertThat(revision()).isEqualTo(version);
            assertThat(receiptCount()).isEqualTo(receipts);
            assertThat(stored(reservation)).isEqualTo(before);
        }
    }
    @ParameterizedTest @CsvSource({"false,3600","true,3600","false,-1800","true,-1800"})
    void esc0109_0113_renombrarNoCambiaReservaNiSnapshots(boolean combined,long offset) {
        var table=create("first","Mesa 1",4).block().body();
        var reservation=protect(table.id(),NOW.plusSeconds(offset),NOW.plusSeconds(offset+7200),combined);
        var before=stored(reservation);
        long version=revision();
        var renamed=patch(table.id(),"rename",new TablePatchRequest("Ventana",4L),version).block();
        assertThat(renamed.body().id()).isEqualTo(table.id());
        assertThat(renamed.body().restaurantId()).isEqualTo(restaurant);
        assertThat(renamed.body().capacity()).isEqualTo(4);
        assertThat(renamed.body().label()).isEqualTo("Ventana");
        assertThat(revision()).isEqualTo(version+1);
        assertThat(stored(reservation)).isEqualTo(before);
    }
    @Test void esc0114_finExactoLiberaProteccionSinAlterarHistoria() {
        var table=create("first","Mesa 1",4).block().body();
        Instant end=NOW.plusSeconds(600);
        var reservation=protect(table.id(),NOW.minusSeconds(600),end,true);
        var before=stored(reservation);
        long version=revision();
        clock.set(end.minusNanos(1));
        StepVerifier.create(patch(table.id(),"at-end",new TablePatchRequest(null,6L),version))
                .expectErrorMatches(e -> e.getMessage().contains("PROTECTED_RESERVATION")).verify();
        assertThat(revision()).isEqualTo(version);
        clock.set(end);
        var accepted=patch(table.id(),"at-end",new TablePatchRequest(null,6L),version).block();
        assertThat(accepted.body().capacity()).isEqualTo(6);
        assertThat(revision()).isEqualTo(version+1);
        assertThat(stored(reservation)).isEqualTo(before);
    }
}

