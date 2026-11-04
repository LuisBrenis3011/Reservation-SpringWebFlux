package com.brenis.SpringWebFlux.handlers;
import java.security.Principal;
import java.util.*;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.*;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.services.definitions.ReservationQueryService;
@Component
public class ReservationQueryHandler {
    private final ReservationQueryService service;private final ReservationHttpSupport errors;private final AvailabilityHttpSupport common;
    public ReservationQueryHandler(ReservationQueryService service,ReservationHttpSupport errors,AvailabilityHttpSupport common){this.service=service;this.errors=errors;this.common=common;}
    private Mono<? extends Principal> principal(ServerRequest request){return request.principal().switchIfEmpty(Mono.error(new AvailabilityException("UNAUTHENTICATED","Autenticación requerida")));}
    private int number(ServerRequest request,String field,int fallback){
        var values=request.queryParams().get(field);if(values==null)return fallback;
        if(values.size()!=1||!values.getFirst().matches("[0-9]+"))throw new AvailabilityException("INVALID_REQUEST","Paginación inválida");
        try{return Integer.parseInt(values.getFirst());}catch(NumberFormatException e){throw new AvailabilityException("INVALID_REQUEST","Paginación inválida",e);}
    }
    private String status(ServerRequest request){var value=request.queryParams().get("status");if(value==null)return null;
        if(value.size()!=1||!Set.of("CONFIRMED","CANCELLED").contains(value.getFirst()))throw new AvailabilityException("INVALID_REQUEST","Estado inválido");return value.getFirst();}
    private void params(ServerRequest request,Set<String> allowed){if(!allowed.containsAll(request.queryParams().keySet()))throw new AvailabilityException("INVALID_REQUEST","Parámetros inválidos");}
    private Mono<ServerResponse> result(Object value){
        var builder=ServerResponse.ok();if(value instanceof ManagedReservationResponse row)builder.eTag(common.etag(row.version()));
        return builder.bodyValue(value);
    }
    private Mono<ServerResponse> execute(ServerRequest request,java.util.function.Function<Principal,Mono<?>> operation){
        return common.observe(request,()->principal(request).flatMap(actor->Mono.defer(()->operation.apply(actor)).flatMap(this::result)).onErrorResume(errors::error));
    }
    public Mono<ServerResponse> mine(ServerRequest request){return execute(request,actor->{params(request,Set.of("page","size","status"));return service.mine(actor,number(request,"page",0),number(request,"size",20),status(request));});}
    public Mono<ServerResponse> byRestaurant(ServerRequest request){return execute(request,actor->{params(request,Set.of("page","size"));return service.byRestaurant(actor,common.uuid(request.pathVariable("restaurantId")),number(request,"page",0),number(request,"size",20));});}
    public Mono<ServerResponse> managed(ServerRequest request){return execute(request,actor->{params(request,Set.of());return service.managed(actor,common.uuid(request.pathVariable("restaurantId")),common.uuid(request.pathVariable("reservationId")));});}
    public Mono<ServerResponse> legacy(ServerRequest request){return execute(request,actor->{params(request,Set.of());return service.legacy(actor,common.uuid(request.pathVariable("restaurantId")),request.pathVariable("legacyRef"));});}
    public Mono<ServerResponse> oldById(ServerRequest request){return execute(request,actor->{params(request,Set.of());return service.oldById(actor,common.uuid(request.pathVariable("id")));});}
}
