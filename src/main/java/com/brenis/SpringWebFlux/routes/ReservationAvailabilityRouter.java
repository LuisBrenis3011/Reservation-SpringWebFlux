package com.brenis.SpringWebFlux.routes;
import org.springframework.context.annotation.*;
import org.springframework.web.reactive.function.server.*;
import com.brenis.SpringWebFlux.handlers.ReservationAvailabilityHandler;
import com.brenis.SpringWebFlux.configs.ReservationProperties;
@Configuration(proxyBeanMethods=false)
public class ReservationAvailabilityRouter {
    @Bean RouterFunction<ServerResponse> reservationAvailabilityRoutes(ReservationAvailabilityHandler handler,ReservationProperties properties){
        if(!properties.isEnabled())return request->reactor.core.publisher.Mono.empty();
        return RouterFunctions.route().GET("/restaurants/{restaurantId}/availability",handler::list).build();
    }
}
