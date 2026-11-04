package com.brenis.SpringWebFlux.handlers;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.web.reactive.function.server.RouterFunctions;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import com.brenis.SpringWebFlux.support.ReservationIdentityFixture;
import com.brenis.SpringWebFlux.services.impls.ReservationAccessPolicy;
import com.brenis.SpringWebFlux.services.definitions.ReservationCommandService;
import static org.mockito.Mockito.*;
class ReservationCommandHttpTests {
    final Clock clock=Clock.fixed(Instant.parse("2026-11-01T10:00:00Z"),ZoneOffset.UTC);
    @Test void clienteValidoRecibe201LocationYVersionComoETag(){
        var service=mock(ReservationCommandService.class);var common=new AvailabilityHttpSupport(clock);
        var handler=new ReservationCommandHandler(service,new ReservationAccessPolicy(),new ReservationHttpSupport(common,clock),common);
        var owner=UUID.randomUUID();var id=UUID.randomUUID();var shift=UUID.randomUUID();var table=UUID.randomUUID();
        var row=new com.brenis.SpringWebFlux.collections.ManagedReservationCollection(id,2,owner,shift,List.of(table),null,
            "https://issuer.example.test","client",2,"",com.brenis.SpringWebFlux.enums.ManagedReservationStatus.CONFIRMED,1,
            "2026-11-01T13:00:00","2026-11-01T14:00:00","UTC",clock.instant().plusSeconds(10800),clock.instant().plusSeconds(14400),
            List.of(new com.brenis.SpringWebFlux.collections.ManagedReservationCollection.TableSnapshot(table,4)),4,clock.instant(),clock.instant(),null);
        var response=new com.brenis.SpringWebFlux.mappers.ManagedReservationMapper(new com.brenis.SpringWebFlux.validators.ReservationIntegrityValidator()).response(row);
        var location="/catalog/restaurants/"+owner+"/reservations/"+id;
        when(service.confirm(org.mockito.ArgumentMatchers.any(),org.mockito.ArgumentMatchers.eq(owner),org.mockito.ArgumentMatchers.any(),org.mockito.ArgumentMatchers.any()))
            .thenReturn(reactor.core.publisher.Mono.just(new com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator.Result<>(response,15,201,location)));
        var principal=new JwtAuthenticationToken(ReservationIdentityFixture.customer("client",clock),List.of(new SimpleGrantedAuthority("ROLE_CUSTOMER")));
        var client=WebTestClient.bindToRouterFunction(RouterFunctions.route().POST("/restaurants/{restaurantId}/reservations",handler::confirm).build())
            .webFilter((exchange,chain)->chain.filter(exchange.mutate().principal(reactor.core.publisher.Mono.just(principal)).build())).build();
        client.post().uri("/restaurants/"+owner+"/reservations").header("Idempotency-Key","key")
            .bodyValue("{\"shiftId\":\""+shift+"\",\"partySize\":2}").exchange().expectStatus().isCreated()
            .expectHeader().valueEquals("Location",location).expectHeader().valueEquals("ETag","\"1\"")
            .expectBody().jsonPath("$.owner.subject").isEqualTo("client").jsonPath("$.id").isEqualTo(id.toString());
    }
    @Test void sinAutenticacionNoSeInvocaServicio(){
        var service=mock(ReservationCommandService.class);var common=new AvailabilityHttpSupport(clock);
        var handler=new ReservationCommandHandler(service,new ReservationAccessPolicy(),new ReservationHttpSupport(common,clock),common);
        WebTestClient.bindToRouterFunction(RouterFunctions.route().POST("/restaurants/{restaurantId}/reservations",handler::confirm).build()).build()
            .post().uri("/restaurants/"+UUID.randomUUID()+"/reservations").bodyValue("{}").exchange().expectStatus().isUnauthorized();
        verifyNoInteractions(service);
    }
    @Test void retiroAntiguoDevuelve410InclusoConCuerpoInvalido(){
        var business=mock(com.brenis.SpringWebFlux.services.definitions.ReservationBusinessService.class);
        var validator=mock(com.brenis.SpringWebFlux.validators.ReactiveValidator.class);
        var barrier=mock(com.brenis.SpringWebFlux.services.impls.LegacyReservationWriteBarrier.class);
        when(barrier.check()).thenReturn(reactor.core.publisher.Mono.error(new com.brenis.SpringWebFlux.exceptions.AvailabilityException("LEGACY_WRITES_RETIRED","Retirado")));
        var handler=new ReservationHandler(business,validator);
        handler.configureLegacyBarrier(barrier,new ReservationHttpSupport(new AvailabilityHttpSupport(clock),clock));
        WebTestClient.bindToRouterFunction(RouterFunctions.route().POST("/reservation",handler::postReservation).build()).build()
            .post().uri("/reservation").bodyValue("invalido").exchange().expectStatus().isEqualTo(410);
        verifyNoInteractions(business,validator);
    }
    @Test void faltaPerfilRechazaAntesDelServicio(){
        var service=mock(ReservationCommandService.class);var common=new AvailabilityHttpSupport(clock);
        var handler=new ReservationCommandHandler(service,new ReservationAccessPolicy(),new ReservationHttpSupport(common,clock),common);
        var jwt=ReservationIdentityFixture.manager(UUID.randomUUID(),clock);
        var principal=new JwtAuthenticationToken(jwt,List.of(new SimpleGrantedAuthority("ROLE_RESTAURANT_MANAGER")));
        var client=WebTestClient.bindToRouterFunction(RouterFunctions.route().POST("/restaurants/{restaurantId}/reservations",handler::confirm).build())
            .webFilter((exchange,chain)->chain.filter(exchange.mutate().principal(reactor.core.publisher.Mono.just(principal)).build())).build();
        client.post().uri("/restaurants/"+UUID.randomUUID()+"/reservations").bodyValue("{}").exchange().expectStatus().isForbidden();
        verifyNoInteractions(service);
    }
    @Test void titularInyectadoEnCuerpoSeRechazaParaClienteYDual(){
        for(boolean dual:List.of(false,true)){
            var service=mock(ReservationCommandService.class);var common=new AvailabilityHttpSupport(clock);
            var handler=new ReservationCommandHandler(service,new ReservationAccessPolicy(),new ReservationHttpSupport(common,clock),common);
            var jwt=dual?ReservationIdentityFixture.dual("customer",UUID.randomUUID(),clock):ReservationIdentityFixture.customer("customer",clock);
            var principal=new JwtAuthenticationToken(jwt,List.of(new SimpleGrantedAuthority("ROLE_CUSTOMER")));
            var client=WebTestClient.bindToRouterFunction(RouterFunctions.route().POST("/restaurants/{restaurantId}/reservations",handler::confirm).build())
                .webFilter((exchange,chain)->chain.filter(exchange.mutate().principal(reactor.core.publisher.Mono.just(principal)).build())).build();
            client.post().uri("/restaurants/"+UUID.randomUUID()+"/reservations").header("Idempotency-Key","key")
                .bodyValue("{\"shiftId\":\""+UUID.randomUUID()+"\",\"partySize\":2,\"customerId\":\"other\"}")
                .exchange().expectStatus().isBadRequest();verifyNoInteractions(service);
        }
    }
}
