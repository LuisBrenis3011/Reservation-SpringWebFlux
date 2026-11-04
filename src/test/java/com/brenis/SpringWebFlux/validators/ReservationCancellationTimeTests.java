package com.brenis.SpringWebFlux.validators;
import java.time.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
class ReservationCancellationTimeTests {
    final ReservationTimePolicy time=new ReservationTimePolicy();
    final Instant now=Instant.parse("2026-11-01T10:00:00Z");
    @Test void clienteIncluyeDosHorasPeroNoMenos(){
        time.cancel(now,now.plusSeconds(7200),false,false);
        assertThatThrownBy(()->time.cancel(now,now.plusSeconds(7200).minusNanos(1),false,false)).hasMessageContaining("RESERVATION_WINDOW_CLOSED");
    }
    @Test void encargadoExigeInicioOriginalFuturoEstricto(){
        time.cancel(now,now.plusNanos(1),true,false);
        assertThatThrownBy(()->time.cancel(now,now,true,false)).hasMessageContaining("RESERVATION_WINDOW_CLOSED");
    }
    @Test void yaCanceladaNoReimponePlazo(){
        time.cancel(now,now.minus(Duration.ofDays(1)),false,true);
        time.cancel(now,now.minus(Duration.ofDays(1)),true,true);
    }
}
