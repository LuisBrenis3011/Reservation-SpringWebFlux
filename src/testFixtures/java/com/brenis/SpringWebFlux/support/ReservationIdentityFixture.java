package com.brenis.SpringWebFlux.support;

import java.time.Clock;
import java.util.List;
import java.util.UUID;
import org.springframework.security.oauth2.jwt.Jwt;

/** Identidades de prueba; no son tokens firmados ni credenciales reales. */
public final class ReservationIdentityFixture {
    private ReservationIdentityFixture() { }

    public static Jwt customer(String subject, Clock clock) {
        return identity(subject, List.of("CUSTOMER"), List.of(), clock);
    }

    public static Jwt otherCustomer(Clock clock) {
        return customer("other-customer", clock);
    }

    public static Jwt manager(UUID restaurant, Clock clock) {
        return AvailabilityIdentityFixture.managerJwt(restaurant, clock);
    }

    public static Jwt dual(String subject, UUID restaurant, Clock clock) {
        return identity(subject, List.of("CUSTOMER", "RESTAURANT_MANAGER"),
                List.of(restaurant.toString()), clock);
    }

    private static Jwt identity(String subject, List<String> roles, List<String> restaurants, Clock clock) {
        return Jwt.withTokenValue("test-only-not-a-signed-token")
                .header("alg", "RS256").subject(subject).issuer("https://issuer.example.test")
                .audience(List.of("eats-hub-catalog"))
                .issuedAt(clock.instant().minusSeconds(60)).notBefore(clock.instant().minusSeconds(60))
                .expiresAt(clock.instant().plusSeconds(3600))
                .claim("roles", roles).claim("restaurant_ids", restaurants).build();
    }
}
