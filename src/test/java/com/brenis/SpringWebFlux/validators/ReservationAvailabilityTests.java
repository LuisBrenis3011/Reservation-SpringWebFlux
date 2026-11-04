package com.brenis.SpringWebFlux.validators;
import java.time.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
class ReservationAvailabilityTests {
    @Test void ventanaInclusivaYGrupoInvalido(){
        var policy=new ReservationTimePolicy();var now=Instant.parse("2026-11-01T10:00:00Z");
        assertThat(policy.window(now,now.plus(Duration.ofHours(2)))).isEqualTo(ReservationTimePolicy.BookingWindow.OPEN);
        assertThat(policy.window(now,now.plus(Duration.ofDays(90)))).isEqualTo(ReservationTimePolicy.BookingWindow.OPEN);
        assertThat(policy.window(now,now.plus(Duration.ofHours(2)).minusNanos(1))).isEqualTo(ReservationTimePolicy.BookingWindow.TOO_SOON);
        assertThat(policy.window(now,now.plus(Duration.ofDays(90)).plusNanos(1))).isEqualTo(ReservationTimePolicy.BookingWindow.TOO_FAR);
        assertThatThrownBy(()->policy.group(0)).hasMessageContaining("VALIDATION_ERROR");
        assertThatThrownBy(()->policy.group(21)).hasMessageContaining("VALIDATION_ERROR");
    }
}
