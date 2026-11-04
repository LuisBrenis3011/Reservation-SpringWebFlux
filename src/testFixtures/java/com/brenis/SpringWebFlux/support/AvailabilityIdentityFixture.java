package com.brenis.SpringWebFlux.support;

import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.test.web.reactive.server.SecurityMockServerConfigurers;
import org.springframework.test.web.reactive.server.WebTestClientConfigurer;

import java.time.Clock;
import java.util.List;
import java.util.UUID;

/** Solo para WebTestClient: no firma tokens ni configura un emisor en la aplicación. */
public final class AvailabilityIdentityFixture {
    private AvailabilityIdentityFixture() { }

    public static Jwt managerJwt(UUID restaurantId, Clock clock) {
        return Jwt.withTokenValue("test-only-not-a-signed-token")
                .header("alg", "RS256")
                .subject("test-manager")
                .issuer("https://issuer.example.test")
                .audience(List.of("eats-hub-catalog"))
                .issuedAt(clock.instant().minusSeconds(60))
                .notBefore(clock.instant().minusSeconds(60))
                .expiresAt(clock.instant().plusSeconds(3600))
                .claim("roles", List.of("RESTAURANT_MANAGER"))
                .claim("restaurant_ids", List.of(restaurantId.toString()))
                .build();
    }

    public static WebTestClientConfigurer manager(UUID restaurantId, Clock clock) {
        return SecurityMockServerConfigurers.mockJwt().jwt(managerJwt(restaurantId, clock))
                .authorities(new SimpleGrantedAuthority("ROLE_RESTAURANT_MANAGER"));
    }
}
