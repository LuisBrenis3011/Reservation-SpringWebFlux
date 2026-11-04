package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.*;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.reactive.config.EnableWebFlux;
import org.springframework.web.reactive.function.server.*;
import org.springframework.test.web.reactive.server.WebTestClient;
import com.brenis.SpringWebFlux.configs.*;

@SpringJUnitConfig(ReservationSecurityBaseTests.Configuration.class)
class ReservationSecurityBaseTests {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false)
    @EnableWebFlux
    @Import({ReservationSecurityConfig.class,AvailabilitySecurityConfig.class,AvailabilityProperties.class,ReservationProperties.class,AvailabilityClockConfig.class})
    static class Configuration {
        @Bean RouterFunction<ServerResponse> probe(){return RouterFunctions.route().GET("/restaurants",r->ServerResponse.ok().build()).build();}
    }
    @Autowired org.springframework.context.ApplicationContext context;
    @Test void gateApagadoOcultaRutasNuevasSinDesafio(){
        WebTestClient.bindToApplicationContext(context).build().get().uri("/restaurants/11111111-1111-4111-8111-111111111111/reservations")
            .exchange().expectStatus().isNotFound().expectHeader().doesNotExist("WWW-Authenticate");
    }
    @Test void lecturaAntiguaExigeTokenAunqueGateNuevoEsteApagado(){
        WebTestClient.bindToApplicationContext(context).build().get().uri("/reservation/11111111-1111-4111-8111-111111111111")
            .exchange().expectStatus().isUnauthorized();
    }
    @Test void catalogoConservaAcceso(){WebTestClient.bindToApplicationContext(context).build().get().uri("/restaurants").exchange().expectStatus().isOk();}
}
