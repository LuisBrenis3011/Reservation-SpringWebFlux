package com.brenis.SpringWebFlux.services;
import com.brenis.SpringWebFlux.dtos.requests.*;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import org.junit.jupiter.api.Test;
import java.time.*;
import reactor.test.StepVerifier;
import static org.assertj.core.api.Assertions.*;
class AvailabilityShiftZoneChangeIT extends AvailabilityShiftIntegrationSupport {
    @Test void cambioNoPuedeRecalcularInicioNoFuturo(){
        createShift("soon","2026-11-01T06:00:00","2026-11-01T07:00:00").block();long v=revision();
        StepVerifier.create(zone("bad","UTC",v)).expectErrorMatches(e -> e.getMessage().contains("SHIFT_ALREADY_STARTED")).verify();assertThat(revision()).isEqualTo(v);
    }
    @Test void reservaEnCursoProtegeZonaYEdicionSinAlterarSnapshot(){
        var first=createShift("first","2026-11-01T22:00:00","2026-11-02T02:00:00").block().body();
        var reservation=com.brenis.SpringWebFlux.support.AvailabilityMongoFixture.confirmedSnapshot(restaurant,first.id(),java.util.UUID.randomUUID(),clock.instant().minusSeconds(600),clock.instant().plusSeconds(600));
        mongo.insert(reservation,"reservations").block();var snapshot=mongo.findById(reservation.get("_id"),org.bson.Document.class,"reservations").block();long v=revision(),r=receiptCount();
        StepVerifier.create(zone("blocked","UTC",v)).expectErrorMatches(e -> e.getMessage().contains("PROTECTED_RESERVATION")).verify();
        StepVerifier.create(edit(first.id(),"protected-edit","2026-11-02T22:00:00","2026-11-03T02:00:00",v)).expectErrorMatches(e -> e.getMessage().contains("PROTECTED_RESERVATION")).verify();
        assertThat(revision()).isEqualTo(v);assertThat(receiptCount()).isEqualTo(r);assertThat(mongo.findById(reservation.get("_id"),org.bson.Document.class,"reservations").block()).isEqualTo(snapshot);
    }
    @Test void futuroRecalculadoNoSeSuperponeConHistoria(){
        createShift("history","2026-11-01T06:00:00","2026-11-01T08:00:00").block();
        createShift("future","2026-11-01T10:30:00","2026-11-01T11:30:00").block();clock.set(Instant.parse("2026-11-01T12:00:00Z"));long v=revision();
        StepVerifier.create(zone("overlap","America/Noronha",v)).expectErrorMatches(e -> e.getMessage().contains("SHIFT_OVERLAP")).verify();assertThat(revision()).isEqualTo(v);
    }
    reactor.core.publisher.Mono<?> zone(String key,String id,long version){return shifts.replaceZone(manager,restaurant,new RestaurantTimeZoneRequest(id),new CommandMetadata(key,"zone:"+id+":"+version,version,200,null));}
    @Test void futurosConservanLocalesEHistoriaSeMantiene(){
        var old=createShift("old","2026-11-01T06:00:00","2026-11-01T07:00:00").block().body();
        var future=createShift("future","2027-01-01T12:00:00","2027-01-01T13:00:00").block().body();
        clock.set(Instant.parse("2026-11-02T00:00:00Z"));
        var history=shiftRepository.findById(old.id()).block();
        zone("change","UTC",revision()).block();
        long after=revision();zone("change","UTC",after-1).block();assertThat(revision()).isEqualTo(after);
        assertThat(shiftRepository.findById(old.id()).block()).isEqualTo(history);
        var changed=shiftRepository.findById(future.id()).block();
        assertThat(changed.localStart()).isEqualTo(future.localStart());assertThat(changed.startInstant()).isEqualTo(Instant.parse("2027-01-01T12:00:00Z"));assertThat(changed.zoneId()).isEqualTo("UTC");
        assertThat(changed.localEnd()).isEqualTo(future.localEnd());
        assertThat(changed.endInstant()).isEqualTo(Instant.parse("2027-01-01T13:00:00Z"));
        assertThat(changed.id()).isEqualTo(future.id());
        assertThat(changed.restaurantId()).isEqualTo(future.restaurantId());
        assertThat(Duration.between(changed.startInstant(),changed.endInstant())).isEqualTo(Duration.ofHours(1));
    }
    @Test void esc0318_turnoTerminadoRechazaEdicionYConservaDocumentoRevisionYRecibos(){
        var saved=createShift("finished","2026-11-01T22:00:00","2026-11-02T02:00:00").block().body();
        var original=shiftRepository.findById(saved.id()).block();
        var originalZone=shifts.readZone(manager,restaurant).block().body();
        var query=org.springframework.data.mongodb.core.query.Query.query(
            org.springframework.data.mongodb.core.query.Criteria.where("restaurantId").is(restaurant));
        var receipts=mongo.find(query,org.bson.Document.class,"operation_receipts").collectList().block();
        long v=revision(),r=receiptCount();
        clock.set(saved.endInstant().plusSeconds(1));
        StepVerifier.create(edit(saved.id(),"edit-finished","2027-01-01T12:00:00","2027-01-01T13:00:00",v))
            .expectErrorMatches(error -> error instanceof com.brenis.SpringWebFlux.exceptions.AvailabilityException known
                && known.code().equals("SHIFT_ALREADY_STARTED")).verify();
        // El record compara identidad, propietario, ambos locales, zona y ambos instantes.
        assertThat(shiftRepository.findById(saved.id()).block()).isEqualTo(original);
        assertThat(shifts.read(manager,restaurant,saved.id()).block().body()).isEqualTo(saved);
        assertThat(shifts.readZone(manager,restaurant).block().body()).isEqualTo(originalZone);
        assertThat(revision()).isEqualTo(v);assertThat(receiptCount()).isEqualTo(r);
        assertThat(mongo.find(query,org.bson.Document.class,"operation_receipts").collectList().block())
            .containsExactlyInAnyOrderElementsOf(receipts);
    }
    @Test void segundoTurnoInvalidoRevierteTodo(){
        createShift("valid","2027-03-13T12:00:00","2027-03-13T13:00:00").block();
        createShift("gap","2027-03-14T02:30:00","2027-03-14T04:00:00").block();
        var rows=shiftRepository.findAllByRestaurantId(restaurant).collectList().block();long v=revision(),r=receiptCount();
        StepVerifier.create(zone("bad","America/New_York",v)).expectErrorSatisfies(error ->
            assertThat(error).isInstanceOfSatisfying(com.brenis.SpringWebFlux.exceptions.ShiftLocalTimeException.class,temporal -> {
                assertThat(temporal.code()).isEqualTo("VALIDATION_ERROR");
                assertThat(temporal.reason()).isEqualTo(com.brenis.SpringWebFlux.exceptions.ShiftLocalTimeException.Reason.NONEXISTENT);
            })).verify();
        assertThat(shiftRepository.findAllByRestaurantId(restaurant).collectList().block()).containsExactlyInAnyOrderElementsOf(rows);
        assertThat(shifts.readZone(manager,restaurant).block().body().zoneId()).isEqualTo("America/Lima");assertThat(revision()).isEqualTo(v);assertThat(receiptCount()).isEqualTo(r);
    }
    @Test void putFuturoConservaIdentidadYReplayYRechazaHistoria(){
        var saved=createShift("one","2026-11-01T22:00:00","2026-11-02T02:00:00").block().body();
        var req=new RestaurantShiftRequest("2026-11-02T22:00:00","2026-11-03T02:00:00");long v=revision();
        var cmd=new CommandMetadata("edit","edit",v,200,null);
        var response=shifts.replace(manager,restaurant,saved.id(),req,cmd).block();
        assertThat(response.body().id()).isEqualTo(saved.id());assertThat(response.revision()).isEqualTo(v+1);
        assertThat(shifts.replace(manager,restaurant,saved.id(),req,cmd).block()).isEqualTo(response);assertThat(revision()).isEqualTo(v+1);
        clock.set(response.body().startInstant());
        StepVerifier.create(shifts.replace(manager,restaurant,saved.id(),req,new CommandMetadata("late","late",revision(),200,null))).expectErrorMatches(e -> e.getMessage().contains("SHIFT_ALREADY_STARTED")).verify();
    }
}
