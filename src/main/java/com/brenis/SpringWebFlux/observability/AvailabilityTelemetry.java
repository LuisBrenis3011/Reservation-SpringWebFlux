package com.brenis.SpringWebFlux.observability;

import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.handlers.AvailabilityHttpSupport;
import io.micrometer.core.instrument.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.ServerResponse;
import reactor.core.publisher.Mono;
import reactor.util.context.ContextView;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.*;
import java.util.function.Supplier;

/** Una medición por suscripción lógica, sin MDC ni etiquetas de cardinalidad ilimitada. */
@Component
public class AvailabilityTelemetry {
    public enum Operation { HTTP, WRITE, READ, LEGACY }
    private static final String ID="availability.operationId";
    private static final String TRACE="availability.telemetry";
    private static final Logger LOG=LoggerFactory.getLogger(AvailabilityTelemetry.class);
    private static final Set<String> CODES=Set.of("INVALID_REQUEST","VALIDATION_ERROR","UNAUTHENTICATED",
            "FORBIDDEN","NOT_FOUND","REVISION_MISMATCH","DUPLICATE_LABEL","DUPLICATE_COMBINATION",
            "SHIFT_OVERLAP","PROTECTED_RESERVATION","LEGACY_RESERVATION_BLOCK","SHIFT_ALREADY_STARTED",
            "IDEMPOTENCY_CONFLICT","COMMITMENT_CHECK_UNAVAILABLE","OPERATION_OUTCOME_UNKNOWN",
            "DEPENDENCY_UNAVAILABLE","INTERNAL_ERROR");
    private static final class Trace {
        final AtomicBoolean replay=new AtomicBoolean(), finished=new AtomicBoolean();
        volatile String errorCode;
    }
    private final MeterRegistry meters;
    public AvailabilityTelemetry(MeterRegistry meters) { this.meters=meters; }
    public static String operationId(ContextView context) {
        return context.getOrDefault(ID,UUID.randomUUID().toString());
    }
    public static String code(Throwable failure) {
        for(Throwable cause=failure;cause!=null;cause=cause.getCause())
            if(cause instanceof AvailabilityException known)
                return CODES.contains(known.code())?known.code():"INTERNAL_ERROR";
        return "INTERNAL_ERROR";
    }
    public static void httpError(ContextView context,String code) {
        if(context.hasKey(TRACE)) context.<Trace>get(TRACE).errorCode=CODES.contains(code)?code:"INTERNAL_ERROR";
    }
    public Mono<Void> replay() {
        return Mono.deferContextual(context -> {
            if(context.hasKey(TRACE)) context.<Trace>get(TRACE).replay.set(true);
            return Mono.empty();
        });
    }
    public <T> Mono<T> observe(Operation operation,UUID restaurant,Supplier<Mono<T>> source) {
        return Mono.deferContextual(parent -> {
            String id=operationId(parent);
            Trace trace=new Trace();
            long start=System.nanoTime();
            return Mono.defer(source).doOnSuccess(value -> {
                String code=trace.errorCode;
                if(code==null && value instanceof ServerResponse response && response.statusCode().isError())
                    code="INTERNAL_ERROR";
                if(code==null) code="OK";
                finish(trace,operation,restaurant,id,start,code,
                        code.equals("OK")?(trace.replay.get()?"replay":"success"):outcome(code));
            }).doOnError(error -> finish(trace,operation,restaurant,id,start,code(error),outcome(code(error))))
              .doOnCancel(() -> finish(trace,operation,restaurant,id,start,"CANCELLED","cancelled"))
              .contextWrite(context -> context.put(ID,id).put(TRACE,trace));
        });
    }
    private static String outcome(String code) {
        return AvailabilityHttpSupport.status(code)>=500?"error":"rejected";
    }
    private void finish(Trace trace,Operation operation,UUID restaurant,String id,long start,String code,String outcome) {
        if(!trace.finished.compareAndSet(false,true)) return;
        long nanos=Math.max(0,System.nanoTime()-start);
        String layer=operation.name().toLowerCase(Locale.ROOT);
        // La telemetría no debe convertir un commit confirmado en un fallo de negocio.
        try {
            LOG.info("event=availability.operation operationId={} restaurantId={} operation={} outcome={} code={} durationMs={}",
                    id,restaurant==null?"unknown":restaurant,layer,outcome,code,nanos/1_000_000.0);
            var tags=Tags.of("operation",layer,"outcome",outcome,"code",code);
            meters.counter("availability.operations",tags).increment();
            meters.timer("availability.operation.duration",tags).record(nanos,TimeUnit.NANOSECONDS);
            if(AvailabilityHttpSupport.status(code)==409 || AvailabilityHttpSupport.status(code)==412)
                meters.counter("availability.conflicts",tags).increment();
            if(code.equals("LEGACY_RESERVATION_BLOCK"))
                meters.counter("availability.legacy.blocks",tags).increment();
            if(outcome.equals("error")) meters.counter("availability.failures",tags).increment();
        } catch(RuntimeException unavailable) {
            // Sin mensaje/stack del exporter: pueden incluir configuración sensible.
            LOG.warn("event=availability.telemetry.unavailable operationId={} operation={}",id,layer);
        }
    }
}

