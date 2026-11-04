package com.brenis.SpringWebFlux.services.impls;

import java.security.Principal;
import java.util.*;
import org.springframework.stereotype.Component;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;

@Component
public class ReservationAccessPolicy {
    public record Actor(String issuer,String subject,boolean isCustomer,Set<UUID> managerRestaurantIds) {
        public boolean manages(UUID restaurant){return managerRestaurantIds.contains(restaurant);}
    }
    public Actor actor(Principal principal){
        if(!(principal instanceof JwtAuthenticationToken token)||!token.isAuthenticated()) throw error("UNAUTHENTICATED");
        var jwt=token.getToken();
        if(jwt.getIssuer()==null||jwt.getSubject()==null||jwt.getSubject().isBlank()) throw error("UNAUTHENTICATED");
        List<String> roles=jwt.getClaimAsStringList("roles");if(roles==null)roles=List.of();
        Set<UUID> restaurants=new HashSet<>();
        if(roles.contains("RESTAURANT_MANAGER")){
            List<String> ids=jwt.getClaimAsStringList("restaurant_ids");
            if(ids!=null)for(String id:ids){try{restaurants.add(UUID.fromString(id));}catch(RuntimeException e){throw error("FORBIDDEN");}}
        }
        return new Actor(jwt.getIssuer().toString(),jwt.getSubject(),roles.contains("CUSTOMER"),Set.copyOf(restaurants));
    }
    public void requireCustomer(Actor actor){if(!actor.isCustomer())throw error("FORBIDDEN");}
    public void requireAccess(Actor actor,ManagedReservationCollection reservation){
        if(actor.manages(reservation.restaurantId()))return;
        requireCustomer(actor);
        if(!actor.issuer().equals(reservation.customerIssuer())||!actor.subject().equals(reservation.customerSubject()))throw error("NOT_FOUND");
    }
    private AvailabilityException error(String code){return new AvailabilityException(code,code);}
}
