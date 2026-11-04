package com.brenis.SpringWebFlux.validators;

import java.time.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class ReservationReplaceTimeTests {
    final ReservationTimePolicy policy=new ReservationTimePolicy();
    final Instant now=Instant.parse("2026-11-01T10:00:00Z");
    @Test void esc0703_clienteIncluyeDosHorasYNoventaDias(){
        policy.replace(now,now.plusSeconds(7200),now.plus(Duration.ofDays(90)),20,false);
        policy.replace(now,now.plusSeconds(7200),now.plusSeconds(7200),1,false);
    }
    @Test void esc0704_clienteRechazaAmbosExtremosFueraDelPlazo(){
        assertThatThrownBy(()->policy.replace(now,now.plusSeconds(7199),now.plusSeconds(7200),2,false)).hasMessageContaining("RESERVATION_WINDOW_CLOSED");
        assertThatThrownBy(()->policy.replace(now,now.plusSeconds(7200),now.plusSeconds(7199),2,false)).hasMessageContaining("RESERVATION_WINDOW_CLOSED");
        assertThatThrownBy(()->policy.replace(now,now.plusSeconds(7200),now.plus(Duration.ofDays(90)).plusMillis(1),2,false)).hasMessageContaining("RESERVATION_WINDOW_CLOSED");
    }
    @Test void encargadoExigeFuturoEstrictoEnOriginalYDestino(){
        policy.replace(now,now.plusMillis(1),now.plusMillis(1),2,true);
        policy.replace(now,now.plusMillis(1),now.plus(Duration.ofDays(90)),2,true);
        assertThatThrownBy(()->policy.replace(now,now,now.plusSeconds(1),2,true)).hasMessageContaining("RESERVATION_WINDOW_CLOSED");
        assertThatThrownBy(()->policy.replace(now,now.plusSeconds(1),now,2,true)).hasMessageContaining("RESERVATION_WINDOW_CLOSED");
        assertThatThrownBy(()->policy.replace(now,now.plusSeconds(1),now.plus(Duration.ofDays(90)).plusMillis(1),2,true)).hasMessageContaining("RESERVATION_WINDOW_CLOSED");
    }
    @Test void grupoFueraDeRango(){
        for(int size:new int[]{0,21})assertThatThrownBy(()->policy.replace(now,now.plusSeconds(7200),now.plusSeconds(7200),size,false)).hasMessageContaining("VALIDATION_ERROR");
    }
}
