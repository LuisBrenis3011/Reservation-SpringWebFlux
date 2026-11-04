package com.brenis.SpringWebFlux.services;
import java.time.*;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.validators.ReservationTimePolicy;
import com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator.MutationOutcome;
import static org.assertj.core.api.Assertions.*;

class ReservationCoordinatorOutcomeTests {
    @org.junit.jupiter.params.ParameterizedTest
    @org.junit.jupiter.params.provider.ValueSource(booleans={true,false})
    void changedYNoChangeEsperanCommitYConservanFirmas(boolean changed){
        var fixture=new CoordinatorFixture();
        var command=new com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata("key","hash",null,201,"/reservation/original");
        var result=changed?fixture.coordinator.write(fixture.owner,String.class,command,ctx->reactor.core.publisher.Mono.just("body"))
            :fixture.coordinator.writeWithOutcome(fixture.owner,String.class,command,ctx->reactor.core.publisher.Mono.just(new MutationOutcome<>("body",false)));
        reactor.test.StepVerifier.create(result)
            .expectSubscription().expectNoEvent(Duration.ofMillis(10))
            .then(()->{
                assertThat(fixture.receipt.get()).isNotNull();
                assertThat(fixture.receipt.get().resultingRevision()).isEqualTo(changed?1L:0L);
                fixture.commit.tryEmitEmpty();
            })
            .assertNext(value->{assertThat(value.body()).isEqualTo("body");assertThat(value.revision()).isEqualTo(changed?1L:0L);})
            .verifyComplete();
        org.mockito.Mockito.verify(fixture.mongo,org.mockito.Mockito.times(changed?0:1)).updateFirst(
            org.mockito.ArgumentMatchers.any(org.springframework.data.mongodb.core.query.Query.class),
            org.mockito.ArgumentMatchers.any(org.springframework.data.mongodb.core.query.Update.class),org.mockito.ArgumentMatchers.eq("restaurant_operations"));
    }
    @Test void replayRestauraRespuestaDespuesDeRollbackSinInvocarTrabajo(){
        var fixture=new CoordinatorFixture();
        var saved=new com.brenis.SpringWebFlux.collections.OperationReceiptCollection(java.util.UUID.randomUUID(),fixture.owner,"key","hash",201,"original",0,"/original");
        org.mockito.Mockito.when(fixture.mongo.findOne(org.mockito.ArgumentMatchers.any(org.springframework.data.mongodb.core.query.Query.class),
            org.mockito.ArgumentMatchers.eq(com.brenis.SpringWebFlux.collections.OperationReceiptCollection.class))).thenReturn(reactor.core.publisher.Mono.just(saved));
        var command=new com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata("key","hash",null,200,"/different");
        reactor.test.StepVerifier.create(fixture.coordinator.writeWithOutcome(fixture.owner,String.class,command,
            ctx->reactor.core.publisher.Mono.<MutationOutcome<String>>error(new AssertionError("No ejecutar callback"))))
            .assertNext(value->{assertThat(fixture.rollbacks).hasValue(1);assertThat(value.body()).isEqualTo("original");
                assertThat(value.httpStatus()).isEqualTo(201);assertThat(value.location()).isEqualTo("/original");assertThat(value.revision()).isZero();})
            .verifyComplete();
        assertThat(fixture.receipt.get()).isNull();
    }
    private static final class CoordinatorFixture {
        final java.util.UUID owner=java.util.UUID.randomUUID();
        final org.springframework.data.mongodb.core.ReactiveMongoTemplate mongo=org.mockito.Mockito.mock(org.springframework.data.mongodb.core.ReactiveMongoTemplate.class);
        final reactor.core.publisher.Sinks.Empty<Void> commit=reactor.core.publisher.Sinks.empty();
        final java.util.concurrent.atomic.AtomicInteger rollbacks=new java.util.concurrent.atomic.AtomicInteger();
        final java.util.concurrent.atomic.AtomicReference<com.brenis.SpringWebFlux.collections.OperationReceiptCollection> receipt=new java.util.concurrent.atomic.AtomicReference<>();
        final com.brenis.SpringWebFlux.services.impls.RestaurantOperationCoordinatorImpl coordinator;
        @SuppressWarnings({"unchecked","rawtypes"}) CoordinatorFixture(){
            var init=org.mockito.Mockito.mock(com.brenis.SpringWebFlux.configs.AvailabilityInfrastructureInitializer.class);
            var tx=org.mockito.Mockito.mock(org.springframework.transaction.reactive.TransactionalOperator.class);
            org.mockito.Mockito.when(init.ensureInitialized(owner)).thenReturn(reactor.core.publisher.Mono.empty());
            org.mockito.Mockito.when(tx.transactional(org.mockito.ArgumentMatchers.any(reactor.core.publisher.Mono.class))).thenAnswer(call->{
                reactor.core.publisher.Mono<Object> source=call.getArgument(0);
                return source.doOnError(error->rollbacks.incrementAndGet()).flatMap(value->commit.asMono().thenReturn(value));
            });
            org.mockito.Mockito.when(mongo.findAndModify(org.mockito.ArgumentMatchers.any(org.springframework.data.mongodb.core.query.Query.class),
                org.mockito.ArgumentMatchers.any(org.springframework.data.mongodb.core.query.Update.class),org.mockito.ArgumentMatchers.any(org.springframework.data.mongodb.core.FindAndModifyOptions.class),
                org.mockito.ArgumentMatchers.eq(org.bson.Document.class),org.mockito.ArgumentMatchers.eq("restaurant_operations")))
                .thenReturn(reactor.core.publisher.Mono.just(new org.bson.Document("revision",1L)));
            org.mockito.Mockito.when(mongo.findOne(org.mockito.ArgumentMatchers.any(org.springframework.data.mongodb.core.query.Query.class),
                org.mockito.ArgumentMatchers.eq(com.brenis.SpringWebFlux.collections.OperationReceiptCollection.class))).thenReturn(reactor.core.publisher.Mono.empty());
            org.mockito.Mockito.when(mongo.updateFirst(org.mockito.ArgumentMatchers.any(org.springframework.data.mongodb.core.query.Query.class),
                org.mockito.ArgumentMatchers.any(org.springframework.data.mongodb.core.query.Update.class),org.mockito.ArgumentMatchers.eq("restaurant_operations")))
                .thenReturn(reactor.core.publisher.Mono.just(com.mongodb.client.result.UpdateResult.acknowledged(1L,1L,null)));
            org.mockito.Mockito.when(mongo.insert(org.mockito.ArgumentMatchers.any(com.brenis.SpringWebFlux.collections.OperationReceiptCollection.class))).thenAnswer(call->{
                com.brenis.SpringWebFlux.collections.OperationReceiptCollection value=call.getArgument(0);receipt.set(value);return reactor.core.publisher.Mono.just(value);
            });
            coordinator=new com.brenis.SpringWebFlux.services.impls.RestaurantOperationCoordinatorImpl(mongo,tx,init,new com.brenis.SpringWebFlux.configs.AvailabilityProperties(),
                Clock.systemUTC(),new com.brenis.SpringWebFlux.observability.AvailabilityTelemetry(new io.micrometer.core.instrument.simple.SimpleMeterRegistry()));
        }
    }
    @Test void falloDeInicializacionNoEjecutaCallbackNiEscribe(){
        var mongo=org.mockito.Mockito.mock(org.springframework.data.mongodb.core.ReactiveMongoTemplate.class);
        var init=org.mockito.Mockito.mock(com.brenis.SpringWebFlux.configs.AvailabilityInfrastructureInitializer.class);
        var transactions=org.mockito.Mockito.mock(org.springframework.transaction.reactive.TransactionalOperator.class);
        var telemetry=new com.brenis.SpringWebFlux.observability.AvailabilityTelemetry(new io.micrometer.core.instrument.simple.SimpleMeterRegistry());
        var coordinator=new com.brenis.SpringWebFlux.services.impls.RestaurantOperationCoordinatorImpl(mongo,transactions,init,
            new com.brenis.SpringWebFlux.configs.AvailabilityProperties(),Clock.systemUTC(),telemetry);
        var id=java.util.UUID.randomUUID();
        org.mockito.Mockito.when(init.ensureInitialized(id)).thenReturn(reactor.core.publisher.Mono.error(
            new com.brenis.SpringWebFlux.exceptions.AvailabilityException("DEPENDENCY_UNAVAILABLE","No inicializado")));
        var calls=new java.util.concurrent.atomic.AtomicInteger();
        var command=new com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata("key","hash",null,200,null);
        reactor.test.StepVerifier.create(coordinator.writeWithOutcome(id,String.class,command,ctx->{calls.incrementAndGet();return reactor.core.publisher.Mono.just(new MutationOutcome<>("cancelada",false));}))
            .expectErrorMatches(e->e.getMessage().contains("DEPENDENCY_UNAVAILABLE")).verify();
        assertThat(calls).hasValue(0);org.mockito.Mockito.verifyNoInteractions(mongo,transactions);
    }
    @Test void limitesTemporalesInclusivosYNoOpFueraDePlazo(){
        var policy=new ReservationTimePolicy();var now=Instant.parse("2026-11-01T10:00:00Z");
        assertThatCode(()->policy.confirm(now,now.plus(Duration.ofHours(2)),20)).doesNotThrowAnyException();
        assertThatCode(()->policy.confirm(now,now.plus(Duration.ofDays(90)),1)).doesNotThrowAnyException();
        assertThatThrownBy(()->policy.confirm(now,now.plus(Duration.ofHours(2)).minusNanos(1),1)).hasMessageContaining("RESERVATION_WINDOW_CLOSED");
        assertThatCode(()->policy.cancel(now,now.minusSeconds(1),false,true)).doesNotThrowAnyException();
    }
}
