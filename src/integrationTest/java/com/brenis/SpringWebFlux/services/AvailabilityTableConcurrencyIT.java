package com.brenis.SpringWebFlux.services;

import com.brenis.SpringWebFlux.support.AvailabilityTableIntegrationSupport;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.collections.ReservationCollection;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import com.brenis.SpringWebFlux.support.AvailabilityMongoFixture;
import com.brenis.SpringWebFlux.services.impls.ReservationCrudServiceImpl;
import org.bson.Document;
import org.springframework.beans.factory.annotation.Autowired;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.*;
import java.time.Duration;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class AvailabilityTableConcurrencyIT extends AvailabilityTableIntegrationSupport {
    @Autowired ReservationCrudServiceImpl legacyService;
    @Test void esc0108_colisionDePatchRevierteEtiquetaCapacidadYRevision() {
        create("one","Mesa 1",4).block();
        var second=create("two","Mesa 2",2).block().body();
        var before=repository.findByIdAndRestaurantId(second.id(),restaurant).block();
        reactor.test.StepVerifier.create(patch(second.id(),"collision",new TablePatchRequest(" MESA 1 ",8L),revision()))
                .expectErrorMatches(e -> e.getMessage().contains("DUPLICATE_LABEL")).verify();
        assertThat(repository.findByIdAndRestaurantId(second.id(),restaurant).block()).isEqualTo(before);
        assertThat(revision()).isEqualTo(2);
        assertThat(receiptCount()).isEqualTo(2);
    }
    @Test void replayDePatchPrecedeIfMatchYNoIncrementaRevisionActual() {
        var first=create("first","Mesa 1",4).block().body();
        var input=new TablePatchRequest("Ventana",6L);
        var original=patch(first.id(),"patch",input,1).block();
        var second=create("second","Mesa 2",2).block().body();
        long current=revision();
        var replay=patch(first.id(),"patch",input,1).block();
        assertThat(replay).isEqualTo(original);
        assertThat(replay.body().revision()).isEqualTo(2);
        assertThat(replay.httpStatus()).isEqualTo(200);
        assertThat(replay.location()).isNull();
        assertThat(revision()).isEqualTo(current);
        reactor.test.StepVerifier.create(patch(first.id(),"stale",new TablePatchRequest("Otra",null),1))
                .expectErrorMatches(e -> e.getMessage().contains("REVISION_MISMATCH")).verify();
        reactor.test.StepVerifier.create(patch(first.id(),"patch",new TablePatchRequest("Otra",null),1))
                .expectErrorMatches(e -> e.getMessage().contains("IDEMPOTENCY_CONFLICT")).verify();
        reactor.test.StepVerifier.create(patch(second.id(),"patch",input,1))
                .expectErrorMatches(e -> e.getMessage().contains("IDEMPOTENCY_CONFLICT")).verify();
        reactor.test.StepVerifier.create(patch(first.id(),"patch",input,current))
                .expectErrorMatches(e -> e.getMessage().contains("IDEMPOTENCY_CONFLICT")).verify();
        assertThat(revision()).isEqualTo(current);
        assertThat(receiptCount()).isEqualTo(3);
        assertThat(repository.findByIdAndRestaurantId(first.id(),restaurant).block().label()).isEqualTo("Ventana");
    }
    @Test void esc0111_confirmacionConcurrenteImpideCambioDeCapacidadSinEstadoParcial() {
        var table=create("base","Mesa",4).block().body();
        var snapshot=AvailabilityMongoFixture.confirmedSnapshot(restaurant,UUID.randomUUID(),table.id(),
                clock.instant().plusSeconds(600),clock.instant().plusSeconds(3600));
        Sinks.One<Void> inside=Sinks.one();
        // La confirmación todavía no tiene API: fixture dentro de la frontera real de escritura.
        var confirmation=coordinator.writeLegacy(restaurant,ctx -> {
            inside.tryEmitEmpty();
            return Mono.delay(Duration.ofMillis(200)).then(mongo.insert(snapshot,"reservations"));
        });
        var change=inside.asMono().then(patch(table.id(),"during-confirm",new TablePatchRequest("Nueva",6L),1));
        var outcomes=Mono.zip(confirmation.materialize(),change.materialize()).block(Duration.ofSeconds(15));
        assertThat(outcomes.getT1().hasValue()).isTrue();
        assertThat(outcomes.getT2().isOnError()).isTrue();
        assertThat(outcomes.getT2().getThrowable()).isInstanceOf(AvailabilityException.class);
        assertThat(((AvailabilityException)outcomes.getT2().getThrowable()).code())
                .isIn("REVISION_MISMATCH","DEPENDENCY_UNAVAILABLE");
        var stored=mongo.findById(snapshot.get("_id"),Document.class,"reservations").block();
        assertThat(repository.findByIdAndRestaurantId(table.id(),restaurant).block().capacity()).isEqualTo(4);
        assertThat(repository.findByIdAndRestaurantId(table.id(),restaurant).block().label()).isEqualTo("Mesa");
        assertThat(revision()).isEqualTo(2);
        assertThat(receiptCount()).isEqualTo(1);
        reactor.test.StepVerifier.create(patch(table.id(),"after-confirm",new TablePatchRequest(null,6L),revision()))
                .expectErrorMatches(e -> e.getMessage().contains("PROTECTED_RESERVATION")).verify();
        assertThat(mongo.findById(snapshot.get("_id"),Document.class,"reservations").block()).isEqualTo(stored);
        assertThat(revision()).isEqualTo(2);
    }
    @Test void esc0111_patchCompiteConUpdateLegacyRealSinIncrementosParciales() {
        var table=create("base","Mesa",4).block().body();
        mongo.updateFirst(org.springframework.data.mongodb.core.query.Query.query(
                org.springframework.data.mongodb.core.query.Criteria.where("_id").is(restaurant)),
                new org.springframework.data.mongodb.core.query.Update().set("closeAt","23:59"),"restaurants").block();
        UUID reservationId=UUID.randomUUID();
        // Fin fiable pasado: no bloquea el cambio inicial. El writer antiguo no conserva
        // campos adaptados que su modelo desconoce; su actualización vuelve a bloquear.
        var past=AvailabilityMongoFixture.confirmedSnapshot(restaurant,UUID.randomUUID(),table.id(),
                clock.instant().minusSeconds(7200),clock.instant().minusSeconds(3600));
        past.put("_id",reservationId);
        past.put("restaurantId",restaurant.toString());
        past.put("status","PENDING");
        past.put("date","2026-11-01"); past.put("time","09:00"); past.put("partySize",2);
        mongo.insert(past,"reservations").block();
        var request=ReservationCollection.builder().restaurantId(restaurant.toString())
                .customerId(UUID.randomUUID().toString()).customerName("Prueba")
                .date("2026-11-02").time("12:00").partySize(2).notes("actualizada").build();
        var outcomes=Mono.zip(
                patch(table.id(),"race-update",new TablePatchRequest("Nueva",6L),1).materialize(),
                legacyService.updateReservation(reservationId,request).materialize()).block(Duration.ofSeconds(15));
        if(outcomes.getT2().isOnError()) {
            assertThat(com.brenis.SpringWebFlux.configs.MongoConfig.hasLabel(
                    outcomes.getT2().getThrowable(),"TransientTransactionError")).isTrue();
            assertThat(mongo.findById(reservationId,ReservationCollection.class).block().getNotes()).isNull();
            legacyService.updateReservation(reservationId,request).block(Duration.ofSeconds(10));
        }
        var saved=repository.findByIdAndRestaurantId(table.id(),restaurant).block();
        if(outcomes.getT1().hasValue()) {
            assertThat(saved.label()).isEqualTo("Nueva");
            assertThat(saved.capacity()).isEqualTo(6);
            assertThat(revision()).isEqualTo(3);
            assertThat(receiptCount()).isEqualTo(2);
        } else {
            assertThat(outcomes.getT1().getThrowable()).isInstanceOf(AvailabilityException.class);
            assertThat(((AvailabilityException)outcomes.getT1().getThrowable()).code())
                    .isIn("REVISION_MISMATCH","DEPENDENCY_UNAVAILABLE");
            assertThat(saved.label()).isEqualTo("Mesa");
            assertThat(saved.capacity()).isEqualTo(4);
            assertThat(revision()).isEqualTo(2);
            assertThat(receiptCount()).isEqualTo(1);
        }
        var reservation=mongo.findById(reservationId,Document.class,"reservations").block();
        assertThat(reservation.getString("notes")).isEqualTo("actualizada");
        long before=revision();
        reactor.test.StepVerifier.create(patch(table.id(),"after-update",new TablePatchRequest(null,saved.capacity()+1),before))
                .expectErrorMatches(e -> e.getMessage().contains("LEGACY_RESERVATION_BLOCK")).verify();
        assertThat(repository.findByIdAndRestaurantId(table.id(),restaurant).block()).isEqualTo(saved);
        assertThat(mongo.findById(reservationId,Document.class,"reservations").block()).isEqualTo(reservation);
        assertThat(revision()).isEqualTo(before);
    }
    @Test void indiceUnicoImpideDuplicadoAunqueSeOmitaElServicio() {
        create("unique","Mesa",4).block();
        reactor.test.StepVerifier.create(repository.insert(new com.brenis.SpringWebFlux.collections.TableCollection(
                UUID.randomUUID(),restaurant,"MESA","mesa",2)))
                .expectError(org.springframework.dao.DuplicateKeyException.class).verify();
        assertThat(repository.findAllByRestaurantId(restaurant).collectList().block()).hasSize(1);
        assertThat(revision()).isEqualTo(1);
    }
    @Test void esc0112_altasSimultaneasNoDuplicanEtiquetaNiRevision() {
        var results=Flux.merge(create("race-a"," Mesa 1 ",4).materialize(),
                create("race-b","mesa 1",2).materialize()).collectList().block(Duration.ofSeconds(15));
        assertThat(results.stream().filter(Signal::hasValue).count()).isEqualTo(1);
        var failure=results.stream().filter(Signal::isOnError).findFirst().orElseThrow().getThrowable();
        assertThat(failure).isInstanceOf(AvailabilityException.class);
        assertThat(((AvailabilityException)failure).code()).isIn("DUPLICATE_LABEL","DEPENDENCY_UNAVAILABLE");
        assertThat(repository.findAllByRestaurantId(restaurant).collectList().block()).hasSize(1);
        assertThat(revision()).isEqualTo(1);
        assertThat(receiptCount()).isEqualTo(1);
        // Tras acabar la carrera, la etiqueta debe seguir siendo un conflicto de dominio.
        reactor.test.StepVerifier.create(create("race-c","MESA 1",3))
                .expectErrorMatches(e -> e.getMessage().contains("DUPLICATE_LABEL")).verify();
        assertThat(revision()).isEqualTo(1);
    }
    @Test void replayDevuelveIdentidadCuerpoLocationYRevisionOriginales() {
        var first=create("stable","Mesa",4).block();
        create("other","Otra",2).block();
        long before=revision();
        var replay=create("stable","Mesa",4).block();
        assertThat(replay).isEqualTo(first);
        assertThat(replay.location()).endsWith(first.body().id().toString());
        assertThat(replay.body().revision()).isEqualTo(first.revision());
        assertThat(revision()).isEqualTo(before);
        assertThat(repository.findAllByRestaurantId(restaurant).collectList().block()).hasSize(2);
        reactor.test.StepVerifier.create(create("stable","Otro payload",4))
                .expectErrorMatches(e -> e.getMessage().contains("IDEMPOTENCY_CONFLICT")).verify();
        assertThat(revision()).isEqualTo(before);
    }
    @Test void esc0111_snapshotDuranteAltaMantieneTotalYRevisionCoherentes() {
        create("base","Mesa base",4).block();
        var views=Flux.merge(
                create("next","Mesa nueva",2).then(tables.list(manager,restaurant)),
                Flux.range(0,5).concatMap(i -> tables.list(manager,restaurant)))
                .collectList().block(Duration.ofSeconds(15));
        assertThat(views).hasSize(6);
        for(var view:views) {
            assertThat(view.body().items()).allSatisfy(t -> assertThat(t.revision()).isEqualTo(view.revision()));
            assertThat(view.body().totalCapacity()).isEqualTo(
                    view.body().items().stream().mapToLong(t -> t.capacity()).sum());
            assertThat(view.body().items().size()).isEqualTo((int)view.revision());
        }
    }
}

