package com.brenis.SpringWebFlux.handlers;
import java.time.Clock;
import java.util.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.*;
import reactor.core.publisher.Mono;
import tools.jackson.databind.DeserializationFeature;
import tools.jackson.databind.json.JsonMapper;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.*;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.exceptions.ShiftLocalTimeException;
import com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator.Result;
import com.brenis.SpringWebFlux.observability.AvailabilityTelemetry;
import java.util.function.Supplier;
@Component
public class AvailabilityHttpSupport {
    private final Clock clock;
    private final AvailabilityTelemetry telemetry;
    private final JsonMapper mapper=JsonMapper.builder().enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES).build();
    public AvailabilityHttpSupport(Clock clock) {
        this(clock,new AvailabilityTelemetry(new io.micrometer.core.instrument.simple.SimpleMeterRegistry()));
    }
    @org.springframework.beans.factory.annotation.Autowired
    public AvailabilityHttpSupport(Clock clock,AvailabilityTelemetry telemetry) { this.clock=clock; this.telemetry=telemetry; }
    public Mono<ServerResponse> observe(ServerRequest request,Supplier<Mono<ServerResponse>> work) {
        UUID owner=null;
        try { owner=uuid(request.pathVariable("restaurantId")); } catch(RuntimeException ignored) { }
        return telemetry.observe(AvailabilityTelemetry.Operation.HTTP,owner,work);
    }
    public CommandMetadata metadata(ServerRequest request,boolean update) {
        String key=request.headers().firstHeader("Idempotency-Key");
        if(key!=null && key.startsWith("rsv:")) throw invalid();
        Long revision=null;
        if(update) {
            String value=request.headers().firstHeader("If-Match");
            if(value==null || !value.matches("\"[0-9]+\"")) throw invalid();
            try { revision=Long.parseLong(value.substring(1,value.length()-1)); } catch(NumberFormatException e) { throw invalid(); }
        }
        return new CommandMetadata(key,null,revision,200,null);
    }
    private AvailabilityException invalid() { return new AvailabilityException("INVALID_REQUEST","Solicitud inválida"); }
    public UUID uuid(String value) {
        try { UUID id=UUID.fromString(value); if(!id.toString().equalsIgnoreCase(value)) throw invalid(); return id; }
        catch(RuntimeException e) { throw invalid(); }
    }
    public String etag(long revision) { return "\""+revision+"\""; }
    public <T> Mono<T> readBody(ServerRequest request,Class<T> type) {
        return request.bodyToMono(String.class).switchIfEmpty(Mono.error(invalid())).flatMap(raw -> {
            try {
                var tree=mapper.readTree(raw);
                if(!tree.isObject()) return Mono.error(invalid());
                var fields=tree.properties();
                for(var field:fields) if(field.getValue().isNull()) return Mono.error(invalid());
                return Mono.just(mapper.readValue(raw,type));
            } catch(RuntimeException e) { return Mono.error(invalid()); }
        });
    }
    public CommandMetadata command(CommandMetadata headers,String method,String path,String canonicalBody,int status,String location) {
        try {
            String input=method+"\n"+path+"\n"+canonicalBody+"\n"+headers.expectedRevision();
            String fingerprint=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(input.getBytes(StandardCharsets.UTF_8)));
            return new CommandMetadata(headers.idempotencyKey(),fingerprint,headers.expectedRevision(),status,location);
        } catch(java.security.NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
    }
    public Mono<ServerResponse> response(Result<?> result) {
        var response=ServerResponse.status(result.httpStatus()).eTag(etag(result.revision()));
        if(result.location()!=null) response.header("Location",result.location());
        return response.bodyValue(result.body());
    }
    public static int status(String code) {
        return switch(code) {
            case "INVALID_REQUEST" -> 400;
            case "UNAUTHENTICATED" -> 401;
            case "FORBIDDEN" -> 403;
            case "NOT_FOUND" -> 404;
            case "REVISION_MISMATCH" -> 412;
            case "VALIDATION_ERROR" -> 422;
            case "COMMITMENT_CHECK_UNAVAILABLE","OPERATION_OUTCOME_UNKNOWN","DEPENDENCY_UNAVAILABLE" -> 503;
            case "DUPLICATE_LABEL","DUPLICATE_COMBINATION","SHIFT_OVERLAP","PROTECTED_RESERVATION",
                 "LEGACY_RESERVATION_BLOCK","SHIFT_ALREADY_STARTED","IDEMPOTENCY_CONFLICT" -> 409;
            default -> 500;
        };
    }
    public Mono<ServerResponse> error(Throwable failure) {
        return Mono.deferContextual(context -> {
        AvailabilityException known=null;
        for(Throwable e=failure;e!=null;e=e.getCause()) if(e instanceof AvailabilityException a) { known=a; break; }
        String code=known==null?"INTERNAL_ERROR":known.code();
        int status=status(code);
        var response=ServerResponse.status(status);
        if(status==503) response.header("Retry-After","1");
        AvailabilityTelemetry.httpError(context,code);
        // Solo este error tipado expone una explicación fija; las demás causas se ocultan.
        String message=status==500?"Error interno":known instanceof ShiftLocalTimeException temporal?temporal.publicMessage():code;
        return response.bodyValue(new ApiError(code,message,status,AvailabilityTelemetry.operationId(context),clock.instant()));
        });
    }
}

