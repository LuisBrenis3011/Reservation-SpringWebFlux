package com.brenis.SpringWebFlux.handlers;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.web.reactive.function.server.RouterFunctions;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.support.ReservationIdentityFixture;
import com.brenis.SpringWebFlux.services.impls.ReservationAccessPolicy;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class ReservationCancellationHttpTests {
    final Clock clock=Clock.fixed(Instant.parse("2026-11-01T10:00:00Z"),ZoneOffset.UTC);
    final UUID owner=UUID.randomUUID(),id=UUID.randomUUID(),shift=UUID.randomUUID(),table=UUID.randomUUID();
    final ReservationCommandService service=mock(ReservationCommandService.class);
    String path(){return "/restaurants/"+owner+"/reservations/"+id+"/cancellation";}
    WebTestClient client(java.security.Principal principal){
        var common=new AvailabilityHttpSupport(clock);
        var handler=new ReservationCommandHandler(service,new ReservationAccessPolicy(),new ReservationHttpSupport(common,clock),common);
        var builder=WebTestClient.bindToRouterFunction(RouterFunctions.route().POST("/restaurants/{restaurantId}/reservations/{reservationId}/cancellation",handler::cancel).build());
        if(principal!=null)builder.webFilter((exchange,chain)->chain.filter(exchange.mutate().principal(Mono.just(principal)).build()));
        return builder.build();
    }
    JwtAuthenticationToken customer(){return new JwtAuthenticationToken(ReservationIdentityFixture.customer("client",clock),List.of(new SimpleGrantedAuthority("ROLE_CUSTOMER")));}
    ManagedReservationResponse response(){return new ManagedReservationResponse("MANAGED",id,owner,new ManagedReservationResponse.Owner("https://issuer.example.test","client"),
        shift,2,"Notas", "CANCELLED",2,List.of(table),null,4,"2026-11-01T13:00:00","2026-11-01T14:00:00","UTC",
        clock.instant().plusSeconds(10800),clock.instant().plusSeconds(14400),clock.instant(),clock.instant(),clock.instant());}
    @Test void titularYEncargadoReciben200ConETagDeReserva(){
        when(service.cancel(any(),eq(owner),eq(id),eq(1L),any())).thenReturn(Mono.just(new RestaurantOperationCoordinator.Result<>(response(),9,200,null)));
        for(var actor:List.of(customer(),new JwtAuthenticationToken(ReservationIdentityFixture.manager(owner,clock),List.of(new SimpleGrantedAuthority("ROLE_RESTAURANT_MANAGER"))))){
            client(actor).post().uri(path()).header("Idempotency-Key","cancel").header("If-Match","\"1\"").exchange()
                .expectStatus().isOk().expectHeader().valueEquals("ETag","\"2\"").expectHeader().doesNotExist("Location")
                .expectBody().jsonPath("$.status").isEqualTo("CANCELLED").jsonPath("$.id").isEqualTo(id.toString());
        }
    }
    @Test void ausenciaDeIdentidadYEncargadoAjenoNoInvocanServicio(){
        client(null).post().uri(path()).exchange().expectStatus().isUnauthorized();
        var foreign=new JwtAuthenticationToken(ReservationIdentityFixture.manager(UUID.randomUUID(),clock),List.of(new SimpleGrantedAuthority("ROLE_RESTAURANT_MANAGER")));
        client(foreign).post().uri(path()).exchange().expectStatus().isForbidden();verifyNoInteractions(service);
    }
    @Test void requiereCabecerasValidasYCuerpoAusente(){
        var web=client(customer());
        for(String match:List.of("","1","W/\"1\"","\"-1\"","\"99999999999999999999\"")){
            var request=web.post().uri(path()).header("Idempotency-Key","cancel");if(!match.isEmpty())request.header("If-Match",match);
            request.exchange().expectStatus().isBadRequest();
        }
        web.post().uri(path()).header("If-Match","\"1\"").exchange().expectStatus().isBadRequest();
        for(String body:List.of("{}"," ","{\"owner\":\"other\"}"))web.post().uri(path()).header("Idempotency-Key","cancel").header("If-Match","\"1\"").bodyValue(body).exchange().expectStatus().isBadRequest();
        verifyNoInteractions(service);
    }
    @Test void erroresDeNegocioSeMapeanSinRelajarSeguridad(){
        for(var error:Map.of("NOT_FOUND",404,"LEGACY_RESERVATION_READ_ONLY",409,"RESERVATION_WINDOW_CLOSED",409,"REVISION_MISMATCH",412,"RESERVATION_UNVERIFIABLE",503,"OPERATION_OUTCOME_UNKNOWN",503).entrySet()){
            when(service.cancel(any(),eq(owner),eq(id),eq(1L),any())).thenReturn(Mono.error(new AvailabilityException(error.getKey(),error.getKey())));
            client(customer()).post().uri(path()).header("Idempotency-Key","cancel").header("If-Match","\"1\"").exchange()
                .expectStatus().isEqualTo(error.getValue()).expectBody().jsonPath("$.code").isEqualTo(error.getKey());
        }
    }
}
