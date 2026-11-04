package com.brenis.SpringWebFlux.support;

import com.brenis.SpringWebFlux.collections.*;
import com.brenis.SpringWebFlux.services.impls.ReservationCrudServiceImpl;
import com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import org.bson.Document;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;
import reactor.core.publisher.*;
import reactor.test.StepVerifier;
import java.time.Duration;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;

@SpringJUnitConfig(AvailabilityIntegrationConfiguration.class)
class AvailabilityLegacyWriterIT {
    @Autowired ReservationCrudServiceImpl service;
    @Autowired RestaurantOperationCoordinator coordinator;
    @Autowired ReactiveMongoTemplate mongo;
    UUID restaurant;
    @Test void arranqueStandaloneSeRechazaInclusoConGateDesactivado() {
        assertThatThrownBy(() -> isolatedContext(false,false)).hasStackTraceContaining("replica");
    }
    @Test void gateActivadoSinEmisorSeRechaza() {
        assertThatThrownBy(() -> isolatedContext(true,true)).hasStackTraceContaining("issuer");
    }
    @Test void replicaConGateDesactivadoNoExigeEmisor() {
        try (var context=isolatedContext(true,false)) {
            assertThat(context.isActive()).isTrue();
            assertThat(context.getBean(com.brenis.SpringWebFlux.configs.AvailabilityProperties.class)
                    .isEnabled()).isFalse();
        }
    }
    private org.springframework.context.annotation.AnnotationConfigApplicationContext isolatedContext(
            boolean replica, boolean enabled) {
        var context=new org.springframework.context.annotation.AnnotationConfigApplicationContext();
        context.getEnvironment().getPropertySources().addFirst(
                new org.springframework.core.env.MapPropertySource("test-only",java.util.Map.of(
                        "availability.test.replica",replica,"availability.enabled",enabled)));
        context.register(AvailabilityIntegrationConfiguration.class);
        try { context.refresh(); return context; }
        catch (RuntimeException failure) { context.close(); throw failure; }
    }
    @BeforeEach void prepare() {
        restaurant=UUID.randomUUID();
        mongo.save(RestaurantCollection.builder().id(restaurant).name("Restaurant")
                .closeAt("23:59").build()).block();
        if (!Boolean.TRUE.equals(mongo.collectionExists("availability_probe").block()))
            mongo.createCollection("availability_probe").block();
        if (!Boolean.TRUE.equals(mongo.collectionExists("reservations").block()))
            mongo.createCollection("reservations").block();
    }
    ReservationCollection input() {
        return ReservationCollection.builder().restaurantId(restaurant.toString())
                .customerId(UUID.randomUUID().toString()).customerName("Test customer")
                .date("2026-11-02").time("12:00").partySize(2).build();
    }
    long revision() {
        Document value=mongo.findById(restaurant,Document.class,"restaurant_operations").block();
        return value==null?0L:((Number)value.get("revision")).longValue();
    }
    @Test void createUpdateDeleteAntiguosUsanLaMismaRevisionSinHeadersNuevos() {
        var created=service.createReservation(input()).block(Duration.ofSeconds(10));
        assertThat(revision()).isEqualTo(1L);
        ReservationCollection update=input(); update.setNotes("updated");
        var updated=service.updateReservation(created.getId(),update).block(Duration.ofSeconds(10));
        assertThat(updated.getId()).isEqualTo(created.getId());
        assertThat(updated.getNotes()).isEqualTo("updated");
        assertThat(revision()).isEqualTo(2L);
        service.deleteReservation(created.getId()).block(Duration.ofSeconds(10));
        assertThat(revision()).isEqualTo(3L);
        assertThat(mongo.findById(created.getId(),ReservationCollection.class).block()).isNull();
    }
    @Test void cambioDeRestauranteNoConfirmaIncrementoNiMutaReserva() {
        var created=service.createReservation(input()).block();
        long before=revision();
        var update=input(); update.setRestaurantId(UUID.randomUUID().toString());
        StepVerifier.create(service.updateReservation(created.getId(),update)).expectError().verify();
        assertThat(revision()).isEqualTo(before);
        assertThat(mongo.findById(created.getId(),ReservationCollection.class).block().getRestaurantId())
                .isEqualTo(restaurant.toString());
    }
    @Test void writerAntiguoCompiteConConfiguracionEnLaMismaFrontera() {
        Sinks.One<Void> inside=Sinks.one();
        var metadata=new CommandMetadata(UUID.randomUUID().toString(),"POST:/probe",null,201,"/catalog/probe");
        var configuration=coordinator.write(restaurant,Document.class,metadata,ctx -> {
            inside.tryEmitEmpty();
            return Mono.delay(Duration.ofMillis(200)).then(mongo.insert(
                    new Document("_id",UUID.randomUUID().toString()),"availability_probe"));
        });
        var request=input();
        var legacy=inside.asMono().then(service.createReservation(request));
        // materialize conserva ambas terminaciones: un conflicto no cancela la transacción competidora.
        var outcomes=Mono.zip(configuration.materialize(),legacy.materialize()).block(Duration.ofSeconds(15));
        assertThat(outcomes.getT1().isOnNext()).isTrue();
        var countQuery=org.springframework.data.mongodb.core.query.Query.query(
                org.springframework.data.mongodb.core.query.Criteria.where("restaurantId").is(restaurant.toString()));
        if(outcomes.getT2().isOnError()) {
            assertThat(com.brenis.SpringWebFlux.configs.MongoConfig.hasLabel(
                    outcomes.getT2().getThrowable(),"TransientTransactionError")).isTrue();
            assertThat(revision()).isEqualTo(1L);
            assertThat(mongo.count(countQuery,ReservationCollection.class).block()).isZero();
            // Reintento explícito del cliente una vez terminada la competidora, no cuarto intento interno.
            assertThat(service.createReservation(request).block(Duration.ofSeconds(10))).isNotNull();
        } else {
            assertThat(outcomes.getT2().isOnNext()).isTrue();
        }
        assertThat(revision()).isEqualTo(2L);
        assertThat(mongo.count(countQuery,ReservationCollection.class).block()).isEqualTo(1L);
    }
}

