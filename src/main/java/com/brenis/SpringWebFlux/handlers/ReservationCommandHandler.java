package com.brenis.SpringWebFlux.handlers;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.*;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.services.definitions.ReservationCommandService;
import com.brenis.SpringWebFlux.services.impls.ReservationAccessPolicy;
import com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator.Result;
import com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse;

@Component
public class ReservationCommandHandler {
    private final ReservationCommandService service;
    private final ReservationAccessPolicy access;
    private final ReservationHttpSupport http;
    private final AvailabilityHttpSupport common;
    public ReservationCommandHandler(ReservationCommandService service,ReservationAccessPolicy access,ReservationHttpSupport http,AvailabilityHttpSupport common){
        this.service=service;this.access=access;this.http=http;this.common=common;
    }
    public Mono<ServerResponse> confirm(ServerRequest request){
        return common.observe(request,()->request.principal().switchIfEmpty(Mono.error(new AvailabilityException("UNAUTHENTICATED","Autenticación requerida")))
            .flatMap(principal->{
                var actor=access.actor(principal);access.requireCustomer(actor);
                var owner=common.uuid(request.pathVariable("restaurantId"));
                return http.readBody(request).flatMap(body->service.confirm(principal,owner,body,
                    http.command(request,actor,http.canonicalBody(body),false,201,null))).flatMap(http::response);
            }).onErrorResume(http::error));
    }
    public Mono<ServerResponse> replace(ServerRequest request){
        return common.observe(request,()->request.principal().switchIfEmpty(Mono.error(new AvailabilityException("UNAUTHENTICATED","Autenticación requerida")))
            .flatMap(principal->{
                var actor=access.actor(principal);
                var owner=common.uuid(request.pathVariable("restaurantId"));
                if(!actor.isCustomer()&&!actor.manages(owner))throw new AvailabilityException("FORBIDDEN","Sin permiso para modificar reservas");
                var id=common.uuid(request.pathVariable("reservationId"));
                long version=http.expectedVersion(request);
                return http.readBody(request).flatMap(body->service.replace(principal,owner,id,version,body,
                    http.command(request,actor,http.canonicalBody(body),true,200,null))).flatMap(http::response);
            }).onErrorResume(http::error));
    }
    public Mono<ServerResponse> cancel(ServerRequest request){
        return common.observe(request,()->request.principal().switchIfEmpty(Mono.error(new AvailabilityException("UNAUTHENTICATED","Autenticación requerida")))
            .flatMap(principal->{
                var actor=access.actor(principal);
                var owner=common.uuid(request.pathVariable("restaurantId"));
                if(!actor.isCustomer()&&!actor.manages(owner))throw new AvailabilityException("FORBIDDEN","Sin permiso para cancelar reservas");
                var id=common.uuid(request.pathVariable("reservationId"));
                long version=http.expectedVersion(request);
                var command=http.command(request,actor,"",true,200,null);
                return request.bodyToMono(byte[].class).defaultIfEmpty(new byte[0]).flatMap(body->{
                    if(body.length!=0)return Mono.<Result<ManagedReservationResponse>>error(
                        new AvailabilityException("INVALID_REQUEST","Cancelación no admite cuerpo"));
                    return service.cancel(principal,owner,id,version,command);
                }).flatMap(http::response);
            }).onErrorResume(http::error));
    }
}
