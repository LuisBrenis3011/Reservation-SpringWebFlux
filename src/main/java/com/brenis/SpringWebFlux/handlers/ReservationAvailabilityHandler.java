package com.brenis.SpringWebFlux.handlers;
import java.time.LocalDate;
import java.util.Set;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.*;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.services.definitions.ReservationAvailabilityService;
@Component
public class ReservationAvailabilityHandler {
    private final ReservationAvailabilityService service; private final AvailabilityHttpSupport common;
    private final ReservationHttpSupport errors;
    public ReservationAvailabilityHandler(ReservationAvailabilityService service,AvailabilityHttpSupport common,ReservationHttpSupport errors){this.service=service;this.common=common;this.errors=errors;}
    public Mono<ServerResponse> list(ServerRequest request){
        return common.observe(request,()->Mono.defer(()->{
            var params=request.queryParams();
            if(!params.keySet().equals(Set.of("date","partySize"))||params.get("date").size()!=1||params.get("partySize").size()!=1)
                throw new AvailabilityException("INVALID_REQUEST","Parámetros inválidos");
            String date=params.getFirst("date"),size=params.getFirst("partySize");
            if(!date.matches("\\d{4}-\\d{2}-\\d{2}")||!size.matches("-?[0-9]+"))throw new AvailabilityException("INVALID_REQUEST","Formato inválido");
            LocalDate day;int group;
            try{day=LocalDate.parse(date);group=Integer.parseInt(size);}catch(RuntimeException e){throw new AvailabilityException("INVALID_REQUEST","Formato inválido",e);}
            if(group<1||group>20)throw new AvailabilityException("VALIDATION_ERROR","El grupo debe tener entre 1 y 20 personas");
            return service.list(common.uuid(request.pathVariable("restaurantId")),day,group).flatMap(value->ServerResponse.ok().bodyValue(value));
        }).onErrorResume(errors::error));
    }
}
