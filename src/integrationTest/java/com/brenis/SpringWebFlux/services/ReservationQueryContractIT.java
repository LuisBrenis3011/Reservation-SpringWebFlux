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

@SpringJUnitConfig(ReservationQueryContractIT.Configuration.class)
class ReservationQueryContractIT extends ReservationQueryIntegrationSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false) @EnableWebFlux
    @Import({ReservationQueryIntegrationSupport.Configuration.class,ReservationSecurityConfig.class,AvailabilitySecurityConfig.class,
        AvailabilityHttpSupport.class,ReservationHttpSupport.class,ReservationQueryHandler.class,ReservationQueryRouter.class,
        ReservationHandler.class,ReservationCrudRouter.class})
    public static class Configuration {
        @Bean ReservationProperties reservationProperties(){var p=new ReservationProperties();p.setEnabled(true);return p;}
        @Bean com.brenis.SpringWebFlux.services.definitions.ReservationBusinessService unusedBusiness(){return org.mockito.Mockito.mock(com.brenis.SpringWebFlux.services.definitions.ReservationBusinessService.class);}
        @Bean com.brenis.SpringWebFlux.validators.ReactiveValidator unusedValidator(){return org.mockito.Mockito.mock(com.brenis.SpringWebFlux.validators.ReactiveValidator.class);}
    }
    @Autowired org.springframework.context.ApplicationContext context;
    @Autowired ReservationProperties gate;
    private Map<String,Object> state(){
        var result=new TreeMap<String,Object>();
        for(String name:List.of("restaurants","reservations","restaurant_operations","operation_receipts","restaurant_tables","table_combinations","restaurant_shifts","restaurant_time_zones","reservation_policy")){
            result.put(name+":docs",mongo.find(new org.springframework.data.mongodb.core.query.Query(),org.bson.Document.class,name).collectList().block());
            if(Boolean.TRUE.equals(mongo.collectionExists(name).block()))result.put(name+":indexes",mongo.indexOps(name).getIndexInfo().map(Object::toString).collectList().block());
        }
        return result;
    }
    private void keys(byte[] raw,String... expected){
        var node=tools.jackson.databind.json.JsonMapper.builder().build().readTree(raw);var names=new HashSet<String>();
        node.properties().forEach(entry->names.add(entry.getKey()));assertThat(names).containsExactlyInAnyOrder(expected);
    }
    @Test void cincoRutasConSeguridadEtagYConservacion(){
        var managed=insertManaged(restaurant,"client",false);var legacy=insertLegacy(restaurant);
        var before=state();var client=WebTestClient.bindToApplicationContext(context).apply(springSecurity()).build();
        var own=client.mutateWith(mockJwt().jwt(ReservationIdentityFixture.customer("client",clock)).authorities(new SimpleGrantedAuthority("ROLE_CUSTOMER")));
        var managerClient=client.mutateWith(AvailabilityIdentityFixture.manager(restaurant,clock));
        String collection="/restaurants/"+restaurant+"/reservations",resource=collection+"/"+managed.id();
        own.get().uri("/me/reservations").exchange().expectStatus().isOk().expectHeader().doesNotExist("ETag")
            .expectBody().jsonPath("$.items[0].owner.subject").isEqualTo("client")
            .consumeWith(reply->keys(reply.getResponseBody(),"items","page","size"));
        managerClient.get().uri(collection).exchange().expectStatus().isOk().expectHeader().doesNotExist("ETag")
            .expectBody().jsonPath("$.items.length()").isEqualTo(2).consumeWith(reply->keys(reply.getResponseBody(),"items","page","size"));
        own.get().uri(resource).exchange().expectStatus().isOk().expectHeader().valueEquals("ETag","\"1\"")
            .expectBody().consumeWith(reply->keys(reply.getResponseBody(),"kind","id","restaurantId","owner","shiftId","partySize","notes","status","version","tableIds","combinationId","assignedCapacity","localStart","localEnd","zoneId","startInstant","endInstant","createdAt","updatedAt","cancelledAt"));
        managerClient.get().uri(collection+"/legacy/"+legacyQueries.reference(legacy.get("_id"))).exchange().expectStatus().isOk().expectHeader().doesNotExist("ETag")
            .expectBody().consumeWith(reply->keys(reply.getResponseBody(),"kind","legacyRef","restaurantId","status","customerName","date","time","partySize","notes"));
        client.mutateWith(AvailabilityIdentityFixture.manager(UUID.randomUUID(),clock)).get().uri(collection).exchange().expectStatus().isForbidden();
        var foreignManager=client.mutateWith(AvailabilityIdentityFixture.manager(UUID.randomUUID(),clock));
        foreignManager.get().uri(resource).exchange().expectStatus().isForbidden();
        foreignManager.get().uri(collection+"/"+UUID.randomUUID()).exchange().expectStatus().isForbidden();
        for(String query:List.of("page=0&page=1","size=0","size=101","status=PENDING","status=CONFIRMED&status=CANCELLED"))
            own.get().uri("/me/reservations?"+query).exchange().expectStatus().isBadRequest();
        client.mutateWith(mockJwt().jwt(ReservationIdentityFixture.customer("other",clock)).authorities(new SimpleGrantedAuthority("ROLE_CUSTOMER")))
            .get().uri(resource).exchange().expectStatus().isNotFound();
        try{
            gate.setEnabled(false);
            managerClient.get().uri(resource).exchange().expectStatus().isNotFound();
            managerClient.get().uri("/reservation/"+managed.id()).exchange().expectStatus().isOk().expectHeader().valueEquals("ETag","\"1\"")
                .expectBody().jsonPath("$.kind").isEqualTo("MANAGED");
            own.get().uri("/reservation/"+managed.id()).exchange().expectStatus().isForbidden();
            client.get().uri("/reservation/"+managed.id()).exchange().expectStatus().isUnauthorized();
        }finally{gate.setEnabled(true);}
        assertThat(state()).isEqualTo(before);
    }
}
