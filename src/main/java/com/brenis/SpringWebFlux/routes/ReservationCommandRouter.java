package com.brenis.SpringWebFlux.routes;
import org.springframework.context.annotation.*;
import org.springframework.web.reactive.function.server.*;
import com.brenis.SpringWebFlux.handlers.ReservationCommandHandler;
@Configuration(proxyBeanMethods=false)
public class ReservationCommandRouter {
    @Bean RouterFunction<ServerResponse> reservationCommands(ReservationCommandHandler handler,com.brenis.SpringWebFlux.configs.ReservationProperties properties){
        if(!properties.isEnabled())return request->reactor.core.publisher.Mono.empty();
        return RouterFunctions.route().POST("/restaurants/{restaurantId}/reservations",handler::confirm)
            .PUT("/restaurants/{restaurantId}/reservations/{reservationId}",handler::replace)
            .POST("/restaurants/{restaurantId}/reservations/{reservationId}/cancellation",handler::cancel).build();
    }
}
