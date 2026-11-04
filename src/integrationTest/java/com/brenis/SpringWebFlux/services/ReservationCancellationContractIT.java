package com.brenis.SpringWebFlux.services;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.*;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;
import org.springframework.web.reactive.config.EnableWebFlux;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import com.brenis.SpringWebFlux.support.*;
import com.brenis.SpringWebFlux.configs.*;
import com.brenis.SpringWebFlux.handlers.*;
import com.brenis.SpringWebFlux.routes.*;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.security.test.web.reactive.server.SecurityMockServerConfigurers.*;

@SpringJUnitConfig(ReservationCancellationContractIT.Configuration.class)
class ReservationCancellationContractIT extends ReservationCancellationSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false) @EnableWebFlux
    @Import({ReservationConfirmationSupport.Configuration.class,ReservationSecurityConfig.class,AvailabilitySecurityConfig.class,
        AvailabilityHttpSupport.class,ReservationHttpSupport.class,ReservationCommandHandler.class,ReservationCommandRouter.class})
    public static class Configuration {
        @Bean ReservationProperties reservationProperties(){var p=new ReservationProperties();p.setEnabled(true);return p;}
    }
    @Autowired org.springframework.context.ApplicationContext context;
    @Autowired ReservationProperties gate;
    @Test void cadenaRealPermisosCuerpoVacioETagReplayYNoop(){
        var first=confirm("client","first",2).block().body();String path="/restaurants/"+restaurant+"/reservations/"+first.id()+"/cancellation";
        var web=WebTestClient.bindToApplicationContext(context).apply(springSecurity()).build();
        var own=web.mutateWith(mockJwt().jwt(ReservationIdentityFixture.customer("client",clock)).authorities(new SimpleGrantedAuthority("ROLE_CUSTOMER")));
        var other=web.mutateWith(mockJwt().jwt(ReservationIdentityFixture.customer("other",clock)).authorities(new SimpleGrantedAuthority("ROLE_CUSTOMER")));
        var manager=web.mutateWith(mockJwt().jwt(ReservationIdentityFixture.manager(UUID.randomUUID(),clock)).authorities(new SimpleGrantedAuthority("ROLE_RESTAURANT_MANAGER")));
        var before=state();web.post().uri(path).exchange().expectStatus().isUnauthorized();
        other.post().uri(path).header("Idempotency-Key","other").header("If-Match","\"1\"").exchange().expectStatus().isNotFound();
        for(UUID target:List.of(first.id(),UUID.randomUUID()))manager.post().uri("/restaurants/"+restaurant+"/reservations/"+target+"/cancellation")
            .header("Idempotency-Key","manager").header("If-Match","\"1\"").exchange().expectStatus().isForbidden();
        own.post().uri(path).header("Idempotency-Key","body").header("If-Match","\"1\"").bodyValue("{}").exchange().expectStatus().isBadRequest();
        own.post().uri(path).header("Idempotency-Key","stale").header("If-Match","\"0\"").exchange().expectStatus().isEqualTo(412);assertThat(state()).isEqualTo(before);
        var accepted=own.post().uri(path).header("Idempotency-Key","cancel").header("If-Match","\"1\"").exchange()
            .expectStatus().isOk().expectHeader().valueEquals("ETag","\"2\"").expectHeader().doesNotExist("Location")
            .expectBody().jsonPath("$.status").isEqualTo("CANCELLED").returnResult().getResponseBody();
        var stable=state();
        own.post().uri(path).header("Idempotency-Key","cancel").header("If-Match","\"1\"").exchange().expectStatus().isOk()
            .expectHeader().valueEquals("ETag","\"2\"").expectBody().consumeWith(result->assertThat(result.getResponseBody()).isEqualTo(accepted));assertThat(state()).isEqualTo(stable);
        own.post().uri(path).header("Idempotency-Key","noop").header("If-Match","\"0\"").exchange().expectStatus().isOk()
            .expectHeader().valueEquals("ETag","\"2\"").expectBody().consumeWith(result->assertThat(result.getResponseBody()).isEqualTo(accepted));
        assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(3);
        stable=state();own.post().uri(path).header("Idempotency-Key","malformed").header("If-Match","W/\"0\"").exchange().expectStatus().isBadRequest();
        try{gate.setEnabled(false);own.post().uri(path).header("Idempotency-Key","off").header("If-Match","\"2\"").exchange().expectStatus().isNotFound();}
        finally{gate.setEnabled(true);}
        assertThat(state()).isEqualTo(stable);
    }
}
