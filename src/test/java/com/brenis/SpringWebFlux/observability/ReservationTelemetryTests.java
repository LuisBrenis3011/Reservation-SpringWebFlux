package com.brenis.SpringWebFlux.observability;
import org.junit.jupiter.api.Test;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import static org.assertj.core.api.Assertions.*;
class ReservationTelemetryTests {
    @Test void etiquetasSonAcotadasYSinIdentidad(){
        var registry=new SimpleMeterRegistry();var telemetry=new ReservationTelemetry(registry);
        for(var outcome:ReservationTelemetry.Outcome.values())telemetry.record(outcome,"operation-test");
        assertThat(registry.get("reservations.operations").tag("outcome","no_op").counter().count()).isEqualTo(1);
        assertThat(registry.getMeters()).hasSize(ReservationTelemetry.Outcome.values().length);
        assertThat(registry.getMeters()).allSatisfy(meter->assertThat(meter.getId().getTags()).hasSize(1));
    }
}
