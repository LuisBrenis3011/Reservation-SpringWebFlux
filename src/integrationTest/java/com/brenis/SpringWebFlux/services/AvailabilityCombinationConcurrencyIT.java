package com.brenis.SpringWebFlux.services;

import com.brenis.SpringWebFlux.support.AvailabilityCombinationIntegrationSupport;
import com.brenis.SpringWebFlux.support.AvailabilityMongoFixture;
import com.brenis.SpringWebFlux.collections.*;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.mappers.TableCombinationMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.bson.Document;
import reactor.core.publisher.*;
import reactor.test.StepVerifier;
import java.time.Duration;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class AvailabilityCombinationConcurrencyIT extends AvailabilityCombinationIntegrationSupport {
    @Autowired TableCombinationMapper mapper;
    @Test void esc0210_altasConcurrentesConOrdenDistintoNoDuplicanConjunto() {
        var results=Mono.zip(combine("forward",List.of(first,second)).materialize(),
                combine("reverse",List.of(second,first)).materialize()).block(Duration.ofSeconds(15));
        var outcomes=List.of(results.getT1(),results.getT2());
        assertThat(outcomes.stream().filter(Signal::hasValue).count()).isEqualTo(1);
        var failure=outcomes.stream().filter(Signal::isOnError).findFirst().orElseThrow().getThrowable();
        assertThat(failure).isInstanceOf(AvailabilityException.class);
        assertThat(((AvailabilityException)failure).code()).isIn("DUPLICATE_COMBINATION","DEPENDENCY_UNAVAILABLE");
        assertThat(storedCombinations()).hasSize(1);
        assertThat(revision()).isEqualTo(3); assertThat(receiptCount()).isEqualTo(3);
        // El agotamiento acotado no se oculta aumentando reintentos. Terminada la
        // competidora, la misma solicitud perdedora debe reconocer el duplicado.
        var retry=results.getT1().isOnError()?combine("forward",List.of(first,second)):combine("reverse",List.of(second,first));
        StepVerifier.create(retry).expectErrorMatches(e -> e.getMessage().contains("DUPLICATE_COMBINATION")).verify();
        assertThat(revision()).isEqualTo(3); assertThat(receiptCount()).isEqualTo(3);
    }
    @Test void indiceUnicoProtegeAunqueSeOmitaElServicio() {
        var created=combine("first",List.of(first,second)).block().body();
        var row=combinationRepository.findByIdAndRestaurantId(created.id(),restaurant).block();
        StepVerifier.create(combinationRepository.insert(new TableCombinationCollection(UUID.randomUUID(),restaurant,
                List.of(second,first),row.memberKey()))).expectError(DuplicateKeyException.class).verify();
        assertThat(storedCombinations()).hasSize(1); assertThat(revision()).isEqualTo(3);
    }
    @Test void replayTipadoTrasCambiarCapacidadConservaRespuestaHistoricaSinOtroWrite() {
        var original=combine("saved",List.of(first,second)).block();
        patch(first,"capacity",new TablePatchRequest(null,5L),revision()).block();
        long before=revision(), receipts=receiptCount();
        var replay=combine("saved",List.of(first,second)).block();
        assertThat(replay).isEqualTo(original);
        assertThat(replay.body().capacity()).isEqualTo(6);
        assertThat(combinations.read(manager,restaurant,replay.body().id()).block().body().capacity()).isEqualTo(7);
        StepVerifier.create(combine("saved",List.of(second,first)))
                .expectErrorMatches(e -> e.getMessage().contains("IDEMPOTENCY_CONFLICT")).verify();
        assertThat(revision()).isEqualTo(before); assertThat(receiptCount()).isEqualTo(receipts);
        assertThat(storedCombinations()).hasSize(1);
    }
    @Test void esc0209_snapshotNoMezclaRevisionYCapacidadesDuranteCambioDeMesa() {
        var saved=combine("base",List.of(first,second)).block().body();
        long version=revision();
        Sinks.One<Void> inside=Sinks.one(), changed=Sinks.one();
        var reading=coordinator.readSnapshot(restaurant,ctx ->
                combinationRepository.findByIdAndRestaurantId(saved.id(),restaurant).flatMap(row -> {
                    inside.tryEmitEmpty();
                    return changed.asMono().then(repository.findAllByRestaurantId(restaurant).collectList())
                            .map(members -> mapper.response(row,members,ctx.revision()));
                }));
        var writing=inside.asMono().then(patch(first,"during-read",new TablePatchRequest(null,5L),version))
                .doFinally(signal -> changed.tryEmitEmpty());
        var result=Mono.zip(reading,writing).block(Duration.ofSeconds(15));
        assertThat(result.getT1().body().capacity()).isEqualTo(6);
        assertThat(result.getT1().revision()).isEqualTo(version);
        assertThat(combinations.read(manager,restaurant,saved.id()).block().body().capacity()).isEqualTo(7);
        assertThat(revision()).isEqualTo(version+1);
    }
    @Test void putExcluyeSuIdentidadPeroRechazaOtroConjuntoYaRegistrado() {
        UUID third=create("third","Tres",3).block().body().id();
        var one=combine("one",List.of(first,second)).block().body();
        var two=combine("two",List.of(first,third)).block().body();
        var before=storedCombinations();
        long version=revision(), receipts=receiptCount();
        StepVerifier.create(replace(one.id(),"collision",List.of(third,first),version))
                .expectErrorMatches(e -> e.getMessage().contains("DUPLICATE_COMBINATION")).verify();
        assertThat(storedCombinations()).isEqualTo(before);
        assertThat(revision()).isEqualTo(version); assertThat(receiptCount()).isEqualTo(receipts);
        var same=replace(two.id(),"own-identity",List.of(third,first),version).block();
        assertThat(same.body().id()).isEqualTo(two.id());
        assertThat(same.body().capacity()).isEqualTo(7);
        assertThat(revision()).isEqualTo(version+1); assertThat(receiptCount()).isEqualTo(receipts+1);
    }
    @Test void putRechazaReferenciasInvalidasYRecursoAjenoSinEscriturasParciales() {
        var target=combine("target",List.of(first,second)).block().body();
        UUID other=UUID.randomUUID(), foreign=UUID.randomUUID();
        mongo.save(RestaurantCollection.builder().id(other).name("Otro").build()).block();
        repository.insert(new TableCollection(foreign,other,"Ajena","ajena",4)).block();
        var before=storedCombinations();
        long version=revision(), receipts=receiptCount();
        int attempt=0;
        for(var ids:List.of(List.of(first),List.of(first,first),List.of(first,foreign),List.of(first,UUID.randomUUID()))) {
            StepVerifier.create(replace(target.id(),"invalid-put-"+(attempt++),ids,version))
                    .expectErrorMatches(e -> e.getMessage().contains("VALIDATION_ERROR")).verify();
        }
        // Un ID de combinacion de otro restaurante no se busca globalmente.
        UUID foreignCombination=UUID.randomUUID(), foreignSecond=UUID.randomUUID();
        repository.insert(new TableCollection(foreignSecond,other,"Otra","otra",2)).block();
        var foreignIds=List.of(foreign,foreignSecond).stream().sorted(Comparator.comparing(UUID::toString)).toList();
        combinationRepository.insert(new TableCombinationCollection(foreignCombination,other,foreignIds,
                String.join(",",foreignIds.stream().map(UUID::toString).toList()))).block();
        StepVerifier.create(replace(foreignCombination,"foreign-put",List.of(first,second),version))
                .expectErrorMatches(e -> e.getMessage().contains("NOT_FOUND")).verify();
        StepVerifier.create(combinations.replace(manager,other,target.id(),request(List.of(first,second)),
                new com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata("forbidden","forbidden",version,200,null)))
                .expectErrorMatches(e -> e.getMessage().contains("FORBIDDEN")).verify();
        assertThat(storedCombinations()).isEqualTo(before);
        assertThat(revision()).isEqualTo(version); assertThat(receiptCount()).isEqualTo(receipts);
        assertThat(mongo.findById(other,Document.class,"restaurant_operations").block()).isNull();
    }
    @Test void putReplayPrecedeIfMatchYConservaRespuestaOriginalTrasOtroWrite() {
        var target=combine("target",List.of(first,second)).block().body();
        long version=revision();
        StepVerifier.create(replace(target.id(),"stale",List.of(first,second),version-1))
                .expectErrorMatches(e -> e.getMessage().contains("REVISION_MISMATCH")).verify();
        assertThat(revision()).isEqualTo(version);
        var original=replace(target.id(),"saved-put",List.of(second,first),version).block();
        patch(first,"table-capacity",new TablePatchRequest(null,5L),revision()).block();
        long current=revision(), receipts=receiptCount();
        var replay=replace(target.id(),"saved-put",List.of(second,first),version).block();
        assertThat(replay).isEqualTo(original);
        assertThat(replay.httpStatus()).isEqualTo(200); assertThat(replay.location()).isNull();
        assertThat(replay.body().capacity()).isEqualTo(6);
        assertThat(combinations.read(manager,restaurant,target.id()).block().body().capacity()).isEqualTo(7);
        StepVerifier.create(replace(target.id(),"saved-put",List.of(first,second),version))
                .expectErrorMatches(e -> e.getMessage().contains("IDEMPOTENCY_CONFLICT")).verify();
        StepVerifier.create(replace(target.id(),"saved-put",List.of(second,first),current))
                .expectErrorMatches(e -> e.getMessage().contains("IDEMPOTENCY_CONFLICT")).verify();
        StepVerifier.create(replace(target.id(),"new-stale",List.of(second,first),version))
                .expectErrorMatches(e -> e.getMessage().contains("REVISION_MISMATCH")).verify();
        assertThat(revision()).isEqualTo(current); assertThat(receiptCount()).isEqualTo(receipts);
        assertThat(storedCombinations()).hasSize(1);
    }
    @Test void putConcurrentesNoConvergenEnDosConjuntosDuplicados() {
        UUID third=create("third","Tres",3).block().body().id();
        UUID fourth=create("fourth","Cuatro",1).block().body().id();
        var one=combine("one",List.of(first,second)).block().body();
        var two=combine("two",List.of(first,third)).block().body();
        long version=revision(), receipts=receiptCount();
        var wanted=List.of(first,fourth);
        var result=Mono.zip(replace(one.id(),"race-one",wanted,version).materialize(),
                replace(two.id(),"race-two",wanted,version).materialize()).block(Duration.ofSeconds(15));
        var outcomes=List.of(result.getT1(),result.getT2());
        assertThat(outcomes.stream().filter(Signal::hasValue).count()).isEqualTo(1);
        var failure=outcomes.stream().filter(Signal::isOnError).findFirst().orElseThrow().getThrowable();
        assertThat(failure).isInstanceOf(AvailabilityException.class);
        assertThat(((AvailabilityException)failure).code()).isIn("REVISION_MISMATCH","DEPENDENCY_UNAVAILABLE");
        var canonical=wanted.stream().sorted(Comparator.comparing(UUID::toString)).toList();
        assertThat(storedCombinations()).hasSize(2).extracting(TableCombinationCollection::id)
                .containsExactlyInAnyOrder(one.id(),two.id());
        assertThat(storedCombinations().stream().filter(row -> row.tableIds().equals(canonical)).count()).isEqualTo(1);
        assertThat(revision()).isEqualTo(version+1); assertThat(receiptCount()).isEqualTo(receipts+1);
        UUID losingId=result.getT1().isOnError()?one.id():two.id();
        StepVerifier.create(replace(losingId,"after-race",wanted,revision()))
                .expectErrorMatches(e -> e.getMessage().contains("DUPLICATE_COMBINATION")).verify();
        assertThat(revision()).isEqualTo(version+1); assertThat(receiptCount()).isEqualTo(receipts+1);
    }
    @Test void confirmacionConcurrenteNoPermiteCambiarCombinacionComprometida() {
        UUID third=create("third","Tres",3).block().body().id();
        var target=combine("target",List.of(first,second)).block().body();
        var reservation=AvailabilityMongoFixture.confirmedSnapshot(restaurant,UUID.randomUUID(),first,
                clock.instant().plusSeconds(600),clock.instant().plusSeconds(3600));
        reservation.put("combinationId",target.id());
        reservation.put("tableIds",List.of(first,second));
        reservation.put("tableSnapshots",List.of(new Document("tableId",first).append("label","Uno").append("capacity",4L),
                new Document("tableId",second).append("label","Dos").append("capacity",2L)));
        var before=combinationRepository.findByIdAndRestaurantId(target.id(),restaurant).block();
        long version=revision(), receipts=receiptCount();
        Sinks.One<Void> inside=Sinks.one();
        // Fixture de confirmacion bajo la frontera real; no se crea una API de reservas.
        var confirm=coordinator.writeLegacy(restaurant,ctx -> {
            inside.tryEmitEmpty();
            return Mono.delay(Duration.ofMillis(200)).then(mongo.insert(reservation,"reservations"));
        });
        var change=inside.asMono().then(replace(target.id(),"during-confirm",List.of(first,third),version));
        var outcome=Mono.zip(confirm.materialize(),change.materialize()).block(Duration.ofSeconds(15));
        assertThat(outcome.getT1().hasValue()).isTrue();
        assertThat(outcome.getT2().isOnError()).isTrue();
        assertThat(outcome.getT2().getThrowable()).isInstanceOf(AvailabilityException.class);
        assertThat(((AvailabilityException)outcome.getT2().getThrowable()).code()).isIn("REVISION_MISMATCH","DEPENDENCY_UNAVAILABLE");
        var history=mongo.findById(reservation.get("_id"),Document.class,"reservations").block();
        StepVerifier.create(replace(target.id(),"after-confirm",List.of(first,third),revision()))
                .expectErrorMatches(e -> e.getMessage().contains("PROTECTED_RESERVATION")).verify();
        assertThat(combinationRepository.findByIdAndRestaurantId(target.id(),restaurant).block()).isEqualTo(before);
        assertThat(mongo.findById(reservation.get("_id"),Document.class,"reservations").block()).isEqualTo(history);
        assertThat(revision()).isEqualTo(version+1); assertThat(receiptCount()).isEqualTo(receipts);
    }
}
