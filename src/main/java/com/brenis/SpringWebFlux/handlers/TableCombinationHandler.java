package com.brenis.SpringWebFlux.handlers;

import com.brenis.SpringWebFlux.dtos.requests.TableCombinationRequest;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.services.definitions.TableCombinationService;
import com.brenis.SpringWebFlux.services.impls.RestaurantAccessPolicy;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.*;
import reactor.core.publisher.Mono;
import tools.jackson.databind.json.JsonMapper;
import java.security.Principal;
import java.util.UUID;
import java.util.function.BiFunction;

@Component
public class TableCombinationHandler {
    private final TableCombinationService combinations;
    private final RestaurantAccessPolicy access;
    private final AvailabilityHttpSupport http;
    private final JsonMapper json=JsonMapper.builder().build();
    public TableCombinationHandler(TableCombinationService combinations,RestaurantAccessPolicy access,AvailabilityHttpSupport http) {
        this.combinations=combinations; this.access=access; this.http=http;
    }
    private Mono<ServerResponse> authorized(ServerRequest request,BiFunction<Principal,UUID,Mono<ServerResponse>> action) {
        return http.observe(request,() -> Mono.defer(() -> request.principal()
                .switchIfEmpty(Mono.error(new AvailabilityException("UNAUTHENTICATED","Autenticacion requerida")))
                .flatMap(principal -> {
                    UUID owner=http.uuid(request.pathVariable("restaurantId"));
                    return access.requireManager(principal,owner).then(Mono.defer(() -> action.apply(principal,owner)));
                })).onErrorResume(http::error));
    }
    public Mono<ServerResponse> create(ServerRequest request) {
        return authorized(request,(principal,owner) -> {
            var headers=http.metadata(request,false);
            return http.readBody(request,TableCombinationRequest.class).flatMap(input -> {
                var command=http.command(headers,"POST","/restaurants/"+owner+"/table-combinations",
                        json.writeValueAsString(input),201,null);
                return combinations.create(principal,owner,input,command).flatMap(http::response);
            });
        });
    }
    public Mono<ServerResponse> list(ServerRequest request) {
        return authorized(request,(principal,owner) -> combinations.list(principal,owner).flatMap(http::response));
    }
    public Mono<ServerResponse> read(ServerRequest request) {
        return authorized(request,(principal,owner) -> combinations.read(principal,owner,
                http.uuid(request.pathVariable("combinationId"))).flatMap(http::response));
    }
    public Mono<ServerResponse> replace(ServerRequest request) {
        return authorized(request,(principal,owner) -> {
            UUID id=http.uuid(request.pathVariable("combinationId"));
            var headers=http.metadata(request,true);
            return http.readBody(request,TableCombinationRequest.class).flatMap(input -> {
                var command=http.command(headers,"PUT","/restaurants/"+owner+"/table-combinations/"+id,
                        json.writeValueAsString(input),200,null);
                return combinations.replace(principal,owner,id,input,command).flatMap(http::response);
            });
        });
    }
}
