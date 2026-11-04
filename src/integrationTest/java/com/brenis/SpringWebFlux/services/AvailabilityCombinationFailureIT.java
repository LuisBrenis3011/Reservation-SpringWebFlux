package com.brenis.SpringWebFlux.services;

import com.brenis.SpringWebFlux.support.AvailabilityCombinationIntegrationSupport;
import com.brenis.SpringWebFlux.services.definitions.ReservationCommitmentReader;
import com.brenis.SpringWebFlux.repositories.LegacyReservationCommitmentAdapter;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.context.annotation.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.ContextConfiguration;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;
import java.time.*;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

@ContextConfiguration(classes=AvailabilityCombinationFailureIT.FailureConfiguration.class)
class AvailabilityCombinationFailureIT extends AvailabilityCombinationIntegrationSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false) static class FailureConfiguration {
        @Bean @Primary ControlledReader controlledCombinationReader(LegacyReservationCommitmentAdapter delegate) { return new ControlledReader(delegate); }
    }
    static class ControlledReader implements ReservationCommitmentReader {
        final LegacyReservationCommitmentAdapter delegate;
        String mode="";
        ControlledReader(LegacyReservationCommitmentAdapter delegate) { this.delegate=delegate; }
        @Override public Mono<CommitmentSummary> read(UUID owner,Instant now) {
            if(mode.equals("fallo")) return Mono.error(new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Fallo de prueba"));
            if(mode.equals("demora")) return Mono.<CommitmentSummary>never().timeout(Duration.ofMillis(20))
                    .onErrorMap(e -> new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Demora de prueba",e));
            return delegate.read(owner,now);
        }
    }
    @Autowired ControlledReader reader;
    @ParameterizedTest @ValueSource(strings={"fallo","demora"})
    void esc0213_0214_rechazoTemporalNoDejaEscriturasYPermiteMismaClave(String mode) {
        var tablesBefore=repository.findAllByRestaurantId(restaurant).collectList().block();
        long version=revision(), receipts=receiptCount();
        reader.mode=mode;
        try {
            StepVerifier.create(combine("retry",List.of(first,second)))
                    .expectErrorMatches(e -> e.getMessage().contains("COMMITMENT_CHECK_UNAVAILABLE")).verify();
        } finally { reader.mode=""; }
        assertThat(storedCombinations()).isEmpty();
        assertThat(revision()).isEqualTo(version); assertThat(receiptCount()).isEqualTo(receipts);
        assertThat(repository.findAllByRestaurantId(restaurant).collectList().block()).isEqualTo(tablesBefore);
        var result=combine("retry",List.of(first,second)).block();
        assertThat(result.body().capacity()).isEqualTo(6);
        assertThat(storedCombinations()).hasSize(1);
        assertThat(revision()).isEqualTo(version+1); assertThat(receiptCount()).isEqualTo(receipts+1);
    }
    @ParameterizedTest @CsvSource({"fallo,false","fallo,true","demora,false","demora,true"})
    void esc0213_0214_putInclusoIdenticoCompruebaReservasYRevierteAnteFallo(String mode,boolean identical) {
        UUID third=create("third","Tres",3).block().body().id();
        var target=combine("target",List.of(first,second)).block().body();
        var before=combinationRepository.findByIdAndRestaurantId(target.id(),restaurant).block();
        var tablesBefore=repository.findAllByRestaurantId(restaurant).collectList().block();
        long version=revision(), receipts=receiptCount();
        var next=identical?List.of(second,first):List.of(first,third);
        reader.mode=mode;
        try {
            StepVerifier.create(replace(target.id(),"retry-put",next,version))
                    .expectErrorMatches(e -> e.getMessage().contains("COMMITMENT_CHECK_UNAVAILABLE")).verify();
        } finally { reader.mode=""; }
        assertThat(combinationRepository.findByIdAndRestaurantId(target.id(),restaurant).block()).isEqualTo(before);
        assertThat(repository.findAllByRestaurantId(restaurant).collectList().block()).isEqualTo(tablesBefore);
        assertThat(revision()).isEqualTo(version); assertThat(receiptCount()).isEqualTo(receipts);
        var accepted=replace(target.id(),"retry-put",next,version).block();
        assertThat(accepted.body().id()).isEqualTo(target.id());
        assertThat(accepted.body().capacity()).isEqualTo(identical?6:7);
        assertThat(revision()).isEqualTo(version+1); assertThat(receiptCount()).isEqualTo(receipts+1);
        assertThat(storedCombinations()).hasSize(1);
    }
}
