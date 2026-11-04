package com.brenis.SpringWebFlux.support;

import java.security.Principal;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

/** Reutiliza el replica set, el reloj y el restaurante de pruebas existentes. */
@org.springframework.test.context.junit.jupiter.SpringJUnitConfig(ManagedReservationIntegrationSupport.Configuration.class)
public abstract class ManagedReservationIntegrationSupport extends AvailabilityTableIntegrationSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false)
    @org.springframework.context.annotation.Import({AvailabilityTableIntegrationSupport.Configuration.class,
        com.brenis.SpringWebFlux.configs.ReservationIndexesContributor.class,
        com.brenis.SpringWebFlux.repositories.ManagedReservationRepository.class,
        com.brenis.SpringWebFlux.validators.ReservationIntegrityValidator.class,
        com.brenis.SpringWebFlux.services.impls.ReservationAccessPolicy.class,
        com.brenis.SpringWebFlux.validators.ReservationTimePolicy.class,
        com.brenis.SpringWebFlux.services.impls.ReservationAssignmentPolicy.class,
        com.brenis.SpringWebFlux.repositories.ReservationOccupancyReader.class,
        com.brenis.SpringWebFlux.services.impls.LegacyReservationWriteBarrier.class})
    public static class Configuration {}
    @org.junit.jupiter.api.BeforeEach void authenticatedManager(){
        manager=new JwtAuthenticationToken(ReservationIdentityFixture.manager(restaurant,clock),
            java.util.List.of(new org.springframework.security.core.authority.SimpleGrantedAuthority("ROLE_RESTAURANT_MANAGER")));
    }
    protected Principal customer(String subject) {
        return new JwtAuthenticationToken(ReservationIdentityFixture.customer(subject, clock),
            java.util.List.of(new org.springframework.security.core.authority.SimpleGrantedAuthority("ROLE_CUSTOMER")));
    }

    protected Principal otherCustomer() {
        return new JwtAuthenticationToken(ReservationIdentityFixture.otherCustomer(clock),
            java.util.List.of(new org.springframework.security.core.authority.SimpleGrantedAuthority("ROLE_CUSTOMER")));
    }

    protected Principal dual(String subject) {
        return new JwtAuthenticationToken(ReservationIdentityFixture.dual(subject, restaurant, clock),
            java.util.List.of(new org.springframework.security.core.authority.SimpleGrantedAuthority("ROLE_CUSTOMER"),
                new org.springframework.security.core.authority.SimpleGrantedAuthority("ROLE_RESTAURANT_MANAGER")));
    }
}
