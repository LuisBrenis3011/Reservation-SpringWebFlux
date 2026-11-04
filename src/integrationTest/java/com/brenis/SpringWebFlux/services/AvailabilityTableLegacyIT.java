package com.brenis.SpringWebFlux.services;

import com.brenis.SpringWebFlux.support.*;
import com.brenis.SpringWebFlux.collections.*;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import reactor.test.StepVerifier;
import java.util.*;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.data.mongodb.core.query.Query.query;
import static org.springframework.data.mongodb.core.query.Criteria.where;

class AvailabilityTableLegacyIT extends AvailabilityTableIntegrationSupport {
    @ParameterizedTest @CsvSource({"false,false","true,false","false,true","true,true"})
    void esc0119_0120_legadoPermiteRenombradoPeroNoCambioDeCapacidad(boolean capacityPresent,boolean binaryOwner) {
        var table=create("initial","Existente",4).block().body();
        var legacy=AvailabilityMongoFixture.unresolvedLegacy(restaurant,binaryOwner,"CONFIRMED");
        mongo.insert(legacy,"reservations").block();
        var before=mongo.findById(legacy.get("_id"),Document.class,"reservations").block();
        var renamed=patch(table.id(),"rename",new TablePatchRequest("Ventana",capacityPresent?4L:null),revision()).block();
        assertThat(renamed.body().id()).isEqualTo(table.id());
        assertThat(renamed.body().label()).isEqualTo("Ventana");
        assertThat(renamed.body().capacity()).isEqualTo(4);
        long version=revision(), receipts=receiptCount();
        StepVerifier.create(patch(table.id(),"capacity",new TablePatchRequest("No debe guardarse",6L),version))
                .expectErrorMatches(e -> e.getMessage().contains("LEGACY_RESERVATION_BLOCK")).verify();
        var view=tables.list(manager,restaurant).block();
        assertThat(view.body().items()).hasSize(1);
        assertThat(view.body().items().getFirst().label()).isEqualTo("Ventana");
        assertThat(view.body().totalCapacity()).isEqualTo(4);
        assertThat(revision()).isEqualTo(version);
        assertThat(receiptCount()).isEqualTo(receipts);
        assertThat(mongo.findById(legacy.get("_id"),Document.class,"reservations").block()).isEqualTo(before);
    }
    @Test void esc0120_legadoBloqueaAltaPeroNoConsultasNiBorraDatos() {
        create("initial","Existente",4).block();
        var legacy=AvailabilityMongoFixture.unresolvedLegacy(restaurant,false,"CONFIRMED");
        mongo.insert(legacy,"reservations").block();
        Document stored=mongo.findById(legacy.get("_id"),Document.class,"reservations").block();
        StepVerifier.create(create("blocked","Nueva",2))
                .expectErrorMatches(e -> e.getMessage().contains("LEGACY_RESERVATION_BLOCK")).verify();
        var view=tables.list(manager,restaurant).block();
        assertThat(view.body().items()).hasSize(1);
        assertThat(view.body().totalCapacity()).isEqualTo(4);
        assertThat(revision()).isEqualTo(1);
        assertThat(receiptCount()).isEqualTo(1);
        assertThat(mongo.findById(legacy.get("_id"),Document.class,"reservations").block()).isEqualTo(stored);
    }
    @Test void esc0105_0106_0115_0116_totalFisicoIgnoraAforoYCombinacionesYAislaRestaurante() {
        UUID other=UUID.randomUUID();
        mongo.save(RestaurantCollection.builder().id(other).capacity(20).name("Otro").build()).block();
        mongo.insert(new TableCollection(UUID.randomUUID(),other,"Uno","uno",100)).block();
        var empty=tables.list(manager,restaurant).block();
        assertThat(empty.body().items()).isEmpty();
        assertThat(empty.body().totalCapacity()).isZero();
        var first=create("one","Uno",4).block();
        var second=create("two","Dos",2).block();
        mongo.insert(new Document("_id",UUID.randomUUID()).append("restaurantId",restaurant)
                .append("tableIds",List.of(first.body().id(),second.body().id())).append("capacity",6L),"table_combinations").block();
        var view=tables.list(manager,restaurant).block();
        assertThat(view.body().totalCapacity()).isEqualTo(6);
        assertThat(view.body().items()).hasSize(2);
        assertThat(view.revision()).isEqualTo(2);
        assertThat(mongo.findById(restaurant,RestaurantCollection.class).block().getCapacity()).isEqualTo(5);
        var found=tables.read(manager,restaurant,first.body().id()).block();
        assertThat(found.body().id()).isEqualTo(first.body().id());
        assertThat(found.body().restaurantId()).isEqualTo(restaurant);
        assertThat(found.body().label()).isEqualTo("Uno");
        assertThat(found.body().capacity()).isEqualTo(4);
        assertThat(found.body().revision()).isEqualTo(view.revision());
        UUID foreign=repository.findAllByRestaurantId(other).blockFirst().id();
        StepVerifier.create(tables.read(manager,restaurant,foreign))
                .expectErrorMatches(e -> e.getMessage().contains("NOT_FOUND")).verify();
        assertThat(revision()).isEqualTo(2);
    }
}

