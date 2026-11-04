package com.brenis.SpringWebFlux.services.impls;
import java.security.Principal;
import java.util.*;
import org.springframework.stereotype.Component;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
@Component
public class RestaurantAccessPolicy {
    public Mono<Void> requireManager(Principal principal,UUID restaurantId) {
        if(!(principal instanceof JwtAuthenticationToken token))
            return Mono.error(new AvailabilityException("UNAUTHENTICATED","Autenticación requerida"));
        Object roles=token.getToken().getClaims().get("roles"), ids=token.getToken().getClaims().get("restaurant_ids");
        boolean permitted=roles instanceof Collection<?> r && r.contains("RESTAURANT_MANAGER")
                && ids instanceof Collection<?> own && own.contains(restaurantId.toString());
        return permitted?Mono.empty():Mono.error(new AvailabilityException("FORBIDDEN","Sin permiso para restaurante"));
    }
}

