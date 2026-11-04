package com.brenis.SpringWebFlux.services;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import com.brenis.SpringWebFlux.support.ReservationIdentityFixture;
import com.brenis.SpringWebFlux.services.impls.ReservationAccessPolicy;
import com.brenis.SpringWebFlux.services.impls.ReservationAssignmentPolicy;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection.TableSnapshot;
import com.brenis.SpringWebFlux.enums.ManagedReservationStatus;
import com.brenis.SpringWebFlux.validators.ReservationIntegrityValidator;
import static org.assertj.core.api.Assertions.*;

class ReservationFoundationPolicyTests {
    @Test void falloDeLecturaDePoliticaNuncaAutorizaEscrituras(){
        var mongo=org.mockito.Mockito.mock(org.springframework.data.mongodb.core.ReactiveMongoTemplate.class);
        org.mockito.Mockito.when(mongo.findById(com.brenis.SpringWebFlux.collections.ReservationPolicyCollection.ID,
            org.bson.Document.class,"reservation_policy")).thenReturn(reactor.core.publisher.Mono.error(new IllegalStateException("offline")));
        var barrier=new com.brenis.SpringWebFlux.services.impls.LegacyReservationWriteBarrier(mongo);
        reactor.test.StepVerifier.create(barrier.check()).expectErrorMatches(error->error instanceof com.brenis.SpringWebFlux.exceptions.AvailabilityException known
            &&known.code().equals("DEPENDENCY_UNAVAILABLE")).verify();
    }
    @Test void doblePerfilNoConvierteAlEncargadoEnTitularDeOtroCliente(){
        Clock clock=Clock.fixed(Instant.parse("2026-11-01T10:00:00Z"),ZoneOffset.UTC);UUID owner=UUID.randomUUID();
        var policy=new ReservationAccessPolicy();
        var actor=policy.actor(new JwtAuthenticationToken(ReservationIdentityFixture.dual("client",owner,clock),List.of(new SimpleGrantedAuthority("ROLE_CUSTOMER"))));
        assertThat(actor.isCustomer()).isTrue();assertThat(actor.manages(owner)).isTrue();
        var manager=policy.actor(new JwtAuthenticationToken(ReservationIdentityFixture.manager(owner,clock),List.of(new SimpleGrantedAuthority("ROLE_RESTAURANT_MANAGER"))));
        assertThatThrownBy(()->policy.requireCustomer(manager)).hasMessageContaining("FORBIDDEN");
        assertThat(actor.subject()).isEqualTo("client");
    }
    @Test void seleccionDeterministaRespetaCapacidadMesasYDesempate(){
        var policy=new ReservationAssignmentPolicy();
        UUID a=UUID.fromString("00000000-0000-4000-8000-000000000001"),b=UUID.fromString("00000000-0000-4000-8000-000000000002");
        var single=new ReservationAssignmentPolicy.Option(null,List.of(new TableSnapshot(a,4)));
        var other=new ReservationAssignmentPolicy.Option(null,List.of(new TableSnapshot(b,4)));
        var combination=new ReservationAssignmentPolicy.Option(UUID.randomUUID(),List.of(new TableSnapshot(a,2),new TableSnapshot(b,2)));
        assertThat(policy.select(List.of(other,combination,single),Set.of(),3).orElseThrow()).isEqualTo(single);
        assertThat(policy.select(List.of(single,other),Set.of(a),3).orElseThrow()).isEqualTo(other);
        assertThat(policy.select(List.of(combination),Set.of(a),3)).isEmpty();
    }
    @Test void integridadExigeCapacidadYExtremosCoherentes(){
        var validator=new ReservationIntegrityValidator();UUID table=UUID.randomUUID();Instant start=Instant.parse("2026-11-02T12:00:00Z");
        var valid=new ManagedReservationCollection(UUID.randomUUID(),2,UUID.randomUUID(),UUID.randomUUID(),List.of(table),null,
            "https://issuer.example.test","customer",3,"",ManagedReservationStatus.CONFIRMED,1,
            "2026-11-02T12:00:00","2026-11-02T13:00:00","UTC",start,start.plusSeconds(3600),List.of(new TableSnapshot(table,4)),4,start.minusSeconds(7200),start.minusSeconds(7200),null);
        assertThatCode(()->validator.validate(valid)).doesNotThrowAnyException();
        var corrupt=new ManagedReservationCollection(valid.id(),2,valid.restaurantId(),valid.shiftId(),valid.tableIds(),null,
            valid.customerIssuer(),valid.customerSubject(),3,"",valid.status(),1,valid.localStart(),valid.localEnd(),valid.zoneId(),start,start.plusSeconds(3600),valid.tableSnapshots(),8,valid.createdAt(),valid.updatedAt(),null);
        assertThatThrownBy(()->validator.validate(corrupt)).hasMessageContaining("RESERVATION_UNVERIFIABLE");
    }
}
