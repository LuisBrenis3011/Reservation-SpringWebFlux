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

/** Cadena, router, handler y servicio reales en contexto efímero; no usa HTTP local. */
@SpringJUnitConfig(ReservationReplaceContractIT.Configuration.class)
class ReservationReplaceContractIT extends ReservationReplacementSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false) @EnableWebFlux
    @Import({ReservationConfirmationSupport.Configuration.class,ReservationSecurityConfig.class,AvailabilitySecurityConfig.class,
        AvailabilityHttpSupport.class,ReservationHttpSupport.class,ReservationCommandHandler.class,ReservationCommandRouter.class})
    public static class Configuration {
        @Bean ReservationProperties reservationProperties(){var p=new ReservationProperties();p.setEnabled(true);return p;}
    }
    @Autowired org.springframework.context.ApplicationContext context;
    @Autowired ReservationProperties gate;
    @Test void permisosContratoReplayYConservacionConCadenaReal(){
        var first=confirm("client","first",3).block().body();
        var web=WebTestClient.bindToApplicationContext(context).apply(springSecurity()).build();
        var own=web.mutateWith(mockJwt().jwt(ReservationIdentityFixture.customer("client",clock)).authorities(new SimpleGrantedAuthority("ROLE_CUSTOMER")));
        var foreign=web.mutateWith(mockJwt().jwt(ReservationIdentityFixture.customer("other",clock)).authorities(new SimpleGrantedAuthority("ROLE_CUSTOMER")));
        var wrongManager=web.mutateWith(mockJwt().jwt(ReservationIdentityFixture.manager(UUID.randomUUID(),clock)).authorities(new SimpleGrantedAuthority("ROLE_RESTAURANT_MANAGER")));
        String path="/restaurants/"+restaurant+"/reservations/"+first.id();
        String payload="{\"shiftId\":\""+shift+"\",\"partySize\":3,\"notes\":\"Ventana\"}";
        var before=state();
        web.put().uri(path).bodyValue(payload).exchange().expectStatus().isUnauthorized();
        foreign.put().uri(path).header("Idempotency-Key","foreign").header("If-Match","\"1\"").bodyValue(payload).exchange().expectStatus().isNotFound();
        for(String target:List.of(path,"/restaurants/"+restaurant+"/reservations/"+UUID.randomUUID()))
            wrongManager.put().uri(target).header("Idempotency-Key","wrong-manager").header("If-Match","\"1\"").bodyValue(payload).exchange().expectStatus().isForbidden();
        assertThat(state()).isEqualTo(before);
        var accepted=own.put().uri(path).header("Idempotency-Key","edit").header("If-Match","\"1\"").bodyValue(payload).exchange()
            .expectStatus().isOk().expectHeader().valueEquals("ETag","\"2\"").expectHeader().doesNotExist("Location")
            .expectBody().jsonPath("$.notes").isEqualTo("Ventana").jsonPath("$.version").isEqualTo(2)
            .returnResult().getResponseBody();
        replace(customer("client"),first.id(),2,"later",shift,3,"Otra").block();before=state();
        own.put().uri(path).header("Idempotency-Key","edit").header("If-Match","\"1\"").bodyValue(payload).exchange()
            .expectStatus().isOk().expectHeader().valueEquals("ETag","\"2\"").expectHeader().doesNotExist("Location")
            .expectBody().consumeWith(result->assertThat(result.getResponseBody()).isEqualTo(accepted));
        own.put().uri(path).header("Idempotency-Key","stale").header("If-Match","\"1\"").bodyValue(payload).exchange().expectStatus().isEqualTo(412);
        own.put().uri(path).header("Idempotency-Key","missing").bodyValue(payload).exchange().expectStatus().isBadRequest();
        try{gate.setEnabled(false);own.put().uri(path).header("Idempotency-Key","off").header("If-Match","\"3\"").bodyValue(payload).exchange().expectStatus().isNotFound();}
        finally{gate.setEnabled(true);}
        assertThat(state()).isEqualTo(before);
    }
}
