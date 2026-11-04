package com.brenis.SpringWebFlux.support;

import com.brenis.SpringWebFlux.configs.AvailabilityProperties;
import com.brenis.SpringWebFlux.configs.AvailabilitySecurityConfig;
import com.brenis.SpringWebFlux.services.impls.RestaurantAccessPolicy;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import reactor.test.StepVerifier;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import static org.assertj.core.api.Assertions.assertThat;

class AvailabilitySecurityTests {
    final UUID restaurant = UUID.randomUUID();
    final AvailabilityClockFixture clock = new AvailabilityClockFixture(Instant.parse("2026-11-01T10:00:00Z"));
    final RestaurantAccessPolicy policy = new RestaurantAccessPolicy();

    private Jwt.Builder copyJwt() {
        Jwt source=AvailabilityIdentityFixture.managerJwt(restaurant,clock);
        return Jwt.withTokenValue(source.getTokenValue()).headers(h -> h.putAll(source.getHeaders()))
                .claims(c -> c.putAll(source.getClaims()));
    }
    @Test void encargadoPropioPuedeAcceder() {
        StepVerifier.create(policy.requireManager(new JwtAuthenticationToken(
                AvailabilityIdentityFixture.managerJwt(restaurant, clock)), restaurant)).verifyComplete();
    }
    @Test void restauranteAjenoSeRechaza() {
        StepVerifier.create(policy.requireManager(new JwtAuthenticationToken(
                AvailabilityIdentityFixture.managerJwt(UUID.randomUUID(), clock)), restaurant))
                .expectErrorMatches(e -> e.getMessage().contains("FORBIDDEN")).verify();
    }
    @ParameterizedTest @ValueSource(strings={"admin_user", "free_user", "premium_user"})
    void rolesAntiguosNoConcedenAcceso(String role) {
        Jwt jwt = copyJwt()
                .claim("roles", List.of(role)).build();
        StepVerifier.create(policy.requireManager(new JwtAuthenticationToken(jwt), restaurant))
                .expectErrorMatches(e -> e.getMessage().contains("FORBIDDEN")).verify();
    }
    @ParameterizedTest @ValueSource(strings={"issuer", "audience", "expired", "future", "subject"})
    void claimsInvalidasSeRechazanPorValidadorReal(String invalid) {
        AvailabilityProperties props = new AvailabilityProperties();
        props.setIssuerUri("https://issuer.example.test");
        Jwt.Builder jwt = copyJwt();
        switch (invalid) {
            case "issuer" -> jwt.issuer("https://other.example.test");
            case "audience" -> jwt.audience(List.of("other-api"));
            case "expired" -> jwt.issuedAt(clock.instant().minusSeconds(600))
                    .expiresAt(clock.instant().minusSeconds(120));
            case "future" -> jwt.notBefore(clock.instant().plusSeconds(120));
            case "subject" -> jwt.subject("");
            default -> throw new IllegalArgumentException(invalid);
        }
        assertThat(new AvailabilitySecurityConfig().jwtValidator(props, clock)
                .validate(jwt.build()).hasErrors()).isTrue();
    }
    @Test void claimsValidasPasanConRelojFijo() {
        AvailabilityProperties props = new AvailabilityProperties();
        props.setIssuerUri("https://issuer.example.test");
        assertThat(new AvailabilitySecurityConfig().jwtValidator(props, clock)
                .validate(AvailabilityIdentityFixture.managerJwt(restaurant, clock)).hasErrors()).isFalse();
    }
}

