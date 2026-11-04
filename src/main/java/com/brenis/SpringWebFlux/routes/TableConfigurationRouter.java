package com.brenis.SpringWebFlux.routes;

import com.brenis.SpringWebFlux.configs.AvailabilityProperties;
import com.brenis.SpringWebFlux.handlers.TableConfigurationHandler;
import org.springframework.context.annotation.*;
import org.springframework.web.reactive.function.server.*;
import reactor.core.publisher.Mono;

@Configuration(proxyBeanMethods=false)
public class TableConfigurationRouter {
    @Bean
    public RouterFunction<ServerResponse> tableConfigurationRoutes(TableConfigurationHandler handler,AvailabilityProperties properties) {
        // La cadena de seguridad conserva 404 incluso si no hay rutas registradas.
        if(!properties.isEnabled()) return request -> Mono.empty();
        String collection="/restaurants/{restaurantId}/tables";
        return RouterFunctions.route().POST(collection,handler::create).GET(collection,handler::list)
                .GET(collection+"/{tableId}",handler::read)
                .PATCH(collection+"/{tableId}",handler::patch).build();
    }
}

