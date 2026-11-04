package com.brenis.SpringWebFlux.services;
import java.util.*;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationCancellationSupport;
import com.brenis.SpringWebFlux.collections.*;
import static org.assertj.core.api.Assertions.*;
class ReservationCancellationIT extends ReservationCancellationSupport {
    @Test void esc0803_04_liberaCombinacionABConservandoReservaC(){
        UUID b=UUID.randomUUID(),c=UUID.randomUUID(),combination=UUID.randomUUID();extraTable(b,4);extraTable(c,4);
        var members=java.util.stream.Stream.of(table,b).sorted(Comparator.comparing(UUID::toString)).toList();
        mongo.insert(new TableCombinationCollection(combination,restaurant,members,members.toString())).block();
        var first=confirm("client","ab",6).block().body();var other=confirm("other","c",3).block().body();
        assertThat(first.tableIds()).containsExactlyElementsOf(members);assertThat(other.tableIds()).containsExactly(c);
        var original=raw(first.id());var unchanged=raw(other.id());
        var result=cancel(customer("client"),first.id(),1,"cancel-ab").block();
        assertThat(result.body().status()).isEqualTo("CANCELLED");assertThat(result.body().version()).isEqualTo(2);
        assertThat(result.revision()).isEqualTo(3);assertThat(result.body().cancelledAt()).isEqualTo(clock.instant());assertThat(result.body().updatedAt()).isEqualTo(clock.instant());
        historyUnchanged(original,raw(first.id()));assertThat(raw(other.id())).isEqualTo(unchanged);
        var next=confirm("client","new-ab",6).block().body();
        assertThat(next.id()).isNotEqualTo(first.id());assertThat(next.tableIds()).containsExactlyElementsOf(members);
        assertThat(raw(other.id())).isEqualTo(unchanged);assertThat(raw(first.id()).getString("status")).isEqualTo("CANCELLED");
        assertThat(revision()).isEqualTo(4);assertThat(receiptCount()).isEqualTo(4);
    }
    @Test void esc0801_clienteExactamenteDosHorasYEncargadoDentroDeDosHoras(){
        var first=confirm("client","first",2).block().body();var initial=clock.instant();
        try{
            clock.advance(java.time.Duration.ofHours(1));
            assertThat(cancel(customer("client"),first.id(),1,"two-hours").block().body().status()).isEqualTo("CANCELLED");
            var second=confirm("client","second",2).block().body();
            clock.advance(java.time.Duration.ofMinutes(30));var before=state();
            assertThatThrownBy(()->cancel(customer("client"),second.id(),1,"too-late").block()).hasMessageContaining("RESERVATION_WINDOW_CLOSED");assertThat(state()).isEqualTo(before);
            assertThat(cancel(dual("client"),second.id(),1,"manager").block().body().status()).isEqualTo("CANCELLED");
        }finally{clock.set(initial);}
    }
    @Test void esc0802_ajenaLegacyYVersionObsoletaConservanDatos(){
        var first=confirm("client","first",2).block().body();var before=state();
        assertThatThrownBy(()->cancel(otherCustomer(),first.id(),1,"foreign").block()).hasMessageContaining("NOT_FOUND");assertThat(state()).isEqualTo(before);
        assertThatThrownBy(()->cancel(customer("client"),first.id(),0,"stale").block()).hasMessageContaining("REVISION_MISMATCH");assertThat(state()).isEqualTo(before);
        UUID legacy=UUID.randomUUID();mongo.insert(new org.bson.Document("_id",legacy).append("restaurantId",restaurant),"reservations").block();
        try{before=state();assertThatThrownBy(()->cancel(manager,legacy,1,"legacy").block()).hasMessageContaining("LEGACY_RESERVATION_READ_ONLY");assertThat(state()).isEqualTo(before);}
        finally{mongo.remove(byId(legacy),"reservations").block();}
    }
    @Test void encargadoEnInicioExactoNoCancelaUnaConfirmada(){
        var first=confirm("client","first",2).block().body();var instant=clock.instant();
        try{
            clock.set(first.startInstant());var before=state();
            var currentManager=new org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken(
                com.brenis.SpringWebFlux.support.ReservationIdentityFixture.manager(restaurant,clock),
                List.of(new org.springframework.security.core.authority.SimpleGrantedAuthority("ROLE_RESTAURANT_MANAGER")));
            assertThatThrownBy(()->cancel(currentManager,first.id(),1,"started").block()).hasMessageContaining("RESERVATION_WINDOW_CLOSED");assertThat(state()).isEqualTo(before);
        }finally{clock.set(instant);}
    }
}
