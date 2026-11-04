package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;
import com.brenis.SpringWebFlux.support.*;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.services.impls.*;
import com.brenis.SpringWebFlux.repositories.LegacyReservationQueryRepository;
import static org.assertj.core.api.Assertions.*;

@SpringJUnitConfig(ReservationLifecycleIT.Configuration.class)
class ReservationLifecycleIT extends ReservationCancellationSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false)
    @Import({ReservationConfirmationSupport.Configuration.class,ReservationAvailabilityServiceImpl.class,
        ReservationQueryServiceImpl.class,LegacyReservationQueryRepository.class})
    public static class Configuration {}
    @Autowired ReservationAvailabilityService availability;
    @Autowired ReservationQueryService queries;
    private String availability(){return availability.list(restaurant,java.time.LocalDate.ofInstant(clock.instant().plusSeconds(10800),java.time.ZoneOffset.UTC),2)
        .block().items().stream().filter(item->item.shiftId().equals(shift)).findFirst().orElseThrow().availability();}
    @Test void t188_consultaConfirmaEditaCancelaYConfirmaOtraVezConHistoriaYReplay(){
        var before=state();assertThat(availability()).isEqualTo("AVAILABLE");assertThat(queries.mine(customer("client"),0,20,null).block().items()).isEmpty();assertThat(state()).isEqualTo(before);
        var first=confirm("client","first",2).block();assertThat(availability()).isEqualTo("UNAVAILABLE");
        assertThat(queries.managed(customer("client"),restaurant,first.body().id()).block().version()).isEqualTo(1);
        var edited=replace(customer("client"),first.body().id(),1,"edit",shift,3,"Ventana").block();
        assertThat(queries.managed(manager,restaurant,first.body().id()).block().notes()).isEqualTo("Ventana");
        var cancelled=cancel(customer("client"),first.body().id(),2,"cancel").block();assertThat(cancelled.body().version()).isEqualTo(3);
        assertThat(queries.managed(customer("client"),restaurant,first.body().id()).block().status()).isEqualTo("CANCELLED");assertThat(availability()).isEqualTo("AVAILABLE");
        var next=confirm("client","new",2).block();assertThat(next.body().id()).isNotEqualTo(first.body().id());assertThat(availability()).isEqualTo("UNAVAILABLE");
        var stable=state();
        assertThat(confirm("client","first",2).block()).isEqualTo(first);
        assertThat(replace(customer("client"),first.body().id(),1,"edit",shift,3,"Ventana").block()).isEqualTo(edited);
        assertThat(cancel(customer("client"),first.body().id(),2,"cancel").block()).isEqualTo(cancelled);assertThat(state()).isEqualTo(stable);
        assertThatThrownBy(()->queries.managed(otherCustomer(),restaurant,next.body().id()).block()).hasMessageContaining("NOT_FOUND");assertThat(state()).isEqualTo(stable);
        var active=raw(next.body().id());cancel(customer("client"),first.body().id(),0,"another-noop").block();
        assertThat(raw(next.body().id())).isEqualTo(active);assertThat(revision()).isEqualTo(4);assertThat(receiptCount()).isEqualTo(5);
    }
}
