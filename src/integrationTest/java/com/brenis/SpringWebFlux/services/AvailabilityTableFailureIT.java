package com.brenis.SpringWebFlux.services;

import com.brenis.SpringWebFlux.support.AvailabilityTableIntegrationSupport;
import com.brenis.SpringWebFlux.services.definitions.ReservationCommitmentReader;
import com.brenis.SpringWebFlux.repositories.LegacyReservationCommitmentAdapter;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.context.annotation.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.ContextConfiguration;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.data.mongodb.core.query.Query.query;
import static org.springframework.data.mongodb.core.query.Criteria.where;

@ContextConfiguration(classes=AvailabilityTableFailureIT.FailureConfiguration.class)
class AvailabilityTableFailureIT extends AvailabilityTableIntegrationSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false)
    static class FailureConfiguration {
        @Bean @Primary ControlledReader controlledReader(LegacyReservationCommitmentAdapter delegate) {
            return new ControlledReader(delegate);
        }
    }
    static class ControlledReader implements ReservationCommitmentReader {
        final LegacyReservationCommitmentAdapter delegate;
        String mode="";
        int calls;
        ControlledReader(LegacyReservationCommitmentAdapter delegate) { this.delegate=delegate; }
        @Override public Mono<CommitmentSummary> read(java.util.UUID owner,java.time.Instant now) {
            calls++;
            if(mode.equals("fallo")) return Mono.error(new AvailabilityException(
                    "COMMITMENT_CHECK_UNAVAILABLE","Fallo inyectado del lector"));
            if(mode.equals("demora")) return Mono.<CommitmentSummary>never()
                    .timeout(java.time.Duration.ofMillis(20))
                    .onErrorMap(e -> new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Demora inyectada",e));
            return delegate.read(owner,now);
        }
    }
    @Autowired ControlledReader reader;
    @ParameterizedTest @ValueSource(strings={"fallo","demora"})
    void esc0117_0118_falloDeComprobacionRevierteYPermiteMismaClave(String mode) {
        create("baseline","Anterior",4).block();
        var before=mongo.find(query(where("restaurantId").is(restaurant)),Document.class,"restaurant_tables").collectList().block();
        long version=revision(), receipts=receiptCount();
        // Sustituir solo la dependencia fallida: coordinador, Mongo y transacciones son reales.
        reader.mode=mode;
        try {
            StepVerifier.create(create("retry","Nueva",2))
                    .expectErrorMatches(e -> e.getMessage().contains("COMMITMENT_CHECK_UNAVAILABLE")).verify();
        } finally {
            reader.mode="";
        }
        assertThat(revision()).isEqualTo(version);
        assertThat(receiptCount()).isEqualTo(receipts);
        assertThat(mongo.find(query(where("restaurantId").is(restaurant)),Document.class,"restaurant_tables").collectList().block())
                .isEqualTo(before);
        var accepted=create("retry","Nueva",2).block();
        assertThat(accepted.body().capacity()).isEqualTo(2);
        assertThat(revision()).isEqualTo(version+1);
        assertThat(receiptCount()).isEqualTo(receipts+1);
    }
    @Test void desbordamientoRechazaAltaCompletaSinConsumirClaveNiRevision() {
        create("max","Grande",Long.MAX_VALUE).block();
        StepVerifier.create(create("overflow","Pequeña",1))
                .expectErrorMatches(e -> e.getMessage().contains("VALIDATION_ERROR")).verify();
        assertThat(revision()).isEqualTo(1);
        assertThat(receiptCount()).isEqualTo(1);
        assertThat(repository.findAllByRestaurantId(restaurant).collectList().block()).hasSize(1);
    }
    @ParameterizedTest @ValueSource(strings={"fallo","demora"})
    void esc0117_0118_patchRechazadoConservaMesaRevisionYClave(String mode) {
        var table=create("baseline","Anterior",4).block().body();
        var before=repository.findByIdAndRestaurantId(table.id(),restaurant).block();
        long version=revision(), receipts=receiptCount();
        var request=new TablePatchRequest("Nueva",6L);
        reader.mode=mode;
        try {
            StepVerifier.create(patch(table.id(),"retry-patch",request,version))
                    .expectErrorMatches(e -> e.getMessage().contains("COMMITMENT_CHECK_UNAVAILABLE")).verify();
        } finally { reader.mode=""; }
        assertThat(repository.findByIdAndRestaurantId(table.id(),restaurant).block()).isEqualTo(before);
        assertThat(revision()).isEqualTo(version);
        assertThat(receiptCount()).isEqualTo(receipts);
        var accepted=patch(table.id(),"retry-patch",request,version).block();
        assertThat(accepted.body().capacity()).isEqualTo(6);
        assertThat(accepted.body().label()).isEqualTo("Nueva");
        assertThat(revision()).isEqualTo(version+1);
        assertThat(receiptCount()).isEqualTo(receipts+1);
    }
    @ParameterizedTest @ValueSource(booleans={false,true})
    void renombradoFuncionaConLectorCaidoInclusoConCapacidadPresenteIgual(boolean capacityPresent) {
        var table=create("baseline","Anterior",4).block().body();
        int calls=reader.calls;
        reader.mode="fallo";
        try {
            var renamed=patch(table.id(),"rename",new TablePatchRequest("Ventana",capacityPresent?4L:null),revision()).block();
            assertThat(renamed.body().label()).isEqualTo("Ventana");
            assertThat(renamed.body().capacity()).isEqualTo(4);
            assertThat(reader.calls).isEqualTo(calls);
        } finally { reader.mode=""; }
        assertThat(revision()).isEqualTo(2);
        assertThat(receiptCount()).isEqualTo(2);
    }
    @Test void overflowDePatchRevierteAmbosCamposSinConsumirRevision() {
        var table=create("first","Primera",4).block().body();
        create("max","Grande",Long.MAX_VALUE-4).block();
        var before=repository.findByIdAndRestaurantId(table.id(),restaurant).block();
        StepVerifier.create(patch(table.id(),"overflow-patch",new TablePatchRequest("Cambio",5L),revision()))
                .expectErrorMatches(e -> e.getMessage().contains("VALIDATION_ERROR")).verify();
        assertThat(repository.findByIdAndRestaurantId(table.id(),restaurant).block()).isEqualTo(before);
        assertThat(revision()).isEqualTo(2);
        assertThat(receiptCount()).isEqualTo(2);
    }
}

