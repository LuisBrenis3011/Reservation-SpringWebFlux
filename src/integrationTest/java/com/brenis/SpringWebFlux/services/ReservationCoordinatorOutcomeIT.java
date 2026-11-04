package com.brenis.SpringWebFlux.services;
import java.util.UUID;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.support.ManagedReservationIntegrationSupport;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator.MutationOutcome;
import static org.assertj.core.api.Assertions.*;

class ReservationCoordinatorOutcomeIT extends ManagedReservationIntegrationSupport {
    @Test void dosNoOpsConcurrentesNoIncrementanRevisionYReintentoEsAcotado(){
        var first=new CommandMetadata(UUID.randomUUID().toString(),"first",null,200,null);
        var second=new CommandMetadata(UUID.randomUUID().toString(),"second",null,200,null);
        var results=reactor.core.publisher.Flux.merge(noOp(first).materialize(),noOp(second).materialize()).collectList().block();
        for(var signal:results)if(signal.isOnError())assertThat(signal.getThrowable()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");
        assertThat(revision()).isZero();
        assertThat(receiptCount()).isEqualTo(results.stream().filter(reactor.core.publisher.Signal::hasValue).count());
        noOp(first).block();noOp(second).block();
        assertThat(receiptCount()).isEqualTo(2);assertThat(revision()).isZero();
    }
    private Mono<com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator.Result<Document>> noOp(CommandMetadata metadata){
        return coordinator.writeWithOutcome(restaurant,Document.class,metadata,ctx->Mono.just(new MutationOutcome<>(new Document("ok",true),false)));
    }
    private Mono<Document> admin(Document command){return mongo.getMongoDatabaseFactory().getMongoDatabase("admin").flatMap(db->Mono.from(db.runCommand(command)));}
    @Test void noOpCommitInciertoConservaRevisionYNoRepiteCallback(){
        var metadata=new CommandMetadata(UUID.randomUUID().toString(),"no-op",null,200,null);
        java.util.concurrent.atomic.AtomicInteger calls=new java.util.concurrent.atomic.AtomicInteger();
        coordinator.readSnapshot(restaurant,ctx->Mono.just(true)).block();long before=revision();
        admin(new Document("configureFailPoint","failCommand").append("mode",new Document("times",1))
            .append("data",new Document("failCommands",java.util.List.of("commitTransaction")).append("errorCode",1)
                .append("errorLabels",java.util.List.of("UnknownTransactionCommitResult")))).block();
        try{
            coordinator.writeWithOutcome(restaurant,Document.class,metadata,ctx->{calls.incrementAndGet();return Mono.just(new MutationOutcome<>(new Document("ok",true),false));}).block(java.time.Duration.ofSeconds(15));
            assertThat(calls).hasValue(1);assertThat(revision()).isEqualTo(before);assertThat(receiptCount()).isEqualTo(1);
        }finally{admin(new Document("configureFailPoint","failCommand").append("mode","off")).block();}
    }
    @Test void noOpPersisteReciboSinRevisionYReplayNoEjecutaCallback(){
        String key=UUID.randomUUID().toString();
        var command=new CommandMetadata(key,"cancel:"+key,null,200,"/original");
        long before=revision();
        var first=coordinator.writeWithOutcome(restaurant,Document.class,command,
            ctx->Mono.just(new MutationOutcome<>(new Document("status","CANCELLED"),false))).block();
        assertThat(revision()).isEqualTo(before);
        assertThat(receiptCount()).isEqualTo(1);
        var replay=coordinator.writeWithOutcome(restaurant,Document.class,command,
            ctx->Mono.<MutationOutcome<Document>>error(new AssertionError("No ejecutar replay"))).block();
        assertThat(replay).isEqualTo(first);assertThat(revision()).isEqualTo(before);
        assertThatThrownBy(()->coordinator.writeWithOutcome(restaurant,Document.class,
            new CommandMetadata(key,"different",null,200,null),ctx->Mono.just(new MutationOutcome<>(new Document(),false))).block())
            .hasMessageContaining("IDEMPOTENCY_CONFLICT");
        assertThat(receiptCount()).isEqualTo(1);assertThat(revision()).isEqualTo(before);
    }
}
