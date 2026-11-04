package com.brenis.SpringWebFlux.support;

import com.brenis.SpringWebFlux.handlers.AvailabilityHttpSupport;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.web.reactive.function.server.MockServerRequest;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.web.reactive.function.server.RouterFunctions;
import org.springframework.web.reactive.function.server.RequestPredicates;
import java.time.Instant;
import static org.assertj.core.api.Assertions.*;

class AvailabilityHttpSupportTests {
    final AvailabilityHttpSupport support = new AvailabilityHttpSupport(
            new AvailabilityClockFixture(Instant.parse("2026-11-01T10:00:00Z")));

    @Test void headersValidosProducenMetadata() {
        var request = MockServerRequest.builder().header("Idempotency-Key", "same-key")
                .header(HttpHeaders.IF_MATCH, "\"42\"").build();
        var metadata = support.metadata(request, true);
        assertThat(metadata.idempotencyKey()).isEqualTo("same-key");
        assertThat(metadata.expectedRevision()).isEqualTo(42L);
    }
    @ParameterizedTest @ValueSource(strings={"42", "W/\"42\"", "\"-1\"", "*", ""})
    void etagNoFuerteSeRechaza(String value) {
        var request = MockServerRequest.builder().header("Idempotency-Key", "key")
                .header(HttpHeaders.IF_MATCH, value).build();
        assertThatThrownBy(() -> support.metadata(request, true))
                .isInstanceOf(AvailabilityException.class).hasMessageContaining("INVALID_REQUEST");
    }
    @Test void faltaClaveSeRechaza() {
        assertThatThrownBy(() -> support.metadata(MockServerRequest.builder().build(), false))
                .isInstanceOf(AvailabilityException.class).hasMessageContaining("INVALID_REQUEST");
    }
    @Test void claveDemasiadoLargaSeRechaza() {
        var request = MockServerRequest.builder().header("Idempotency-Key", "x".repeat(129)).build();
        assertThatThrownBy(() -> support.metadata(request, false))
                .isInstanceOf(AvailabilityException.class);
    }
    @Test void postNoExigeRevision() {
        var request = MockServerRequest.builder().header("Idempotency-Key", "key").build();
        assertThat(support.metadata(request, false).expectedRevision()).isNull();
    }
    @Test void errorNoFiltraDetalleInterno() {
        var router = RouterFunctions.route(RequestPredicates.GET("/probe"),
                r -> support.error(new RuntimeException("secret-password-and-stack")));
        WebTestClient.bindToRouterFunction(router).build().get().uri("/probe").exchange()
                .expectStatus().isEqualTo(500).expectBody()
                .jsonPath("$.code").isEqualTo("INTERNAL_ERROR")
                .jsonPath("$.status").isEqualTo(500)
                .jsonPath("$.operationId").isNotEmpty()
                .jsonPath("$.timestamp").isNotEmpty()
                .jsonPath("$.message").value(value -> assertThat(value.toString())
                        .doesNotContain("secret-password-and-stack"));
    }
    @Test void falloComprobacionDa503YRetryAfter() {
        var router = RouterFunctions.route(RequestPredicates.GET("/probe"), r ->
                support.error(new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE", "Reintentar")));
        WebTestClient.bindToRouterFunction(router).build().get().uri("/probe").exchange()
                .expectStatus().isEqualTo(503).expectHeader().valueEquals("Retry-After", "1")
                .expectBody().jsonPath("$.code").isEqualTo("COMMITMENT_CHECK_UNAVAILABLE");
    }
}

