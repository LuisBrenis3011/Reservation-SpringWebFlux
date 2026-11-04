package com.brenis.SpringWebFlux.handlers;

import com.brenis.SpringWebFlux.configs.*;
import com.brenis.SpringWebFlux.dtos.requests.TableCreateRequest;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import com.brenis.SpringWebFlux.dtos.responses.*;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.routes.TableConfigurationRouter;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.services.impls.RestaurantAccessPolicy;
import com.brenis.SpringWebFlux.support.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.junit.jupiter.params.provider.CsvSource;
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

class AvailabilityTableHttpTests {
    @Configuration(proxyBeanMethods=false) @EnableWebFlux
    @Import({AvailabilitySecurityConfig.class,AvailabilityHttpSupport.class,RestaurantAccessPolicy.class,
            AvailabilityMetricsConfig.class,com.brenis.SpringWebFlux.observability.AvailabilityTelemetry.class,
            TableConfigurationHandler.class,TableConfigurationRouter.class})
    static class WebConfiguration {
        @Bean AvailabilityProperties properties() {
            var p=new AvailabilityProperties(); p.setEnabled(true);
            p.setIssuerUri("https://issuer.example.test"); p.setJwkSetUri("https://issuer.example.test/jwks");
            return p;
        }
        @Bean Clock clock() { return new AvailabilityClockFixture(Instant.parse("2026-11-01T10:00:00Z")); }
        @Bean TableConfigurationService service() { return mock(TableConfigurationService.class); }
    }
    @Configuration(proxyBeanMethods=false)
    static class DisabledConfiguration {
        @Bean @Primary AvailabilityProperties disabled() { return new AvailabilityProperties(); }
    }
    AnnotationConfigApplicationContext context;
    WebTestClient client;
    TableConfigurationService service;
    UUID restaurant=UUID.randomUUID(), table=UUID.randomUUID();
    String collection() { return "/restaurants/"+restaurant+"/tables"; }
    @BeforeEach void setup() { open(false); }
    void open(boolean disabled) {
        context=new AnnotationConfigApplicationContext();
        context.register(WebConfiguration.class);
        if(disabled) context.register(DisabledConfiguration.class);
        context.refresh();
        service=context.getBean(TableConfigurationService.class);
        client=WebTestClient.bindToApplicationContext(context).apply(springSecurity()).build();
    }
    @AfterEach void close() { context.close(); }
    WebTestClient manager(UUID owner) {
        return client.mutateWith(AvailabilityIdentityFixture.manager(owner,context.getBean(Clock.class)));
    }
    @Test void esc0101_postPropioDevuelve201LocationETagYCuerpoDelContrato() {
        var reply=new TableAvailabilityResponse(table,restaurant,"Mesa",4,1);
        String location="/catalog"+collection()+"/"+table;
        when(service.create(any(),eq(restaurant),any(),any()))
                .thenReturn(Mono.just(new RestaurantOperationCoordinator.Result<>(reply,1,201,location)));
        manager(restaurant).post().uri(collection()).header("Idempotency-Key","one")
                .contentType(MediaType.APPLICATION_JSON).bodyValue(Map.of("label","Mesa","capacity",4))
                .exchange().expectStatus().isCreated().expectHeader().valueEquals("Location",location)
                .expectHeader().valueEquals("ETag",new AvailabilityHttpSupport(Clock.systemUTC()).etag(1))
                .expectBody().jsonPath("$.restaurantId").isEqualTo(restaurant.toString())
                .jsonPath("$.capacity").isEqualTo(4).jsonPath("$.revision").isEqualTo(1)
                .jsonPath("$.labelKey").doesNotExist();
        verify(service).create(any(),eq(restaurant),eq(new TableCreateRequest("Mesa",4L)),
                argThat(c -> c.idempotencyKey().equals("one") && c.fingerprint()!=null));
    }
    @Test void getColeccionYRecursoCompartenRevisionSinIdempotencyKey() {
        var reply=new TableAvailabilityResponse(table,restaurant,"Mesa",4,2);
        when(service.list(any(),eq(restaurant))).thenReturn(Mono.just(new RestaurantOperationCoordinator.Result<>(
                new TableListResponse(List.of(reply),4,2),2,200,null)));
        when(service.read(any(),eq(restaurant),eq(table))).thenReturn(Mono.just(
                new RestaurantOperationCoordinator.Result<>(reply,2,200,null)));
        manager(restaurant).get().uri(collection()).exchange().expectStatus().isOk()
                .expectHeader().valueEquals("ETag",String.valueOf('"')+2+'"')
                .expectBody().jsonPath("$.totalCapacity").isEqualTo(4).jsonPath("$.items[0].revision").isEqualTo(2);
        manager(restaurant).get().uri(collection()+"/"+table).exchange().expectStatus().isOk()
                .expectBody().jsonPath("$.id").isEqualTo(table.toString());
    }
    @Test void esc0102_sinTokenNoRevelaDatosNiEjecutaServicio() {
        client.get().uri(collection()).exchange().expectStatus().isUnauthorized()
                .expectBody().jsonPath("$.code").isEqualTo("UNAUTHENTICATED").jsonPath("$.items").doesNotExist();
        verifyNoInteractions(service);
    }
    @Test void esc0102_encargadoAjenoNoLeeNiEscribeAunqueBodySeaInvalido() {
        manager(UUID.randomUUID()).get().uri(collection()).exchange().expectStatus().isForbidden();
        manager(UUID.randomUUID()).post().uri(collection()).contentType(MediaType.APPLICATION_JSON)
                .bodyValue("{").exchange().expectStatus().isForbidden()
                .expectBody().jsonPath("$.code").isEqualTo("FORBIDDEN").jsonPath("$.items").doesNotExist();
        verifyNoInteractions(service);
    }
    @ParameterizedTest @ValueSource(strings={
            "{\"label\":\"Mesa\",\"capacity\":1.5}",
            "{\"label\":\"Mesa\",\"capacity\":\"4\"}",
            "{\"label\":42,\"capacity\":4}",
            "{\"label\":null,\"capacity\":4}",
            "{\"label\":\"Mesa\",\"capacity\":4,\"other\":1}",
            "{\"label\":\"Mesa\"}","{\"capacity\":4}","[]","{"
    })
    void esc0104_estructuraInvalidaNoLlegaAlServicio(String body) {
        manager(restaurant).post().uri(collection()).header("Idempotency-Key","bad")
                .contentType(MediaType.APPLICATION_JSON).bodyValue(body).exchange().expectStatus().isBadRequest()
                .expectBody().jsonPath("$.code").isEqualTo("INVALID_REQUEST");
        verifyNoInteractions(service);
    }
    @Test void postSinClaveRechazaAntesDeEscribir() {
        manager(restaurant).post().uri(collection()).contentType(MediaType.APPLICATION_JSON)
                .bodyValue(Map.of("label","Mesa","capacity",4)).exchange().expectStatus().isBadRequest();
        verifyNoInteractions(service);
    }
    @Test void erroresDeDominioConservanContratoYRetryAfter() {
        when(service.create(any(),any(),any(),any())).thenReturn(Mono.error(
                new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Fallo")));
        manager(restaurant).post().uri(collection()).header("Idempotency-Key","retry")
                .contentType(MediaType.APPLICATION_JSON).bodyValue(Map.of("label","Mesa","capacity",4))
                .exchange().expectStatus().isEqualTo(503).expectHeader().valueEquals("Retry-After","1")
                .expectBody().jsonPath("$.code").isEqualTo("COMMITMENT_CHECK_UNAVAILABLE")
                .jsonPath("$.operationId").isNotEmpty().jsonPath("$.timestamp").isNotEmpty();
    }
    @Test void inexistentePropioDevuelve404() {
        when(service.read(any(),any(),any())).thenReturn(Mono.error(new AvailabilityException("NOT_FOUND","No existe")));
        manager(restaurant).get().uri(collection()+"/"+table).exchange().expectStatus().isNotFound();
    }
    @Test void gateApagadoOcultaTodasLasRutas() {
        context.close(); open(true);
        client.get().uri(collection()).exchange().expectStatus().isNotFound();
        client.post().uri(collection()).exchange().expectStatus().isNotFound();
        client.get().uri(collection()+"/"+table).exchange().expectStatus().isNotFound();
        client.patch().uri(collection()+"/"+table).exchange().expectStatus().isNotFound();
        verifyNoInteractions(service);
    }
    @ParameterizedTest @ValueSource(strings={"VALIDATION_ERROR","DUPLICATE_LABEL","LEGACY_RESERVATION_BLOCK","IDEMPOTENCY_CONFLICT"})
    void rechazosDeAltaMantienenCodigoYEstadoDelContrato(String code) {
        when(service.create(any(),any(),any(),any())).thenReturn(Mono.error(new AvailabilityException(code,"Rechazado")));
        manager(restaurant).post().uri(collection()).header("Idempotency-Key","rejected")
                .contentType(MediaType.APPLICATION_JSON).bodyValue(Map.of("label","Mesa","capacity",4))
                .exchange().expectStatus().isEqualTo(code.equals("VALIDATION_ERROR")?422:409)
                .expectBody().jsonPath("$.code").isEqualTo(code).jsonPath("$.items").doesNotExist();
    }
    @Test void uuidInvalidoNoConsulta() {
        manager(restaurant).get().uri(collection()+"/no-es-uuid").exchange().expectStatus().isBadRequest();
        verifyNoInteractions(service);
    }
    String etag(long revision) { return String.valueOf('"')+revision+'"'; }
    @ParameterizedTest @ValueSource(strings={"label","capacity","both"})
    void patchPropioConCamposOpcionalesDevuelve200YRevision(String fields) {
        boolean labelPresent=!fields.equals("capacity"), capacityPresent=!fields.equals("label");
        var input=new TablePatchRequest(labelPresent?"Ventana":null,capacityPresent?6L:null);
        var payload=new LinkedHashMap<String,Object>();
        if(labelPresent) payload.put("label","Ventana");
        if(capacityPresent) payload.put("capacity",6);
        var reply=new TableAvailabilityResponse(table,restaurant,labelPresent?"Ventana":"Mesa",capacityPresent?6:4,3);
        when(service.patch(any(),eq(restaurant),eq(table),eq(input),any())).thenReturn(Mono.just(
                new RestaurantOperationCoordinator.Result<>(reply,3,200,null)));
        manager(restaurant).patch().uri(collection()+"/"+table).header("Idempotency-Key","patch")
                .header("If-Match",etag(2)).contentType(MediaType.APPLICATION_JSON).bodyValue(payload)
                .exchange().expectStatus().isOk().expectHeader().valueEquals("ETag",etag(3))
                .expectHeader().doesNotExist("Location").expectBody()
                .jsonPath("$.id").isEqualTo(table.toString()).jsonPath("$.restaurantId").isEqualTo(restaurant.toString())
                .jsonPath("$.label").isEqualTo(reply.label()).jsonPath("$.capacity").isEqualTo((int)reply.capacity())
                .jsonPath("$.revision").isEqualTo(3).jsonPath("$.labelKey").doesNotExist();
        verify(service).patch(any(),eq(restaurant),eq(table),eq(input),argThat(c ->
                c.idempotencyKey().equals("patch") && c.expectedRevision().equals(2L)
                        && c.fingerprint()!=null && c.httpStatus()==200 && c.location()==null));
    }
    @ParameterizedTest @ValueSource(strings={
            "{}","{\"label\":null}","{\"capacity\":null}","{\"capacity\":1.5}",
            "{\"capacity\":\"4\"}","{\"label\":4}","{\"capacity\":9223372036854775808}",
            "{\"other\":1}","{\"label\":\"Mesa\",\"other\":1}","[]","{",""
    })
    void patchRechazaJsonIncompatibleSinInvocarServicio(String body) {
        manager(restaurant).patch().uri(collection()+"/"+table).header("Idempotency-Key","bad")
                .header("If-Match",etag(1)).contentType(MediaType.APPLICATION_JSON).bodyValue(body)
                .exchange().expectStatus().isBadRequest().expectBody().jsonPath("$.code").isEqualTo("INVALID_REQUEST");
        verifyNoInteractions(service);
    }
    @ParameterizedTest @ValueSource(strings={"missing-key","missing-etag","unquoted","weak","negative","overflow","multiple","long-key"})
    void patchRechazaHeadersAusentesOMalformados(String invalid) {
        var request=manager(restaurant).patch().uri(collection()+"/"+table);
        if(!invalid.equals("missing-key"))
            request.header("Idempotency-Key",invalid.equals("long-key")?"a".repeat(129):"patch");
        if(!invalid.equals("missing-etag")) {
            String value=switch(invalid) {
                case "unquoted" -> "1";
                case "weak" -> "W/"+etag(1);
                case "negative" -> etag(-1);
                case "overflow" -> String.valueOf('"')+"9223372036854775808"+'"';
                case "multiple" -> etag(1)+", "+etag(2);
                default -> etag(1);
            };
            request.header("If-Match",value);
        }
        request.contentType(MediaType.APPLICATION_JSON).bodyValue(Map.of("label","Mesa"))
                .exchange().expectStatus().isBadRequest().expectBody().jsonPath("$.code").isEqualTo("INVALID_REQUEST");
        verifyNoInteractions(service);
    }
    @ParameterizedTest @CsvSource({
            "DUPLICATE_LABEL,409","PROTECTED_RESERVATION,409","LEGACY_RESERVATION_BLOCK,409",
            "IDEMPOTENCY_CONFLICT,409","REVISION_MISMATCH,412","VALIDATION_ERROR,422","NOT_FOUND,404",
            "COMMITMENT_CHECK_UNAVAILABLE,503","OPERATION_OUTCOME_UNKNOWN,503"
    })
    void patchConservaErroresDelContrato(String code,int status) {
        when(service.patch(any(),any(),any(),any(),any())).thenReturn(Mono.error(new AvailabilityException(code,"Rechazado")));
        var response=manager(restaurant).patch().uri(collection()+"/"+table).header("Idempotency-Key","patch")
                .header("If-Match",etag(1)).contentType(MediaType.APPLICATION_JSON).bodyValue(Map.of("capacity",6))
                .exchange().expectStatus().isEqualTo(status);
        if(status==503) response.expectHeader().valueEquals("Retry-After","1");
        response.expectBody().jsonPath("$.code").isEqualTo(code).jsonPath("$.status").isEqualTo(status)
                .jsonPath("$.operationId").isNotEmpty().jsonPath("$.timestamp").isNotEmpty()
                .jsonPath("$.capacity").doesNotExist();
    }
    @Test void patchSinAutenticacionOPermisoNoLeeNiEscribe() {
        client.patch().uri(collection()+"/"+table).exchange().expectStatus().isUnauthorized();
        manager(UUID.randomUUID()).patch().uri(collection()+"/"+table)
                .contentType(MediaType.APPLICATION_JSON).bodyValue("{").exchange().expectStatus().isForbidden();
        verifyNoInteractions(service);
    }
    @Test void patchConUuidInvalidoSeRechazaAntesDelServicio() {
        manager(restaurant).patch().uri(collection()+"/invalid").header("Idempotency-Key","patch")
                .header("If-Match",etag(1)).contentType(MediaType.APPLICATION_JSON).bodyValue(Map.of("label","Mesa"))
                .exchange().expectStatus().isBadRequest();
        verifyNoInteractions(service);
    }
}

