package com.brenis.SpringWebFlux.handlers;
import com.brenis.SpringWebFlux.dtos.requests.RestaurantShiftRequest;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.*;
import reactor.core.publisher.Mono;
import tools.jackson.databind.json.JsonMapper;
import com.brenis.SpringWebFlux.services.definitions.RestaurantShiftService;
import com.brenis.SpringWebFlux.services.impls.RestaurantAccessPolicy;
import com.brenis.SpringWebFlux.dtos.requests.RestaurantTimeZoneRequest;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
@Component
public class RestaurantShiftHandler {
    private final RestaurantShiftService service;
    private final RestaurantAccessPolicy access;
    private final AvailabilityHttpSupport http;
    private final JsonMapper json=JsonMapper.builder().build();
    public RestaurantShiftHandler(RestaurantShiftService service,RestaurantAccessPolicy access,AvailabilityHttpSupport http){this.service=service;this.access=access;this.http=http;}
    private Mono<ServerResponse> authorized(ServerRequest request,java.util.function.BiFunction<java.security.Principal,UUID,Mono<ServerResponse>> action){
        return http.observe(request,() -> Mono.defer(() -> request.principal().switchIfEmpty(Mono.error(new AvailabilityException("UNAUTHENTICATED","Token requerido"))).flatMap(actor -> {
            UUID owner=http.uuid(request.pathVariable("restaurantId"));
            return access.requireManager(actor,owner).then(Mono.defer(() -> action.apply(actor,owner)));
        })).onErrorResume(http::error));
    }
    private Mono<ServerResponse> handle(ServerRequest request,boolean update){
        return authorized(request,(actor,owner) -> {
                if(!update)return service.readZone(actor,owner).flatMap(http::response);
                var headers=http.metadata(request,true);
                return http.readBody(request,RestaurantTimeZoneRequest.class).flatMap(input -> service.replaceZone(actor,owner,input,
                    http.command(headers,"PUT","/restaurants/"+owner+"/time-zone",json.writeValueAsString(input),200,null)).flatMap(http::response));
        });
    }
    public Mono<ServerResponse> create(ServerRequest request){return authorized(request,(actor,owner) -> {
        var headers=http.metadata(request,false);
        return http.readBody(request,RestaurantShiftRequest.class).flatMap(input -> service.create(actor,owner,input,
            http.command(headers,"POST","/restaurants/"+owner+"/shifts",json.writeValueAsString(input),201,null)).flatMap(http::response));
    });}
    public Mono<ServerResponse> list(ServerRequest request){return authorized(request,(actor,owner) -> service.list(actor,owner).flatMap(http::response));}
    public Mono<ServerResponse> replace(ServerRequest request){return authorized(request,(actor,owner) -> {
        UUID id=http.uuid(request.pathVariable("shiftId"));var headers=http.metadata(request,true);
        return http.readBody(request,RestaurantShiftRequest.class).flatMap(input -> service.replace(actor,owner,id,input,
            http.command(headers,"PUT","/restaurants/"+owner+"/shifts/"+id,json.writeValueAsString(input),200,null)).flatMap(http::response));
    });}
    public Mono<ServerResponse> read(ServerRequest request){return authorized(request,(actor,owner) -> service.read(actor,owner,http.uuid(request.pathVariable("shiftId"))).flatMap(http::response));}
    public Mono<ServerResponse> readZone(ServerRequest request){return handle(request,false);}
    public Mono<ServerResponse> replaceZone(ServerRequest request){return handle(request,true);}
}
