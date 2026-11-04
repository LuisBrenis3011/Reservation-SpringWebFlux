package com.brenis.SpringWebFlux.handlers;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.web.reactive.function.server.RouterFunctions;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.mockito.ArgumentCaptor;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.support.ReservationIdentityFixture;
import com.brenis.SpringWebFlux.services.impls.ReservationAccessPolicy;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.dtos.requests.ManagedReservationRequest;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.assertj.core.api.Assertions.*;

class ReservationReplaceHttpTests {
    final Clock clock=Clock.fixed(Instant.parse("2026-11-01T10:00:00Z"),ZoneOffset.UTC);
    final UUID owner=UUID.randomUUID(),id=UUID.randomUUID(),shift=UUID.randomUUID();
    final ReservationCommandService service=mock(ReservationCommandService.class);
    String path(){return "/restaurants/"+owner+"/reservations/"+id;}
    String body(){return "{\"shiftId\":\""+shift+"\",\"partySize\":2}";}
    WebTestClient client(java.security.Principal actor){
        var common=new AvailabilityHttpSupport(clock);
        var handler=new ReservationCommandHandler(service,new ReservationAccessPolicy(),new ReservationHttpSupport(common,clock),common);
        var builder=WebTestClient.bindToRouterFunction(RouterFunctions.route().PUT("/restaurants/{restaurantId}/reservations/{reservationId}",handler::replace).build());
        if(actor!=null)builder.webFilter((exchange,chain)->chain.filter(exchange.mutate().principal(Mono.just(actor)).build()));
        return builder.build();
    }
    JwtAuthenticationToken customer(){return new JwtAuthenticationToken(ReservationIdentityFixture.customer("client",clock),
        List.of(new SimpleGrantedAuthority("ROLE_CUSTOMER")));}
    @Test void esc0701_putCompletoNotasOmitidasYETagDeVersion(){
        UUID table=UUID.randomUUID();
        var row=new com.brenis.SpringWebFlux.collections.ManagedReservationCollection(id,2,owner,shift,List.of(table),null,
            "https://issuer.example.test","client",2,"",com.brenis.SpringWebFlux.enums.ManagedReservationStatus.CONFIRMED,2,
            "2026-11-01T13:00:00","2026-11-01T14:00:00","UTC",clock.instant().plusSeconds(10800),clock.instant().plusSeconds(14400),
            List.of(new com.brenis.SpringWebFlux.collections.ManagedReservationCollection.TableSnapshot(table,4)),4,clock.instant(),clock.instant(),null);
        var response=new com.brenis.SpringWebFlux.mappers.ManagedReservationMapper(new com.brenis.SpringWebFlux.validators.ReservationIntegrityValidator()).response(row);
        when(service.replace(any(),eq(owner),eq(id),eq(1L),any(),any())).thenReturn(Mono.just(new RestaurantOperationCoordinator.Result<>(response,25,200,null)));
        client(customer()).put().uri(path()).header("Idempotency-Key","edit").header("If-Match","\"1\"")
            .bodyValue(body()).exchange().expectStatus().isOk().expectHeader().valueEquals("ETag","\"2\"").expectHeader().doesNotExist("Location")
            .expectBody().jsonPath("$.notes").isEqualTo("").jsonPath("$.id").isEqualTo(id.toString());
        var dto=ArgumentCaptor.forClass(ManagedReservationRequest.class);var metadata=ArgumentCaptor.forClass(CommandMetadata.class);
        verify(service).replace(any(),eq(owner),eq(id),eq(1L),dto.capture(),metadata.capture());
        assertThat(dto.getValue().notes()).isEmpty();assertThat(metadata.getValue().expectedRevision()).isNull();
        String firstFingerprint=metadata.getValue().fingerprint();clearInvocations(service);
        // Misma versión numérica, distinta cabecera original: la huella cambia.
        client(customer()).put().uri(path()).header("Idempotency-Key","edit").header("If-Match","\"01\"")
            .bodyValue(body()).exchange().expectStatus().isOk();
        verify(service).replace(any(),eq(owner),eq(id),eq(1L),any(),metadata.capture());
        assertThat(metadata.getValue().fingerprint()).isNotEqualTo(firstFingerprint);
    }
    @Test void esc0702_sinIdentidadOPermisosNoInvocaServicio(){
        client(null).put().uri(path()).bodyValue(body()).exchange().expectStatus().isUnauthorized();
        var foreign=new JwtAuthenticationToken(ReservationIdentityFixture.manager(UUID.randomUUID(),clock),
            List.of(new SimpleGrantedAuthority("ROLE_RESTAURANT_MANAGER")));
        client(foreign).put().uri(path()).bodyValue(body()).exchange().expectStatus().isForbidden();
        verifyNoInteractions(service);
    }
    @Test void cabecerasYCuerpoInvalidosNoInvocanServicio(){
        var web=client(customer());
        for(String match:List.of("", "1","W/\"1\"","\"-1\"","\"99999999999999999999\"")){
            var request=web.put().uri(path()).header("Idempotency-Key","edit");if(!match.isEmpty())request.header("If-Match",match);
            request.bodyValue(body()).exchange().expectStatus().isBadRequest();
        }
        for(String field:List.of("owner","restaurantId","tableIds","extra"))
            web.put().uri(path()).header("Idempotency-Key","edit").header("If-Match","\"1\"")
                .bodyValue(body().replace("}",",\""+field+"\":\"x\"}")).exchange().expectStatus().isBadRequest();
        web.put().uri(path()).header("If-Match","\"1\"").bodyValue(body()).exchange().expectStatus().isBadRequest();
        verifyNoInteractions(service);
    }
    @Test void erroresDeDominioRespetanContrato(){
        var web=client(customer());
        var statuses=Map.of("NOT_FOUND",404,"RESERVATION_NOT_EDITABLE",409,"LEGACY_RESERVATION_READ_ONLY",409,"REVISION_MISMATCH",412,"VALIDATION_ERROR",422,"DEPENDENCY_UNAVAILABLE",503);
        for(var entry:statuses.entrySet()){
            when(service.replace(any(),eq(owner),eq(id),eq(1L),any(),any())).thenReturn(Mono.error(new AvailabilityException(entry.getKey(),entry.getKey())));
            web.put().uri(path()).header("Idempotency-Key","edit").header("If-Match","\"1\"").bodyValue(body()).exchange()
                .expectStatus().isEqualTo(entry.getValue()).expectBody().jsonPath("$.code").isEqualTo(entry.getKey());
        }
    }
}
