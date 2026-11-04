package com.brenis.SpringWebFlux.routes;

import com.brenis.SpringWebFlux.handlers.ReservationHandler;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.ServerResponse;

import static org.springframework.web.reactive.function.server.RouterFunctions.route;

@Configuration
public class ReservationCrudRouter {

    @Bean
    public RouterFunction<ServerResponse> reservationRoutes(ReservationHandler handler) {
        return route()
                .path("/reservation", builder -> builder
                        .POST("", handler::postReservation)
                        .GET("/{id}", handler::getReservationsById)
                        .PUT("/{id}", handler::updateReservation)
                        .DELETE("/{id}", handler::deleteReservation)
                )
                .build();
    }
}
