package com.brenis.SpringWebFlux.handlers;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.web.reactive.function.server.RouterFunctions;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.services.definitions.ReservationAvailabilityService;
import com.brenis.SpringWebFlux.dtos.responses.ReservationAvailabilityResponse;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.assertj.core.api.Assertions.*;
class ReservationAvailabilityHttpTests {
    @Test void respuestaConTurnoNoExponeDatosPrivadosNiEtag(){
        var service=mock(ReservationAvailabilityService.class);var clock=Clock.systemUTC();var common=new AvailabilityHttpSupport(clock);
        var handler=new ReservationAvailabilityHandler(service,common,new ReservationHttpSupport(common,clock));
        var client=WebTestClient.bindToRouterFunction(RouterFunctions.route().GET("/restaurants/{restaurantId}/availability",handler::list).build()).build();
        var id=UUID.randomUUID();var shift=UUID.randomUUID();var date=LocalDate.parse("2026-11-01");var now=Instant.parse("2026-11-01T10:00:00Z");
        var item=new ReservationAvailabilityResponse.Item(shift,"2026-11-01T13:00:00","2026-11-01T14:00:00","UTC",now.plusSeconds(10800),now.plusSeconds(14400),"OPEN","AVAILABLE",true);
        when(service.list(eq(id),eq(date),eq(2))).thenReturn(Mono.just(new ReservationAvailabilityResponse(id,date.toString(),2,now,List.of(item))));
        client.get().uri("/restaurants/"+id+"/availability?date=2026-11-01&partySize=2").exchange().expectStatus().isOk().expectHeader().doesNotExist("ETag")
            .expectBody().jsonPath("$.items[0].shiftId").isEqualTo(shift.toString()).jsonPath("$.items[0].tableIds").doesNotExist()
            .jsonPath("$.items[0].owner").doesNotExist().jsonPath("$.items[0].notes").doesNotExist().jsonPath("$.revision").doesNotExist()
            .consumeWith(result->{
                var tree=tools.jackson.databind.json.JsonMapper.builder().build().readTree(result.getResponseBody());
                var fields=new java.util.HashSet<String>();tree.properties().forEach(entry->fields.add(entry.getKey()));
                assertThat(fields).containsExactlyInAnyOrder("restaurantId","date","partySize","observedAt","items");
                var itemFields=new java.util.HashSet<String>();tree.get("items").get(0).properties().forEach(entry->itemFields.add(entry.getKey()));
                assertThat(itemFields).containsExactlyInAnyOrder("shiftId","localStart","localEnd","zoneId","startInstant","endInstant","bookingWindow","availability","reservable");
            });
    }
    @Test void consultaPublicaYParametrosInvalidos(){
        var service=mock(ReservationAvailabilityService.class);var clock=Clock.systemUTC();var common=new AvailabilityHttpSupport(clock);
        var handler=new ReservationAvailabilityHandler(service,common,new ReservationHttpSupport(common,clock));
        var client=WebTestClient.bindToRouterFunction(RouterFunctions.route().GET("/restaurants/{restaurantId}/availability",handler::list).build()).build();
        var id=UUID.randomUUID();var date=LocalDate.parse("2026-11-01");
        when(service.list(eq(id),eq(date),eq(2))).thenReturn(Mono.just(new ReservationAvailabilityResponse(id,date.toString(),2,Instant.parse("2026-11-01T10:00:00Z"),List.of())));
        String base="/restaurants/"+id+"/availability";
        client.get().uri(base+"?date=2026-11-01&partySize=2").exchange().expectStatus().isOk().expectBody().jsonPath("$.items").isArray();
        client.get().uri(base+"?date=2026-02-30&partySize=2").exchange().expectStatus().isBadRequest();
        client.get().uri(base+"?date=2026-11-01&partySize=2&extra=x").exchange().expectStatus().isBadRequest();
        client.get().uri(base+"?date=2026-11-01&partySize=x").exchange().expectStatus().isBadRequest();
        for(int size:new int[]{-1,0,21})client.get().uri(base+"?date=2026-11-01&partySize="+size).exchange().expectStatus().isEqualTo(422);
    }
}
