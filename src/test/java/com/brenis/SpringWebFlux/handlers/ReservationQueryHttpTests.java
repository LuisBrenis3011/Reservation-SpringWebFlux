package com.brenis.SpringWebFlux.handlers;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.web.reactive.function.server.RouterFunctions;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.support.ReservationIdentityFixture;
import com.brenis.SpringWebFlux.services.definitions.ReservationQueryService;
import com.brenis.SpringWebFlux.dtos.responses.ReservationListResponse;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
class ReservationQueryHttpTests {
    @Test void listaPropiaExigeIdentidadYNoPublicaEtag(){
        var service=mock(ReservationQueryService.class);var clock=Clock.fixed(Instant.parse("2026-11-01T10:00:00Z"),ZoneOffset.UTC);
        var common=new AvailabilityHttpSupport(clock);var handler=new ReservationQueryHandler(service,new ReservationHttpSupport(common,clock),common);
        var router=RouterFunctions.route().GET("/me/reservations",handler::mine).build();
        WebTestClient.bindToRouterFunction(router).build().get().uri("/me/reservations").exchange().expectStatus().isUnauthorized();
        var principal=new JwtAuthenticationToken(ReservationIdentityFixture.customer("client",clock),List.of(new SimpleGrantedAuthority("ROLE_CUSTOMER")));
        var client=WebTestClient.bindToRouterFunction(router).webFilter((exchange,chain)->chain.filter(exchange.mutate().principal(Mono.just(principal)).build())).build();
        when(service.mine(any(),eq(0),eq(20),isNull())).thenReturn(Mono.just(new ReservationListResponse(List.of(),0,20)));
        client.get().uri("/me/reservations").exchange().expectStatus().isOk().expectHeader().doesNotExist("ETag").expectBody().jsonPath("$.items").isArray();
        client.get().uri("/me/reservations?page=-1").exchange().expectStatus().isBadRequest();
    }
    @Test void detalleAjenoNoExponeContenido(){
        var service=mock(ReservationQueryService.class);var clock=Clock.systemUTC();var common=new AvailabilityHttpSupport(clock);
        var handler=new ReservationQueryHandler(service,new ReservationHttpSupport(common,clock),common);var owner=UUID.randomUUID();var id=UUID.randomUUID();
        var principal=new JwtAuthenticationToken(ReservationIdentityFixture.customer("client",clock),List.of(new SimpleGrantedAuthority("ROLE_CUSTOMER")));
        var client=WebTestClient.bindToRouterFunction(RouterFunctions.route().GET("/restaurants/{restaurantId}/reservations/{reservationId}",handler::managed).build())
            .webFilter((exchange,chain)->chain.filter(exchange.mutate().principal(Mono.just(principal)).build())).build();
        when(service.managed(any(),eq(owner),eq(id))).thenReturn(Mono.error(new AvailabilityException("NOT_FOUND","ajena")));
        client.get().uri("/restaurants/"+owner+"/reservations/"+id).exchange().expectStatus().isNotFound().expectBody().jsonPath("$.code").isEqualTo("NOT_FOUND");
    }
}
