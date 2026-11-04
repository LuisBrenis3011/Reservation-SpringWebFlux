package com.brenis.SpringWebFlux.validators;
import com.brenis.SpringWebFlux.dtos.requests.RestaurantShiftRequest;
import com.brenis.SpringWebFlux.exceptions.ShiftLocalTimeException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import java.time.*;
import static org.assertj.core.api.Assertions.*;
class AvailabilityShiftValidatorTests {
    final RestaurantShiftValidator validator=new RestaurantShiftValidator();
    final Instant now=Instant.parse("2026-11-01T10:00:00Z");
    @Test void esc0303_medianocheConFechaExplicita(){
        var v=validator.validate(new RestaurantShiftRequest("2026-11-01T22:00:00","2026-11-02T02:00:00"),"America/Lima",now);
        assertThat(Duration.between(v.startInstant(),v.endInstant())).isEqualTo(Duration.ofHours(4));
        assertThat(v.startInstant()).isEqualTo(Instant.parse("2026-11-02T03:00:00Z"));
    }
    @ParameterizedTest @CsvSource({"2026-11-01T22:00:00,2026-11-01T22:00:00","2026-11-01T22:00:00,2026-11-01T02:00:00","2026-02-30T22:00:00,2026-03-01T02:00:00","2026-11-01T22:00,2026-11-02T02:00:00"})
    void esc0304_fechasInvalidas(String start,String end){assertThatThrownBy(() -> validator.validate(new RestaurantShiftRequest(start,end),"America/Lima",now)).hasMessageContaining("VALIDATION_ERROR");}
    @ParameterizedTest @CsvSource({
        "2027-03-14T02:30:00,2027-03-14T04:00:00,NONEXISTENT",
        "2027-03-14T01:00:00,2027-03-14T02:30:00,NONEXISTENT",
        "2027-11-07T01:30:00,2027-11-07T03:00:00,AMBIGUOUS",
        "2027-11-07T00:30:00,2027-11-07T01:30:00,AMBIGUOUS"})
    void esc0313_0314_rechazaGapYOverlapEnAmbosExtremos(String start,String end,ShiftLocalTimeException.Reason reason){
        assertThatThrownBy(() -> validator.validate(new RestaurantShiftRequest(start,end),"America/New_York",now))
            .isInstanceOfSatisfying(ShiftLocalTimeException.class,error -> {
                assertThat(error.code()).isEqualTo("VALIDATION_ERROR");
                assertThat(error.reason()).isEqualTo(reason);
                assertThat(error.publicMessage()).isEqualTo(reason==ShiftLocalTimeException.Reason.NONEXISTENT
                    ? "La hora local no existe en la zona del restaurante."
                    : "La hora local es ambigua porque se repite en la zona del restaurante.");
            });
    }
    @Test void esc0318_0319_futuroEstricto(){
        var req=new RestaurantShiftRequest("2026-11-01T05:00:00","2026-11-01T06:00:00");
        assertThatThrownBy(() -> validator.validate(req,"America/Lima",now)).hasMessageContaining("SHIFT_ALREADY_STARTED");
        assertThat(validator.validate(req,"America/Lima",now.minusNanos(1)).startInstant()).isEqualTo(now);
        assertThatThrownBy(() -> validator.validate(req,"America/Lima",now.plusNanos(1))).hasMessageContaining("SHIFT_ALREADY_STARTED");
    }
    @Test void sinZonaOZonaDesconocidaNoUsaDefault(){for(String zone:new String[]{null,"","No/Zone"})assertThatThrownBy(() -> validator.validate(new RestaurantShiftRequest("2027-01-01T10:00:00","2027-01-01T11:00:00"),zone,now)).hasMessageContaining("VALIDATION_ERROR");}
}
