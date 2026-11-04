package com.brenis.SpringWebFlux.support;

import com.brenis.SpringWebFlux.observability.AvailabilityTelemetry;
import com.brenis.SpringWebFlux.handlers.AvailabilityHttpSupport;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import reactor.test.StepVerifier;
import org.slf4j.LoggerFactory;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.web.reactive.function.server.*;
import java.time.Clock;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import static org.assertj.core.api.Assertions.*;
import static com.brenis.SpringWebFlux.observability.AvailabilityTelemetry.Operation.*;

class AvailabilityTelemetryTests {
    final SimpleMeterRegistry meters=new SimpleMeterRegistry();
    final AvailabilityTelemetry telemetry=new AvailabilityTelemetry(meters);
    final UUID owner=UUID.randomUUID();
    final Logger logger=(Logger)LoggerFactory.getLogger(AvailabilityTelemetry.class);
    final ListAppender<ILoggingEvent> appender=new ListAppender<>();
    @BeforeEach void capture() { appender.start(); logger.addAppender(appender); }
    @AfterEach void cleanup() { logger.detachAppender(appender); appender.stop(); meters.close(); }
    @Test void mideUnaSuscripcionCompletaIncluidoMonoVoidSinEjecutarAntes() {
        AtomicInteger calls=new AtomicInteger();
        var operation=telemetry.observe(LEGACY,owner,() -> {
            calls.incrementAndGet(); return Mono.<Void>empty();
        });
        assertThat(calls).hasValue(0);
        StepVerifier.create(operation).verifyComplete();
        assertThat(calls).hasValue(1);
        assertThat(meters.get("availability.operations").tag("operation","legacy").counter().count()).isEqualTo(1);
        assertThat(meters.get("availability.operation.duration").timer().count()).isEqualTo(1);
    }
    @Test void bloqueoLegacyCuentaConflictoYConservaLaExcepcionOriginal() {
        var failure=new AvailabilityException("LEGACY_RESERVATION_BLOCK","private-label jwt-secret");
        StepVerifier.create(telemetry.observe(WRITE,owner,() -> Mono.error(failure)))
                .expectErrorMatches(e -> e==failure).verify();
        assertThat(meters.get("availability.legacy.blocks").counter().count()).isEqualTo(1);
        assertThat(meters.get("availability.conflicts").counter().count()).isEqualTo(1);
        assertThat(meters.find("availability.failures").counter()).isNull();
        assertThat(appender.list).allSatisfy(event -> {
            assertThat(event.getFormattedMessage()).contains("operationId=","restaurantId=","outcome=rejected","durationMs=")
                    .doesNotContain("private-label","jwt-secret");
            assertThat(event.getThrowableProxy()).isNull();
        });
    }
    @ParameterizedTest @ValueSource(strings={"COMMITMENT_CHECK_UNAVAILABLE","OPERATION_OUTCOME_UNKNOWN","INTERNAL_ERROR"})
    void falloSeCuentaSinAfirmarRollbackNiPublicarDetalle(String code) {
        StepVerifier.create(telemetry.observe(WRITE,owner,() -> Mono.error(new AvailabilityException(code,"secret"))))
                .expectError(AvailabilityException.class).verify();
        assertThat(meters.get("availability.failures").tag("code",code).counter().count()).isEqualTo(1);
        assertThat(appender.list.getFirst().getFormattedMessage()).doesNotContain("secret","rollback");
    }
    @Test void replayNoSeClasificaComoFalloNiMultiplicaEventosPorIntento() {
        StepVerifier.create(telemetry.observe(WRITE,owner,() -> telemetry.replay().thenReturn("original")))
                .expectNext("original").verifyComplete();
        assertThat(meters.get("availability.operations").tag("outcome","replay").counter().count()).isEqualTo(1);
        assertThat(meters.find("availability.failures").counter()).isNull();
    }
    @Test void cancelacionSeDistingueDeExito() {
        StepVerifier.create(telemetry.observe(READ,owner,Mono::never)).thenCancel().verify();
        assertThat(meters.get("availability.operations").tag("outcome","cancelled").counter().count()).isEqualTo(1);
    }
    @Test void datosDeIdentidadNuncaSonEtiquetasDeMetricas() {
        StepVerifier.create(telemetry.observe(WRITE,owner,() -> Mono.just("body-with-secret")))
                .expectNext("body-with-secret").verifyComplete();
        meters.getMeters().forEach(meter -> assertThat(meter.getId().getTags()).allSatisfy(tag -> {
            assertThat(tag.getKey()).isIn("operation","outcome","code");
            assertThat(tag.getValue()).doesNotContain(owner.toString(),"body-with-secret");
        }));
    }
    @Test void operationIdConectaErrorHttpYCoordinadorInclusoTrasCambiarThread() {
        var support=new AvailabilityHttpSupport(Clock.systemUTC(),telemetry);
        var router=RouterFunctions.route(RequestPredicates.GET("/probe"),request ->
            telemetry.observe(HTTP,owner,() -> telemetry.<ServerResponse>observe(WRITE,owner,
                    () -> Mono.error(new AvailabilityException("PROTECTED_RESERVATION","secret")))
                .publishOn(Schedulers.parallel()).onErrorResume(support::error)));
        WebTestClient.bindToRouterFunction(router).build().get().uri("/probe").exchange()
                .expectStatus().isEqualTo(409).expectBody().jsonPath("$.operationId").value(value -> {
                    assertThat(appender.list).hasSize(2);
                    assertThat(appender.list).allSatisfy(event ->
                            assertThat(event.getFormattedMessage()).contains("operationId="+value));
                });
        assertThat(meters.get("availability.operations").tag("operation","http").tag("code","PROTECTED_RESERVATION")
                .counter().count()).isEqualTo(1);
    }
    @Test void registryIndisponibleNoConvierteExitoEnError() {
        var broken=org.mockito.Mockito.mock(io.micrometer.core.instrument.MeterRegistry.class);
        org.mockito.Mockito.when(broken.counter(org.mockito.ArgumentMatchers.anyString(),
                org.mockito.ArgumentMatchers.<io.micrometer.core.instrument.Tag>anyIterable()))
                .thenThrow(new IllegalStateException("exporter-secret"));
        var safe=new AvailabilityTelemetry(broken);
        StepVerifier.create(safe.observe(WRITE,owner,() -> Mono.just("committed")))
                .expectNext("committed").verifyComplete();
        assertThat(appender.list).allSatisfy(event -> assertThat(event.getFormattedMessage()).doesNotContain("exporter-secret"));
    }
}

