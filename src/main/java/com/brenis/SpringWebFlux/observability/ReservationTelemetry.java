package com.brenis.SpringWebFlux.observability;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.stereotype.Component;
@Component
public class ReservationTelemetry {
    private static final org.slf4j.Logger LOG=org.slf4j.LoggerFactory.getLogger(ReservationTelemetry.class);
    public enum Outcome { ACCEPTED,REJECTED,REPLAY,NO_OP,VERSION_CONFLICT,CONTENTION,UNCERTAIN }
    private final MeterRegistry registry;
    public ReservationTelemetry(MeterRegistry registry){this.registry=registry;}
    public void record(Outcome outcome){record(outcome,"unavailable");}
    public void record(Outcome outcome,String operationId){
        try{
            registry.counter("reservations.operations","outcome",outcome.name().toLowerCase(java.util.Locale.ROOT)).increment();
            LOG.info("event=reservations.operation operationId={} outcome={}",operationId,outcome);
        }catch(RuntimeException unavailable){
            // Un fallo del exporter no cambia el resultado de un commit ya confirmado.
            LOG.warn("event=reservations.telemetry.unavailable operationId={}",operationId);
        }
    }
}
