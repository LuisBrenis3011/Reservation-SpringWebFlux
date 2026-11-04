package com.brenis.SpringWebFlux.handlers;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.util.*;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.*;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.*;
import com.brenis.SpringWebFlux.dtos.requests.ManagedReservationRequest;
import com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator.Result;
import com.brenis.SpringWebFlux.services.impls.ReservationAccessPolicy.Actor;
import tools.jackson.databind.json.JsonMapper;

@Component
public class ReservationHttpSupport {
    private final AvailabilityHttpSupport shared;
    private final Clock clock;
    private final JsonMapper json=JsonMapper.builder().build();
    public ReservationHttpSupport(AvailabilityHttpSupport shared,Clock clock){this.shared=shared;this.clock=clock;}
    public Mono<ManagedReservationRequest> readBody(ServerRequest request){
        return request.bodyToMono(String.class).switchIfEmpty(Mono.error(invalid())).flatMap(raw->{
            try{
                var tree=json.readTree(raw);
                if(!tree.isObject()||!tree.has("shiftId")||!tree.has("partySize"))throw invalid();
                for(var field:tree.properties())if(!Set.of("shiftId","partySize","notes").contains(field.getKey())||field.getValue().isNull())throw invalid();
                if(!tree.get("shiftId").isTextual()||!tree.get("partySize").isIntegralNumber()||!tree.get("partySize").canConvertToInt()
                    ||(tree.has("notes")&&!tree.get("notes").isTextual()))throw invalid();
                shared.uuid(json.treeToValue(tree.get("shiftId"),String.class));
                var dto=json.readValue(raw,ManagedReservationRequest.class);return Mono.just(dto);
            }catch(RuntimeException e){return Mono.error(invalid());}
        });
    }
    public CommandMetadata command(ServerRequest request,Actor actor,String canonicalBody,boolean update,int status,String location){
        String key=request.headers().firstHeader("Idempotency-Key");
        if(key==null||!key.matches("[!-~]{1,128}"))throw invalid();
        String match=request.headers().firstHeader("If-Match");
        if(update)expectedVersion(request);
        String path=request.path().replaceFirst("^/catalog(?=/)","");
        for(var variable:request.pathVariables().entrySet())if(Set.of("restaurantId","reservationId","id").contains(variable.getKey()))
            path=path.replace(variable.getValue(),shared.uuid(variable.getValue()).toString());
        return new CommandMetadata("rsv:"+hash(List.of(actor.issuer(),actor.subject(),key)),
            hash(Arrays.asList(actor.issuer(),actor.subject(),request.method().name(),path,canonicalBody,match)),null,status,location);
    }
    public long expectedVersion(ServerRequest request){String value=request.headers().firstHeader("If-Match");if(value==null||!value.matches("\"[0-9]+\""))throw invalid();try{return Long.parseLong(value.substring(1,value.length()-1));}catch(NumberFormatException e){throw invalid();}}
    public String canonicalBody(ManagedReservationRequest request){
        var values=new LinkedHashMap<String,Object>();values.put("shiftId",request.shiftId().toString());values.put("partySize",request.partySize());values.put("notes",request.notes());
        return json.writeValueAsString(values);
    }
    public Mono<ServerResponse> response(Result<ManagedReservationResponse> result){var builder=ServerResponse.status(result.httpStatus()).eTag(shared.etag(result.body().version()));if(result.location()!=null)builder.header("Location",result.location());return builder.bodyValue(result.body());}
    public Mono<ServerResponse> error(Throwable e){
        AvailabilityException known=null;for(Throwable t=e;t!=null;t=t.getCause())if(t instanceof AvailabilityException a){known=a;break;}
        String code=known==null?"INTERNAL_ERROR":known.code();int status=switch(code){
            case "NO_AVAILABILITY","DUPLICATE_RESERVATION","RESERVATION_WINDOW_CLOSED","RESERVATION_NOT_EDITABLE","LEGACY_RESERVATION_READ_ONLY"->409;
            case "RESERVATION_UNVERIFIABLE"->503;case "LEGACY_WRITES_RETIRED"->410;default->AvailabilityHttpSupport.status(code);};
        var response=ServerResponse.status(status);if(status==503)response.header("Retry-After","1");
        return Mono.deferContextual(ctx->response.bodyValue(new ApiError(code,status==500?"Error interno":code,status,
            com.brenis.SpringWebFlux.observability.AvailabilityTelemetry.operationId(ctx),clock.instant())));
    }
    private String hash(Object value){try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(json.writeValueAsString(value).getBytes(StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException(e);}}
    private AvailabilityException invalid(){return new AvailabilityException("INVALID_REQUEST","Solicitud inválida");}
}
