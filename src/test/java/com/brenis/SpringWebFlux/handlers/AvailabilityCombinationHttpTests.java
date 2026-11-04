package com.brenis.SpringWebFlux.handlers;

import com.brenis.SpringWebFlux.configs.*;
import com.brenis.SpringWebFlux.dtos.requests.TableCombinationRequest;
import com.brenis.SpringWebFlux.dtos.responses.*;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.routes.TableCombinationRouter;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.services.impls.RestaurantAccessPolicy;
import com.brenis.SpringWebFlux.support.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.context.annotation.*;
import org.springframework.http.MediaType;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.web.reactive.config.EnableWebFlux;
import reactor.core.publisher.Mono;
import java.time.*;
import java.util.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.security.test.web.reactive.server.SecurityMockServerConfigurers.springSecurity;

class AvailabilityCombinationHttpTests {
    @Configuration(proxyBeanMethods=false) @EnableWebFlux
    @Import({AvailabilitySecurityConfig.class,AvailabilityHttpSupport.class,RestaurantAccessPolicy.class,
            AvailabilityMetricsConfig.class,com.brenis.SpringWebFlux.observability.AvailabilityTelemetry.class,
            TableCombinationHandler.class,TableCombinationRouter.class})
    static class WebConfiguration {
        @Bean AvailabilityProperties properties() {
            var p=new AvailabilityProperties(); p.setEnabled(true);
            p.setIssuerUri("https://issuer.example.test"); p.setJwkSetUri("https://issuer.example.test/jwks"); return p;
        }
        @Bean Clock clock() { return new AvailabilityClockFixture(Instant.parse("2026-11-01T10:00:00Z")); }
        @Bean TableCombinationService service() { return mock(TableCombinationService.class); }
    }
    @Configuration(proxyBeanMethods=false) static class DisabledConfiguration {
        @Bean @Primary AvailabilityProperties disabled() { return new AvailabilityProperties(); }
    }
    AnnotationConfigApplicationContext context;
    WebTestClient client;
    TableCombinationService service;
    final UUID restaurant=UUID.randomUUID(), combination=UUID.randomUUID(), a=UUID.randomUUID(), b=UUID.randomUUID();
    String collection() { return "/restaurants/"+restaurant+"/table-combinations"; }
    String etag(long value) { return "\""+value+"\""; }
    @BeforeEach void setup() { open(false); }
    void open(boolean disabled) {
        context=new AnnotationConfigApplicationContext(); context.register(WebConfiguration.class);
        if(disabled) context.register(DisabledConfiguration.class);
        context.refresh(); service=context.getBean(TableCombinationService.class);
        client=WebTestClient.bindToApplicationContext(context).apply(springSecurity()).build();
    }
    @AfterEach void close() { context.close(); }
    WebTestClient manager(UUID owner) { return client.mutateWith(AvailabilityIdentityFixture.manager(owner,context.getBean(Clock.class))); }
    Map<String,Object> body() { return Map.of("tableIds",List.of(a.toString(),b.toString())); }
    TableCombinationResponse response() { return new TableCombinationResponse(combination,restaurant,List.of(a,b),6,3); }
    @Test void esc0201_postPropioDevuelveContratoLocationYETagSinMemberKey() {
        String location="/catalog"+collection()+"/"+combination;
        when(service.create(any(),eq(restaurant),any(),any())).thenReturn(Mono.just(
                new RestaurantOperationCoordinator.Result<>(response(),3,201,location)));
        manager(restaurant).post().uri(collection()).header("Idempotency-Key","create").contentType(MediaType.APPLICATION_JSON)
                .bodyValue(body()).exchange().expectStatus().isCreated().expectHeader().valueEquals("Location",location)
                .expectHeader().valueEquals("ETag",etag(3)).expectBody().jsonPath("$.id").isEqualTo(combination.toString())
                .jsonPath("$.restaurantId").isEqualTo(restaurant.toString()).jsonPath("$.tableIds.length()").isEqualTo(2)
                .jsonPath("$.capacity").isEqualTo(6).jsonPath("$.revision").isEqualTo(3)
                .jsonPath("$.memberKey").doesNotExist();
        verify(service).create(any(),eq(restaurant),eq(new TableCombinationRequest(List.of(a.toString(),b.toString()))),
                argThat(c -> c.idempotencyKey().equals("create") && c.fingerprint()!=null && c.httpStatus()==201));
    }
    @Test void esc0205_getColeccionYRecursoNoExigenClave() {
        when(service.list(any(),eq(restaurant))).thenReturn(Mono.just(new RestaurantOperationCoordinator.Result<>(
                new TableCombinationListResponse(List.of(response()),3),3,200,null)));
        when(service.read(any(),eq(restaurant),eq(combination))).thenReturn(Mono.just(
                new RestaurantOperationCoordinator.Result<>(response(),3,200,null)));
        manager(restaurant).get().uri(collection()).exchange().expectStatus().isOk().expectHeader().valueEquals("ETag",etag(3))
                .expectBody().jsonPath("$.items[0].capacity").isEqualTo(6).jsonPath("$.revision").isEqualTo(3)
                .jsonPath("$.totalCapacity").doesNotExist();
        manager(restaurant).get().uri(collection()+"/"+combination).exchange().expectStatus().isOk()
                .expectHeader().valueEquals("ETag",etag(3)).expectBody().jsonPath("$.id").isEqualTo(combination.toString());
    }
    @Test void esc0202_sinTokenOEncargadoAjenoNoEjecutaServicio() {
        client.get().uri(collection()).exchange().expectStatus().isUnauthorized();
        client.post().uri(collection()).exchange().expectStatus().isUnauthorized();
        client.put().uri(collection()+"/"+combination).exchange().expectStatus().isUnauthorized();
        manager(UUID.randomUUID()).get().uri(collection()).exchange().expectStatus().isForbidden();
        manager(UUID.randomUUID()).post().uri(collection()).header("Idempotency-Key","x")
                .contentType(MediaType.APPLICATION_JSON).bodyValue("{").exchange().expectStatus().isForbidden();
        manager(UUID.randomUUID()).put().uri(collection()+"/"+combination)
                .contentType(MediaType.APPLICATION_JSON).bodyValue("{").exchange().expectStatus().isForbidden();
        var original=AvailabilityIdentityFixture.managerJwt(restaurant,context.getBean(Clock.class));
        var noRole=org.springframework.security.oauth2.jwt.Jwt.withTokenValue(original.getTokenValue())
                .headers(h -> h.putAll(original.getHeaders())).claims(c -> {
                    c.putAll(original.getClaims()); c.put("roles",List.of());
                }).build();
        client.mutateWith(org.springframework.security.test.web.reactive.server.SecurityMockServerConfigurers.mockJwt().jwt(noRole))
                .get().uri(collection()).exchange().expectStatus().isForbidden()
                .expectBody().jsonPath("$.tableIds").doesNotExist();
        client.mutateWith(org.springframework.security.test.web.reactive.server.SecurityMockServerConfigurers.mockJwt().jwt(noRole))
                .put().uri(collection()+"/"+combination).contentType(MediaType.APPLICATION_JSON).bodyValue("{")
                .exchange().expectStatus().isForbidden();
        verifyNoInteractions(service);
    }
    @ParameterizedTest @ValueSource(strings={"{}","[]","{","{\"tableIds\":null}","{\"tableIds\":\"x\"}",
            "{\"tableIds\":[null]}","{\"tableIds\":[1]}","{\"tableIds\":[],\"capacity\":6}"})
    void estructuraInvalidaEs400SinCoerciones(String payload) {
        manager(restaurant).post().uri(collection()).header("Idempotency-Key","bad").contentType(MediaType.APPLICATION_JSON)
                .bodyValue(payload).exchange().expectStatus().isBadRequest().expectBody().jsonPath("$.code").isEqualTo("INVALID_REQUEST");
        manager(restaurant).put().uri(collection()+"/"+combination).header("Idempotency-Key","bad-put").header("If-Match",etag(3))
                .contentType(MediaType.APPLICATION_JSON).bodyValue(payload).exchange().expectStatus().isBadRequest()
                .expectBody().jsonPath("$.code").isEqualTo("INVALID_REQUEST");
        verifyNoInteractions(service);
    }
    @Test void cabeceraAusenteYUuidDeRutaInvalidoNoConsultan() {
        manager(restaurant).post().uri(collection()).contentType(MediaType.APPLICATION_JSON).bodyValue(body())
                .exchange().expectStatus().isBadRequest();
        manager(restaurant).get().uri(collection()+"/no-es-uuid").exchange().expectStatus().isBadRequest();
        verifyNoInteractions(service);
    }
    @ParameterizedTest @ValueSource(strings={"VALIDATION_ERROR","DUPLICATE_COMBINATION","LEGACY_RESERVATION_BLOCK",
            "IDEMPOTENCY_CONFLICT","COMMITMENT_CHECK_UNAVAILABLE","OPERATION_OUTCOME_UNKNOWN"})
    void rechazosConservanCodigoDelContrato(String code) {
        when(service.create(any(),any(),any(),any())).thenReturn(Mono.error(new AvailabilityException(code,"Fallo")));
        int expected=AvailabilityHttpSupport.status(code);
        var result=manager(restaurant).post().uri(collection()).header("Idempotency-Key","error").contentType(MediaType.APPLICATION_JSON)
                .bodyValue(body()).exchange().expectStatus().isEqualTo(expected);
        if(expected==503) result.expectHeader().valueEquals("Retry-After","1");
        result.expectBody().jsonPath("$.code").isEqualTo(code).jsonPath("$.operationId").isNotEmpty()
                .jsonPath("$.timestamp").isNotEmpty().jsonPath("$.tableIds").doesNotExist();
    }
    @Test void recursoNoEncontradoEs404SinDatosAjenos() {
        when(service.read(any(),any(),any())).thenReturn(Mono.error(new AvailabilityException("NOT_FOUND","No existe")));
        manager(restaurant).get().uri(collection()+"/"+combination).exchange().expectStatus().isNotFound();
    }
    @Test void gateDesactivadoOcultaLasCuatroOperaciones() {
        context.close(); open(true);
        client.get().uri(collection()).exchange().expectStatus().isNotFound();
        client.post().uri(collection()).exchange().expectStatus().isNotFound();
        client.get().uri(collection()+"/"+combination).exchange().expectStatus().isNotFound();
        client.put().uri(collection()+"/"+combination).exchange().expectStatus().isNotFound();
        verifyNoInteractions(service);
    }
    @Test void putPropioConservaIdentidadYEmiteETagSinLocation() {
        var reply=new TableCombinationResponse(combination,restaurant,List.of(a,b),6,4);
        when(service.replace(any(),eq(restaurant),eq(combination),any(),any())).thenReturn(Mono.just(
                new RestaurantOperationCoordinator.Result<>(reply,4,200,null)));
        manager(restaurant).put().uri(collection()+"/"+combination).header("Idempotency-Key","replace").header("If-Match",etag(3))
                .contentType(MediaType.APPLICATION_JSON).bodyValue(body()).exchange().expectStatus().isOk()
                .expectHeader().valueEquals("ETag",etag(4)).expectHeader().doesNotExist("Location")
                .expectBody().jsonPath("$.id").isEqualTo(combination.toString())
                .jsonPath("$.restaurantId").isEqualTo(restaurant.toString()).jsonPath("$.tableIds.length()").isEqualTo(2)
                .jsonPath("$.capacity").isEqualTo(6).jsonPath("$.revision").isEqualTo(4).jsonPath("$.memberKey").doesNotExist();
        verify(service).replace(any(),eq(restaurant),eq(combination),eq(new TableCombinationRequest(List.of(a.toString(),b.toString()))),
                argThat(c -> c.expectedRevision().equals(3L) && c.idempotencyKey().equals("replace")
                        && c.fingerprint()!=null && c.httpStatus()==200 && c.location()==null));
    }
    @ParameterizedTest @ValueSource(strings={"missing-key","missing-etag","weak","unquoted","negative","overflow","multiple","long-key"})
    void putRechazaHeadersAusentesOMalformadosAntesDelServicio(String invalid) {
        var request=manager(restaurant).put().uri(collection()+"/"+combination).contentType(MediaType.APPLICATION_JSON);
        if(!invalid.equals("missing-key")) request.header("Idempotency-Key",invalid.equals("long-key")?"x".repeat(129):"key");
        if(!invalid.equals("missing-etag")) request.header("If-Match",switch(invalid) {
            case "weak" -> "W/\"3\"";
            case "unquoted" -> "3";
            case "negative" -> "\"-1\"";
            case "overflow" -> "\"9223372036854775808\"";
            case "multiple" -> "\"2\",\"3\"";
            default -> etag(3);
        });
        request.bodyValue(body()).exchange().expectStatus().isBadRequest().expectBody().jsonPath("$.code").isEqualTo("INVALID_REQUEST");
        verifyNoInteractions(service);
    }
    @ParameterizedTest @ValueSource(strings={"VALIDATION_ERROR","DUPLICATE_COMBINATION","PROTECTED_RESERVATION",
            "LEGACY_RESERVATION_BLOCK","REVISION_MISMATCH","IDEMPOTENCY_CONFLICT","COMMITMENT_CHECK_UNAVAILABLE",
            "OPERATION_OUTCOME_UNKNOWN","NOT_FOUND"})
    void putPropagaRechazosConContratoYRetryAfter(String code) {
        when(service.replace(any(),any(),any(),any(),any())).thenReturn(Mono.error(new AvailabilityException(code,"Fallo")));
        int status=AvailabilityHttpSupport.status(code);
        var result=manager(restaurant).put().uri(collection()+"/"+combination).header("Idempotency-Key","put-error")
                .header("If-Match",etag(3)).contentType(MediaType.APPLICATION_JSON).bodyValue(body())
                .exchange().expectStatus().isEqualTo(status);
        if(status==503) result.expectHeader().valueEquals("Retry-After","1");
        result.expectBody().jsonPath("$.code").isEqualTo(code).jsonPath("$.status").isEqualTo(status)
                .jsonPath("$.operationId").isNotEmpty().jsonPath("$.timestamp").isNotEmpty()
                .jsonPath("$.tableIds").doesNotExist();
    }
    @Test void putRechazaUuidDeRecursoInvalido() {
        manager(restaurant).put().uri(collection()+"/no-es-uuid").header("Idempotency-Key","bad-id")
                .header("If-Match",etag(3)).contentType(MediaType.APPLICATION_JSON).bodyValue(body())
                .exchange().expectStatus().isBadRequest();
        verifyNoInteractions(service);
    }
}
