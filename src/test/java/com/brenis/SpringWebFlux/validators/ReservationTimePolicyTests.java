package com.brenis.SpringWebFlux.validators;
import java.time.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
class ReservationTimePolicyTests {
    @Test void bordesInclusivosYFracciones(){
        var policy=new ReservationTimePolicy();var now=Instant.parse("2026-11-01T10:00:00Z");
        for(int size:new int[]{1,20})for(var delta:new Duration[]{Duration.ofHours(2),Duration.ofDays(90)})
            assertThatCode(()->policy.confirm(now,now.plus(delta),size)).doesNotThrowAnyException();
        assertThatThrownBy(()->policy.confirm(now,now.plusSeconds(7200).minusNanos(1),2)).hasMessageContaining("RESERVATION_WINDOW_CLOSED");
        assertThatThrownBy(()->policy.confirm(now,now.plus(Duration.ofDays(90)).plusNanos(1),2)).hasMessageContaining("RESERVATION_WINDOW_CLOSED");
        for(int size:new int[]{0,21})assertThatThrownBy(()->policy.confirm(now,now.plusSeconds(7200),size)).hasMessageContaining("VALIDATION_ERROR");
    }
}
