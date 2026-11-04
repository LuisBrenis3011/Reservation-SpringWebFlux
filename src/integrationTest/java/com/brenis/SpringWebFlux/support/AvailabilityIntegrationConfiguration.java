package com.brenis.SpringWebFlux.support;

import com.brenis.SpringWebFlux.configs.*;
import com.brenis.SpringWebFlux.services.impls.*;
import com.brenis.SpringWebFlux.repositories.LegacyReservationCommitmentAdapter;
import com.brenis.SpringWebFlux.clientes.PlannerMSClient;
import com.brenis.SpringWebFlux.validators.ReservationValidator;
import com.brenis.SpringWebFlux.collections.ReservationCollection;
import com.mongodb.ConnectionString;
import com.mongodb.MongoClientSettings;
import com.mongodb.reactivestreams.client.MongoClient;
import com.mongodb.reactivestreams.client.MongoClients;
import org.bson.UuidRepresentation;
import org.springframework.context.annotation.*;
import org.springframework.data.mongodb.core.*;
import org.springframework.data.mongodb.ReactiveMongoTransactionManager;
import org.springframework.data.mongodb.ReactiveMongoDatabaseFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.mongodb.repository.config.EnableReactiveMongoRepositories;
import org.springframework.transaction.reactive.TransactionalOperator;
import reactor.core.publisher.Mono;
import java.time.Instant;
import static org.mockito.Mockito.*;

/** Contexto de tests, sin aplicación completa, Redis ni llamadas HTTP reales. */
@Configuration(proxyBeanMethods=false)
@EnableReactiveMongoRepositories(basePackages="com.brenis.SpringWebFlux.repositories")
@Import({RestaurantOperationCoordinatorImpl.class, AvailabilityInfrastructureInitializer.class,
        LegacyReservationCommitmentAdapter.class, ReservationMutationGuard.class,
        ReservationCrudServiceImpl.class, AvailabilityMetricsConfig.class,
        com.brenis.SpringWebFlux.observability.AvailabilityTelemetry.class})
class AvailabilityIntegrationConfiguration {
    @Bean(initMethod="start",destroyMethod="close")
    AvailabilityMongoFixture mongoFixture(@Value("${availability.test.replica:true}") boolean replica) {
        return replica ? new AvailabilityMongoFixture().enableCommandFailpoints()
                : new AvailabilityMongoFixture(false);
    }
    @Bean(destroyMethod="close")
    MongoClient mongoClient(AvailabilityMongoFixture fixture) {
        return MongoClients.create(MongoClientSettings.builder()
                .applyConnectionString(new ConnectionString(fixture.replicaSetUri()))
                .uuidRepresentation(UuidRepresentation.STANDARD).build());
    }
    @Bean ReactiveMongoDatabaseFactory databaseFactory(MongoClient client, AvailabilityMongoFixture fixture) {
        return new SimpleReactiveMongoDatabaseFactory(client,fixture.database());
    }
    @Bean(name="reactiveMongoTemplate") ReactiveMongoTemplate mongoTemplate(ReactiveMongoDatabaseFactory factory) {
        return new ReactiveMongoTemplate(factory);
    }
    @Bean ReactiveMongoTransactionManager transactionManager(ReactiveMongoDatabaseFactory factory) {
        var manager = new com.brenis.SpringWebFlux.configs.MongoConfig.AvailabilityTransactionManager(factory, java.time.Duration.ofSeconds(5)); /*
                com.mongodb.TransactionOptions.builder().readConcern(com.mongodb.ReadConcern.SNAPSHOT)
                        .writeConcern(com.mongodb.WriteConcern.MAJORITY)
                        .readPreference(com.mongodb.ReadPreference.primary()).build());
        */ return manager;
    }
    @Bean TransactionalOperator transactionalOperator(ReactiveMongoTransactionManager manager) {
        return TransactionalOperator.create(manager);
    }
    @Bean AvailabilityProperties availabilityProperties(@Value("${availability.enabled:false}") boolean enabled) {
        var properties = new AvailabilityProperties();
        properties.setEnabled(enabled);
        return properties;
    }
    @Bean AvailabilityClockFixture clock() {
        return new AvailabilityClockFixture(Instant.parse("2026-11-01T10:00:00Z"));
    }
    @Bean PlannerMSClient planner() {
        PlannerMSClient planner=mock(PlannerMSClient.class);
        when(planner.verifyAvailability(anyString(),anyString(),any())).thenReturn(Mono.just(true));
        return planner;
    }
    @Bean ReservationValidator<ReservationCollection> reservationValidator(
            com.brenis.SpringWebFlux.repositories.RestaurantRepository restaurants, PlannerMSClient planner) {
        return new ReservationValidator<>(restaurants,planner);
    }
}

