package com.brenis.SpringWebFlux.handlers;

import com.brenis.SpringWebFlux.dtos.requests.TableCreateRequest;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.services.definitions.TableConfigurationService;
import com.brenis.SpringWebFlux.services.impls.RestaurantAccessPolicy;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.*;
import reactor.core.publisher.Mono;
import tools.jackson.databind.json.JsonMapper;
import java.security.Principal;
import java.util.UUID;
import java.util.function.BiFunction;

@Component
public class TableConfigurationHandler {
    private final TableConfigurationService tables;
    private final RestaurantAccessPolicy access;
    private final AvailabilityHttpSupport http;
    private final JsonMapper json=JsonMapper.builder().build();
    public TableConfigurationHandler(TableConfigurationService tables,RestaurantAccessPolicy access,AvailabilityHttpSupport http) {
        this.tables=tables; this.access=access; this.http=http;
    }
    private Mono<ServerResponse> authorized(ServerRequest request,
            BiFunction<Principal,UUID,Mono<ServerResponse>> action) {
        return http.observe(request,() -> Mono.defer(() -> request.principal()
                .switchIfEmpty(Mono.error(new AvailabilityException("UNAUTHENTICATED","Autenticación requerida")))
                .flatMap(principal -> {
                    UUID owner=http.uuid(request.pathVariable("restaurantId"));
                    return access.requireManager(principal,owner).then(Mono.defer(() -> action.apply(principal,owner)));
                })).onErrorResume(http::error));
    }
    public Mono<ServerResponse> create(ServerRequest request) {
        return authorized(request,(principal,owner) -> {
            var headers=http.metadata(request,false);
            return http.readBody(request,TableCreateRequest.class).flatMap(input -> {
                var command=http.command(headers,"POST","/restaurants/"+owner+"/tables",
                        json.writeValueAsString(input),201,null);
                return tables.create(principal,owner,input,command).flatMap(http::response);
            });
        });
    }
    public Mono<ServerResponse> list(ServerRequest request) {
        return authorized(request,(principal,owner) -> tables.list(principal,owner).flatMap(http::response));
    }
    public Mono<ServerResponse> read(ServerRequest request) {
        return authorized(request,(principal,owner) ->
                tables.read(principal,owner,http.uuid(request.pathVariable("tableId"))).flatMap(http::response));
    }
    public Mono<ServerResponse> patch(ServerRequest request) {
        return authorized(request,(principal,owner) -> {
            UUID table=http.uuid(request.pathVariable("tableId"));
            var headers=http.metadata(request,true);
            return http.readBody(request,TablePatchRequest.class).flatMap(input -> {
                var command=http.command(headers,"PATCH","/restaurants/"+owner+"/tables/"+table,
                        json.writeValueAsString(input),200,null);
                return tables.patch(principal,owner,table,input,command).flatMap(http::response);
            });
        });
    }
}

