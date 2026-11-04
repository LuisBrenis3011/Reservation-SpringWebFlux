package com.brenis.SpringWebFlux.handlers;
import com.brenis.SpringWebFlux.configs.*;
import com.brenis.SpringWebFlux.dtos.responses.RestaurantTimeZoneResponse;
import com.brenis.SpringWebFlux.routes.RestaurantShiftRouter;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.services.impls.RestaurantAccessPolicy;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.support.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.junit.jupiter.params.provider.CsvSource;
import com.brenis.SpringWebFlux.dtos.requests.RestaurantShiftRequest;
import com.brenis.SpringWebFlux.validators.RestaurantShiftValidator;
import org.springframework.context.annotation.*;
import org.springframework.web.reactive.config.EnableWebFlux;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.http.MediaType;
import reactor.core.publisher.Mono;
import java.time.*;
import java.util.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.springframework.security.test.web.reactive.server.SecurityMockServerConfigurers.springSecurity;

class AvailabilityShiftHttpTests {
    @Configuration(proxyBeanMethods=false) @EnableWebFlux
    @Import({AvailabilitySecurityConfig.class,AvailabilityHttpSupport.class,RestaurantAccessPolicy.class,
        AvailabilityMetricsConfig.class,com.brenis.SpringWebFlux.observability.AvailabilityTelemetry.class,
        RestaurantShiftHandler.class,RestaurantShiftRouter.class})
    static class WebConfiguration {
        @Bean AvailabilityProperties properties(){var p=new AvailabilityProperties();p.setEnabled(true);p.setIssuerUri("https://issuer.example.test");p.setJwkSetUri("https://issuer.example.test/jwks");return p;}
        @Bean Clock clock(){return new AvailabilityClockFixture(Instant.parse("2026-11-01T10:00:00Z"));}
        @Bean RestaurantShiftService service(){return mock(RestaurantShiftService.class);}
    }
    AnnotationConfigApplicationContext context;
    WebTestClient client;
    RestaurantShiftService service;
    UUID owner=UUID.randomUUID();
    String path(){return "/restaurants/"+owner+"/time-zone";}
    WebTestClient manager(UUID id){return client.mutateWith(AvailabilityIdentityFixture.manager(id,context.getBean(Clock.class)));}
    @BeforeEach void open(){context=new AnnotationConfigApplicationContext(WebConfiguration.class);service=context.getBean(RestaurantShiftService.class);client=WebTestClient.bindToApplicationContext(context).apply(springSecurity()).build();}
    @AfterEach void close(){context.close();}
    @Test void esc0301_zonaAusenteEsNullSinDefault(){
        when(service.readZone(any(),eq(owner))).thenReturn(Mono.just(new RestaurantOperationCoordinator.Result<>(new RestaurantTimeZoneResponse(owner,null,0),0,200,null)));
        manager(owner).get().uri(path()).exchange().expectStatus().isOk().expectHeader().valueEquals("ETag","\"0\"")
            .expectBody().jsonPath("$.zoneId").isEmpty().jsonPath("$.restaurantId").isEqualTo(owner.toString());
    }
    @Test void esc0301_putPropioDevuelveZonaYETag(){
        when(service.replaceZone(any(),eq(owner),any(),any())).thenReturn(Mono.just(new RestaurantOperationCoordinator.Result<>(new RestaurantTimeZoneResponse(owner,"America/Lima",1),1,200,null)));
        manager(owner).put().uri(path()).header("Idempotency-Key","zone").header("If-Match","\"0\"").contentType(MediaType.APPLICATION_JSON).bodyValue(Map.of("zoneId","America/Lima")).exchange()
            .expectStatus().isOk().expectHeader().valueEquals("ETag","\"1\"").expectHeader().doesNotExist("Location").expectBody().jsonPath("$.zoneId").isEqualTo("America/Lima");
        verify(service).replaceZone(any(),eq(owner),any(),argThat(c -> c.expectedRevision()==0 && c.httpStatus()==200 && c.fingerprint()!=null));
    }
    @Test void esc0302_permisosAntesDeLeerCuerpo(){
        client.get().uri(path()).exchange().expectStatus().isUnauthorized();
        client.mutateWith(org.springframework.security.test.web.reactive.server.SecurityMockServerConfigurers.mockJwt().jwt(jwt -> jwt.claim("roles",List.of()).claim("restaurant_ids",List.of(owner.toString())))).get().uri(path()).exchange().expectStatus().isForbidden();
        manager(UUID.randomUUID()).put().uri(path()).bodyValue("{").exchange().expectStatus().isForbidden();
        verifyNoInteractions(service);
    }
    @ParameterizedTest @ValueSource(strings={"{}","[]","{","{\"zoneId\":null}","{\"zoneId\":12}","{\"zoneId\":\"America/Lima\",\"extra\":true}"})
    void cuerpoEstricto(String body){manager(owner).put().uri(path()).header("Idempotency-Key","bad").header("If-Match","\"0\"").contentType(MediaType.APPLICATION_JSON).bodyValue(body).exchange().expectStatus().isBadRequest();verifyNoInteractions(service);}
    @ParameterizedTest @ValueSource(strings={"VALIDATION_ERROR","LEGACY_RESERVATION_BLOCK","PROTECTED_RESERVATION","COMMITMENT_CHECK_UNAVAILABLE","REVISION_MISMATCH","IDEMPOTENCY_CONFLICT","NOT_FOUND"})
    void esc0321_0324_propagaFalloLegadoYErrores(String code){
        when(service.replaceZone(any(),any(),any(),any())).thenReturn(Mono.error(new AvailabilityException(code,"test")));
        var response=manager(owner).put().uri(path()).header("Idempotency-Key","error").header("If-Match","\"0\"").contentType(MediaType.APPLICATION_JSON).bodyValue(Map.of("zoneId","America/Lima")).exchange().expectStatus().isEqualTo(AvailabilityHttpSupport.status(code));
        if(code.equals("COMMITMENT_CHECK_UNAVAILABLE"))response.expectHeader().valueEquals("Retry-After","1");
        response.expectBody().jsonPath("$.code").isEqualTo(code).jsonPath("$.message").isEqualTo(code);
    }
    @Test void headersObligatorios(){manager(owner).put().uri(path()).contentType(MediaType.APPLICATION_JSON).bodyValue(Map.of("zoneId","America/Lima")).exchange().expectStatus().isBadRequest();verifyNoInteractions(service);}
    String shiftsPath(){return "/restaurants/"+owner+"/shifts";}
    @ParameterizedTest @CsvSource({
        "2027-03-14T02:30:00,2027-03-14T04:00:00,La hora local no existe en la zona del restaurante.",
        "2027-03-14T01:00:00,2027-03-14T02:30:00,La hora local no existe en la zona del restaurante.",
        "2027-11-07T01:30:00,2027-11-07T03:00:00,La hora local es ambigua porque se repite en la zona del restaurante.",
        "2027-11-07T00:30:00,2027-11-07T01:30:00,La hora local es ambigua porque se repite en la zona del restaurante."})
    void esc0313_0314_explicaCausaTemporalEnAltaEdicionYZona(String start,String end,String message){
        var input=new RestaurantShiftRequest(start,end);
        var failure=org.assertj.core.api.Assertions.catchThrowable(() ->
            new RestaurantShiftValidator().validate(input,"America/New_York",context.getBean(Clock.class).instant()));
        org.assertj.core.api.Assertions.assertThat(failure).isInstanceOf(com.brenis.SpringWebFlux.exceptions.ShiftLocalTimeException.class);
        when(service.create(any(),eq(owner),any(),any())).thenReturn(Mono.error(failure));
        when(service.replace(any(),eq(owner),any(),any(),any())).thenReturn(Mono.error(failure));
        when(service.replaceZone(any(),eq(owner),any(),any())).thenReturn(Mono.error(failure));
        var payload=Map.of("localStart",start,"localEnd",end);
        manager(owner).post().uri(shiftsPath()).header("Idempotency-Key","gap-post")
            .contentType(MediaType.APPLICATION_JSON).bodyValue(payload).exchange().expectStatus().isEqualTo(422)
            .expectBody().jsonPath("$.code").isEqualTo("VALIDATION_ERROR").jsonPath("$.message").isEqualTo(message);
        manager(owner).put().uri(shiftsPath()+"/"+UUID.randomUUID()).header("Idempotency-Key","gap-put").header("If-Match","\"1\"")
            .contentType(MediaType.APPLICATION_JSON).bodyValue(payload).exchange().expectStatus().isEqualTo(422)
            .expectBody().jsonPath("$.code").isEqualTo("VALIDATION_ERROR").jsonPath("$.message").isEqualTo(message);
        manager(owner).put().uri(path()).header("Idempotency-Key","gap-zone").header("If-Match","\"1\"")
            .contentType(MediaType.APPLICATION_JSON).bodyValue(Map.of("zoneId","America/New_York")).exchange().expectStatus().isEqualTo(422)
            .expectBody().jsonPath("$.code").isEqualTo("VALIDATION_ERROR").jsonPath("$.message").isEqualTo(message);
    }
    @Test void putTurnoContrato(){
        UUID id=UUID.randomUUID();when(service.replace(any(),eq(owner),eq(id),any(),any())).thenReturn(Mono.just(new RestaurantOperationCoordinator.Result<>(shiftResponse(id),2,200,null)));
        manager(owner).put().uri(shiftsPath()+"/"+id).header("Idempotency-Key","edit").header("If-Match","\"1\"").contentType(MediaType.APPLICATION_JSON).bodyValue(shiftBody()).exchange().expectStatus().isOk().expectHeader().valueEquals("ETag","\"2\"").expectHeader().doesNotExist("Location");
        verify(service).replace(any(),eq(owner),eq(id),any(),argThat(c -> c.expectedRevision()==1));
    }
    Map<String,String> shiftBody(){return Map.of("localStart","2026-11-01T22:00:00","localEnd","2026-11-02T02:00:00");}
    com.brenis.SpringWebFlux.dtos.responses.RestaurantShiftResponse shiftResponse(UUID id){return new com.brenis.SpringWebFlux.dtos.responses.RestaurantShiftResponse(id,owner,"2026-11-01T22:00:00","2026-11-02T02:00:00","America/Lima",Instant.parse("2026-11-02T03:00:00Z"),Instant.parse("2026-11-02T07:00:00Z"),2);}
    @Test void postYGetTurnoRespetanContrato(){
        UUID id=UUID.randomUUID();String location="/catalog"+shiftsPath()+"/"+id;var value=shiftResponse(id);
        when(service.create(any(),eq(owner),any(),any())).thenReturn(Mono.just(new RestaurantOperationCoordinator.Result<>(value,2,201,location)));
        manager(owner).post().uri(shiftsPath()).header("Idempotency-Key","shift").contentType(MediaType.APPLICATION_JSON).bodyValue(shiftBody()).exchange().expectStatus().isCreated().expectHeader().valueEquals("Location",location).expectHeader().valueEquals("ETag","\"2\"").expectBody().jsonPath("$.zoneId").isEqualTo("America/Lima").jsonPath("$.startInstant").isEqualTo("2026-11-02T03:00:00Z");
        when(service.read(any(),eq(owner),eq(id))).thenReturn(Mono.just(new RestaurantOperationCoordinator.Result<>(value,2,200,null)));
        manager(owner).get().uri(shiftsPath()+"/"+id).exchange().expectStatus().isOk().expectHeader().valueEquals("ETag","\"2\"").expectBody().jsonPath("$.id").isEqualTo(id.toString());
        when(service.list(any(),eq(owner))).thenReturn(Mono.just(new RestaurantOperationCoordinator.Result<>(new com.brenis.SpringWebFlux.dtos.responses.RestaurantShiftListResponse(List.of(value),2),2,200,null)));
        manager(owner).get().uri(shiftsPath()).exchange().expectStatus().isOk().expectBody().jsonPath("$.items.length()").isEqualTo(1).jsonPath("$.revision").isEqualTo(2);
    }
    @ParameterizedTest @ValueSource(strings={"{}","{\"localStart\":null,\"localEnd\":\"x\"}","{\"localStart\":3,\"localEnd\":\"x\"}","{\"localStart\":\"x\",\"localEnd\":\"y\",\"zoneId\":\"UTC\"}"})
    void turnoRechazaEstructuraInvalida(String payload){manager(owner).post().uri(shiftsPath()).header("Idempotency-Key","bad-shift").contentType(MediaType.APPLICATION_JSON).bodyValue(payload).exchange().expectStatus().isBadRequest();verifyNoInteractions(service);}
    @Test void permisosYCabecerasDeTurnos(){
        client.post().uri(shiftsPath()).bodyValue(shiftBody()).exchange().expectStatus().isUnauthorized();
        manager(UUID.randomUUID()).post().uri(shiftsPath()).bodyValue("{").exchange().expectStatus().isForbidden();
        manager(owner).post().uri(shiftsPath()).contentType(MediaType.APPLICATION_JSON).bodyValue(shiftBody()).exchange().expectStatus().isBadRequest();
        verifyNoInteractions(service);
    }
    @ParameterizedTest @ValueSource(strings={"SHIFT_OVERLAP","SHIFT_ALREADY_STARTED","VALIDATION_ERROR","LEGACY_RESERVATION_BLOCK","COMMITMENT_CHECK_UNAVAILABLE","IDEMPOTENCY_CONFLICT"})
    void erroresDeTurnos(String code){when(service.create(any(),any(),any(),any())).thenReturn(Mono.error(new AvailabilityException(code,"test")));var result=manager(owner).post().uri(shiftsPath()).header("Idempotency-Key","error-shift").contentType(MediaType.APPLICATION_JSON).bodyValue(shiftBody()).exchange().expectStatus().isEqualTo(AvailabilityHttpSupport.status(code));if(code.equals("COMMITMENT_CHECK_UNAVAILABLE"))result.expectHeader().valueEquals("Retry-After","1");result.expectBody().jsonPath("$.code").isEqualTo(code);}
    @Test void gateOcultaZonaYNoRegistraTurnos(){
        var p=context.getBean(AvailabilityProperties.class);p.setEnabled(false);
        var route=new RestaurantShiftRouter().restaurantShiftRoutes(context.getBean(RestaurantShiftHandler.class),p);
        WebTestClient.bindToRouterFunction(route).build().get().uri(path()).exchange().expectStatus().isNotFound();
        WebTestClient.bindToRouterFunction(route).build().put().uri("/restaurants/"+owner+"/shifts/"+UUID.randomUUID()).exchange().expectStatus().isNotFound();
    }
}
