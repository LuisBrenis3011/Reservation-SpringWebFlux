package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import com.brenis.SpringWebFlux.support.ReservationConfirmationSupport;
import com.brenis.SpringWebFlux.services.definitions.ReservationCrudService;
import static org.assertj.core.api.Assertions.*;
class ReservationLegacyCutoverIT extends ReservationConfirmationSupport {
    @Autowired ReservationCrudService legacy;
    @Test void escritorAntiguoConcurrenteNoEludeCorte(){
        var results=reactor.core.publisher.Flux.merge(legacy.createReservation(null).map(value->(Object)value).materialize(),
            confirm("client","new",2).map(value->(Object)value).materialize()).collectList().block();
        assertThat(results.stream().filter(reactor.core.publisher.Signal::hasValue).count()).isEqualTo(1);
        assertThat(results.stream().filter(reactor.core.publisher.Signal::isOnError).findFirst().orElseThrow().getThrowable()).hasMessageContaining("LEGACY_WRITES_RETIRED");
        assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
    }
    @Test void politicaInvalidaBloqueaAmbasViasSinGuardarNada(){
        mongo.updateFirst(org.springframework.data.mongodb.core.query.Query.query(org.springframework.data.mongodb.core.query.Criteria.where("_id").is(
            com.brenis.SpringWebFlux.collections.ReservationPolicyCollection.ID)),new org.springframework.data.mongodb.core.query.Update().set("legacyWritesRetired",false),"reservation_policy").block();
        assertThatThrownBy(()->legacy.createReservation(null).block()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");
        assertThatThrownBy(()->confirm("client","new",2).block()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");
        assertThat(revision()).isZero();assertThat(receiptCount()).isZero();
    }
    @Test void barreraRetiraConsumidoresInternosAntesDeDeserializarModelos(){
        assertThatThrownBy(()->legacy.createReservation(null).block()).hasMessageContaining("LEGACY_WRITES_RETIRED");
        assertThatThrownBy(()->legacy.updateReservation(java.util.UUID.randomUUID(),null).block()).hasMessageContaining("LEGACY_WRITES_RETIRED");
        assertThatThrownBy(()->legacy.deleteReservation(java.util.UUID.randomUUID()).block()).hasMessageContaining("LEGACY_WRITES_RETIRED");
        assertThat(revision()).isZero();assertThat(receiptCount()).isZero();
    }
}
