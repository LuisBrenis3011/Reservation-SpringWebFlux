package com.brenis.SpringWebFlux.routes;

import com.brenis.SpringWebFlux.configs.AvailabilityProperties;
import com.brenis.SpringWebFlux.handlers.TableCombinationHandler;
import org.springframework.context.annotation.*;
import org.springframework.web.reactive.function.server.*;
import reactor.core.publisher.Mono;

@Configuration(proxyBeanMethods=false)
public class TableCombinationRouter {
    @Bean
    public RouterFunction<ServerResponse> tableCombinationRoutes(TableCombinationHandler handler,AvailabilityProperties properties) {
        if(!properties.isEnabled()) return request -> Mono.empty();
        String collection="/restaurants/{restaurantId}/table-combinations";
        return RouterFunctions.route().POST(collection,handler::create).GET(collection,handler::list)
                .GET(collection+"/{combinationId}",handler::read).PUT(collection+"/{combinationId}",handler::replace).build();
    }
}
