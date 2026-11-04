package com.brenis.SpringWebFlux.routes;
import org.springframework.context.annotation.*;
import org.springframework.web.reactive.function.server.*;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.configs.AvailabilityProperties;
import com.brenis.SpringWebFlux.handlers.RestaurantShiftHandler;
@Configuration(proxyBeanMethods=false)
public class RestaurantShiftRouter {
    @Bean public RouterFunction<ServerResponse> restaurantShiftRoutes(RestaurantShiftHandler handler,AvailabilityProperties properties){
        if(!properties.isEnabled())return request -> Mono.empty();
        return RouterFunctions.route().GET("/restaurants/{restaurantId}/time-zone",handler::readZone)
            .PUT("/restaurants/{restaurantId}/time-zone",handler::replaceZone)
            .POST("/restaurants/{restaurantId}/shifts",handler::create).GET("/restaurants/{restaurantId}/shifts",handler::list)
            .GET("/restaurants/{restaurantId}/shifts/{shiftId}",handler::read)
            .PUT("/restaurants/{restaurantId}/shifts/{shiftId}",handler::replace).build();
    }
}
