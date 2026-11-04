package com.brenis.SpringWebFlux.services;

import com.brenis.SpringWebFlux.support.AvailabilityCombinationIntegrationSupport;
import com.brenis.SpringWebFlux.collections.*;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import reactor.test.StepVerifier;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class AvailabilityCombinationReadTests extends AvailabilityCombinationIntegrationSupport {
    @Test void esc0205_altaYConsultasSumanSeisSinDuplicarCapacidadFisica() {
        var created=combine("combination",List.of(first,second)).block();
        assertThat(created.httpStatus()).isEqualTo(201);
        assertThat(created.location()).isEqualTo("/catalog/restaurants/"+restaurant+"/table-combinations/"+created.body().id());
        var read=combinations.read(manager,restaurant,created.body().id()).block();
        var list=combinations.list(manager,restaurant).block();
        assertThat(read.body()).isEqualTo(created.body());
        assertThat(read.body().capacity()).isEqualTo(6);
        assertThat(read.body().tableIds()).containsExactlyInAnyOrder(first,second);
        assertThat(list.body().items()).containsExactly(read.body());
        assertThat(list.body().revision()).isEqualTo(revision());
        assertThat(tables.list(manager,restaurant).block().body().totalCapacity()).isEqualTo(6);
        Document raw=mongo.findById(read.body().id(),Document.class,"table_combinations").block();
        assertThat(raw).doesNotContainKey("capacity");
        assertThat(raw.getString("memberKey")).isNotBlank();
    }
    @Test void esc0206_capacidadVigenteEnDosCombinacionesQueCompartenMesa() {
        UUID third=create("third","Tres",3).block().body().id();
        var one=combine("one",List.of(first,second)).block().body();
        var two=combine("two",List.of(first,third)).block().body();
        patch(first,"capacity",new TablePatchRequest(null,5L),revision()).block();
        var view=combinations.list(manager,restaurant).block();
        assertThat(view.body().items()).hasSize(2).allSatisfy(item -> assertThat(item.revision()).isEqualTo(view.revision()));
        assertThat(combinations.read(manager,restaurant,one.id()).block().body().capacity()).isEqualTo(7);
        assertThat(combinations.read(manager,restaurant,two.id()).block().body().capacity()).isEqualTo(8);
        assertThat(tables.list(manager,restaurant).block().body().totalCapacity()).isEqualTo(10);
        assertThat(revision()).isEqualTo(6);
        assertThat(storedCombinations()).hasSize(2);
    }
    @Test void coleccionVaciaYLecturasNoIncrementanRevision() {
        assertThat(combinations.list(manager,restaurant).block().body().items()).isEmpty();
        StepVerifier.create(combinations.read(manager,restaurant,UUID.randomUUID()))
                .expectErrorMatches(e -> e.getMessage().contains("NOT_FOUND")).verify();
        assertThat(revision()).isEqualTo(2);
        assertThat(receiptCount()).isEqualTo(2);
    }
    @Test void esc0202_0204_miembroInexistenteOAjenoRechazaTodoSinFiltrarDatos() {
        UUID other=UUID.randomUUID(), foreign=UUID.randomUUID();
        mongo.save(RestaurantCollection.builder().id(other).name("Otro").build()).block();
        repository.insert(new TableCollection(foreign,other,"Ajena","ajena",9)).block();
        for(UUID missing:List.of(foreign,UUID.randomUUID())) {
            StepVerifier.create(combine("invalid-"+missing,List.of(first,missing)))
                    .expectErrorMatches(e -> e.getMessage().contains("VALIDATION_ERROR")).verify();
        }
        for(var invalid:List.of(List.of(first),List.of(first,first))) {
            StepVerifier.create(combine("invalid-members-"+invalid.size(),invalid))
                    .expectErrorMatches(e -> e.getMessage().contains("VALIDATION_ERROR")).verify();
        }
        assertThat(storedCombinations()).isEmpty();
        assertThat(revision()).isEqualTo(2); assertThat(receiptCount()).isEqualTo(2);
        assertThat(repository.findById(foreign).block().capacity()).isEqualTo(9);
    }
    @Test void aislamientoDeCombinacionYAutorizacionPreviaAMetadatos() {
        var own=combine("own",List.of(first,second)).block().body();
        UUID other=UUID.randomUUID(), foreign=UUID.randomUUID();
        mongo.save(RestaurantCollection.builder().id(other).name("Otro").build()).block();
        UUID foreignOne=UUID.randomUUID(), foreignTwo=UUID.randomUUID();
        repository.insert(new TableCollection(foreignOne,other,"Uno","uno",4)).block();
        repository.insert(new TableCollection(foreignTwo,other,"Dos","dos",2)).block();
        var foreignIds=List.of(foreignOne,foreignTwo).stream().sorted(Comparator.comparing(UUID::toString)).toList();
        combinationRepository.insert(new TableCombinationCollection(foreign,other,foreignIds,
                String.join(",",foreignIds.stream().map(UUID::toString).toList()))).block();
        StepVerifier.create(combinations.read(manager,restaurant,foreign))
                .expectErrorMatches(e -> e.getMessage().contains("NOT_FOUND")).verify();
        StepVerifier.create(combinations.list(manager,other))
                .expectErrorMatches(e -> e.getMessage().contains("FORBIDDEN")).verify();
        assertThat(combinations.list(manager,restaurant).block().body().items()).extracting(row -> row.id()).containsExactly(own.id());
        assertThat(mongo.findById(other,Document.class,"restaurant_operations").block()).isNull();
    }
    @Test void referenciaPersistidaAusenteNoProduceCapacidadParcial() {
        var combo=combine("base",List.of(first,second)).block().body();
        // Fixture corrupta solo en Mongo efimero; no existe DELETE productivo de mesas.
        repository.deleteById(second).block();
        StepVerifier.create(combinations.read(manager,restaurant,combo.id()))
                .expectErrorMatches(e -> e.getMessage().contains("COMMITMENT_CHECK_UNAVAILABLE")).verify();
        StepVerifier.create(combinations.list(manager,restaurant))
                .expectErrorMatches(e -> e.getMessage().contains("COMMITMENT_CHECK_UNAVAILABLE")).verify();
        assertThat(revision()).isEqualTo(3); assertThat(receiptCount()).isEqualTo(3);
    }
}
