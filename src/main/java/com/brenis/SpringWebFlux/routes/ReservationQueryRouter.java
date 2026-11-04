package com.brenis.SpringWebFlux.routes;
import org.springframework.context.annotation.*;
import org.springframework.web.reactive.function.server.*;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.configs.ReservationProperties;
import com.brenis.SpringWebFlux.handlers.ReservationQueryHandler;
@Configuration(proxyBeanMethods=false)
public class ReservationQueryRouter {
    @Bean RouterFunction<ServerResponse> reservationQueries(ReservationQueryHandler handler,ReservationProperties properties){
        if(!properties.isEnabled())return request->Mono.empty();
        String path="/restaurants/{restaurantId}/reservations";
        return RouterFunctions.route().GET("/me/reservations",handler::mine).GET(path+"/legacy/{legacyRef}",handler::legacy)
            .GET(path+"/{reservationId}",handler::managed).GET(path,handler::byRestaurant).build();
    }
}
