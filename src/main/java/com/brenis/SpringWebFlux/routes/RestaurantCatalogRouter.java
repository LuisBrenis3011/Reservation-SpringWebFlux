package com.brenis.SpringWebFlux.routes;

import com.brenis.SpringWebFlux.handlers.RestaurantCatalogHandler;
import com.brenis.SpringWebFlux.services.definitions.RestaurantCatalogService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.ServerResponse;
import static org.springframework.web.reactive.function.server.RouterFunctions.route;
@Configuration
public class RestaurantCatalogRouter {

//    private final RestaurantCatalogHandler restaurantCatalogHandler;

    @Bean
    public RouterFunction<ServerResponse> routes(RestaurantCatalogHandler handler) {

        return route()
                .path("/restaurants", builder -> builder
                        .GET(BY_NAME_URL, handler::getRestaurantByName)
                        .GET("", request -> {
                            if (request.queryParam("cousinType").isPresent()) {
                                return handler.getRestaurantsByCousinType(request);
                            }
                            if (request.queryParam("prices").isPresent()) {
                                return handler.getRestaurantBetweenPrice(request);
                            }
                            if (request.queryParam("city").isPresent()) {
                                return handler.getRestaurantsByCity(request);
                            } else {
                                return handler.getAllRestaurants(request);
                            }
                        })
                )
                .build();
    }



    private final static String BY_NAME_URL = "/{name}";


}
