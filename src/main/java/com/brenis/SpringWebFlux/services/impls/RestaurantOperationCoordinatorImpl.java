package com.brenis.SpringWebFlux.services.impls;
import java.time.Clock;
import java.util.UUID;
import java.util.function.Function;
import org.bson.Document;
import org.springframework.stereotype.Service;
import org.springframework.data.mongodb.core.*;
import org.springframework.data.mongodb.core.query.*;
import org.springframework.transaction.reactive.TransactionalOperator;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.configs.*;
import com.brenis.SpringWebFlux.collections.OperationReceiptCollection;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator;
import com.brenis.SpringWebFlux.observability.AvailabilityTelemetry;
@Service
public class RestaurantOperationCoordinatorImpl implements RestaurantOperationCoordinator {
    private final ReactiveMongoTemplate mongo;
    private final TransactionalOperator transactions;
    private final AvailabilityInfrastructureInitializer initializer;
    private final AvailabilityProperties properties;
    private final Clock clock;
    private final AvailabilityTelemetry telemetry;
    private com.brenis.SpringWebFlux.observability.ReservationTelemetry reservationTelemetry;
    @org.springframework.beans.factory.annotation.Autowired(required=false)
    void reservationTelemetry(com.brenis.SpringWebFlux.observability.ReservationTelemetry value){this.reservationTelemetry=value;}
    public RestaurantOperationCoordinatorImpl(ReactiveMongoTemplate mongo,TransactionalOperator transactions,
            AvailabilityInfrastructureInitializer initializer,AvailabilityProperties properties,Clock clock,AvailabilityTelemetry telemetry) {
        this.mongo=mongo; this.transactions=transactions; this.initializer=initializer; this.properties=properties; this.clock=clock;
        this.telemetry=telemetry;
    }
    private Query owner(UUID id) { return Query.query(Criteria.where("_id").is(id)); }
    private static final class Replay extends RuntimeException {
        final Result<?> result; Replay(Result<?> result) { this.result=result; }
    }
    private static boolean outcomeUnknown(Throwable e) {
        for(Throwable t=e;t!=null;t=t.getCause())
            if(t instanceof AvailabilityException a && a.code().equals("OPERATION_OUTCOME_UNKNOWN")) return true;
        return MongoConfig.hasLabel(e,"UnknownTransactionCommitResult");
    }
    private <T> Mono<T> attempt(Function<Integer,Mono<T>> action,int number) {
        return Mono.defer(() -> action.apply(number)).onErrorResume(e -> {
            if(!outcomeUnknown(e) && MongoConfig.hasLabel(e,"TransientTransactionError") && number<properties.getMaxTransactionAttempts())
                return Mono.delay(number==1?properties.getFirstRetryBackoff():properties.getSecondRetryBackoff())
                        .then(attempt(action,number+1));
            return Mono.error(e);
        });
    }
    private <T> T restoreBody(Object stored,Class<T> responseType) {
        if(responseType.isInstance(stored)) return responseType.cast(stored);
        Document bson=new Document();
        if(stored instanceof java.util.Map<?,?> map) {
            map.forEach((key,value) -> bson.put(key.toString(),value));
        } else {
            mongo.getConverter().write(stored,bson);
        }
        return responseType==Document.class?responseType.cast(bson):mongo.getConverter().read(responseType,bson);
    }
    @Override public <T> Mono<Result<T>> write(UUID id,Class<T> responseType,CommandMetadata command,Function<Context,Mono<T>> work) {
        return writeWithOutcome(id,responseType,command,ctx->work.apply(ctx).map(value->new MutationOutcome<>(value,true)));
    }
    @Override public <T> Mono<Result<T>> writeWithOutcome(UUID id,Class<T> responseType,CommandMetadata command,Function<Context,Mono<MutationOutcome<T>>> work) {
        return Mono.deferContextual(context->{
            String operationId=AvailabilityTelemetry.operationId(context);
            var outcome=new java.util.concurrent.atomic.AtomicReference<>(com.brenis.SpringWebFlux.observability.ReservationTelemetry.Outcome.REPLAY);
            return telemetry.observe(AvailabilityTelemetry.Operation.WRITE,id,() -> writeObserved(id,responseType,command,ctx->work.apply(ctx).doOnNext(value->outcome.set(value.businessChanged()
                ?com.brenis.SpringWebFlux.observability.ReservationTelemetry.Outcome.ACCEPTED:com.brenis.SpringWebFlux.observability.ReservationTelemetry.Outcome.NO_OP)),
                ()->outcome.set(com.brenis.SpringWebFlux.observability.ReservationTelemetry.Outcome.REPLAY)))
                .doOnSuccess(result->{if(result!=null&&reservationTelemetry!=null&&command.idempotencyKey().startsWith("rsv:"))reservationTelemetry.record(outcome.get(),operationId);})
                .doOnError(error->{if(reservationTelemetry!=null&&command.idempotencyKey().startsWith("rsv:"))reservationTelemetry.record(
                    failureOutcome(error),operationId);})
                .contextWrite(parent->parent.put("availability.operationId",operationId));
        });
    }
    private com.brenis.SpringWebFlux.observability.ReservationTelemetry.Outcome failureOutcome(Throwable error){
        if(outcomeUnknown(error))return com.brenis.SpringWebFlux.observability.ReservationTelemetry.Outcome.UNCERTAIN;
        if(MongoConfig.hasLabel(error,"TransientTransactionError"))return com.brenis.SpringWebFlux.observability.ReservationTelemetry.Outcome.CONTENTION;
        for(Throwable cause=error;cause!=null;cause=cause.getCause())if(cause instanceof AvailabilityException known&&known.code().equals("REVISION_MISMATCH"))
            return com.brenis.SpringWebFlux.observability.ReservationTelemetry.Outcome.VERSION_CONFLICT;
        return com.brenis.SpringWebFlux.observability.ReservationTelemetry.Outcome.REJECTED;
    }
    private <T> Mono<Result<T>> writeObserved(UUID id,Class<T> responseType,CommandMetadata command,Function<Context,Mono<MutationOutcome<T>>> work,Runnable replayed) {
        java.util.Objects.requireNonNull(responseType,"responseType");
        if(command.fingerprint()==null || command.fingerprint().isBlank())
            return Mono.error(new AvailabilityException("INVALID_REQUEST","Fingerprint requerido"));
        return initializer.ensureInitialized(id).then(attempt(n -> {
            Mono<Result<T>> body=mongo.findAndModify(owner(id),new Update().inc("revision",1),
                    FindAndModifyOptions.options().returnNew(true),Document.class,"restaurant_operations")
                .switchIfEmpty(Mono.error(new AvailabilityException("DEPENDENCY_UNAVAILABLE","Revisión ausente")))
                .flatMap(op -> {
                    long revision=((Number)op.get("revision")).longValue();
                    var receiptQuery=Query.query(Criteria.where("restaurantId").is(id).and("idempotencyKey").is(command.idempotencyKey()));
                    return mongo.findOne(receiptQuery,OperationReceiptCollection.class).flatMap(receipt -> {
                        if(!receipt.fingerprint().equals(command.fingerprint()))
                            return Mono.<Result<T>>error(new AvailabilityException("IDEMPOTENCY_CONFLICT","Clave usada con otro comando"));
                        return Mono.<Result<T>>error(new Replay(new Result<>(restoreBody(receipt.responseBody(),responseType),receipt.resultingRevision(),
                                receipt.httpStatus(),receipt.location())));
                    }).switchIfEmpty(Mono.defer(() -> {
                        if(command.expectedRevision()!=null && command.expectedRevision()!=revision-1)
                            return Mono.error(new AvailabilityException("REVISION_MISMATCH","If-Match obsoleto"));
                        return work.apply(new Context(id,revision,clock.instant())).flatMap(outcome -> {
                            long resultingRevision=outcome.businessChanged()?revision:revision-1;
                            Mono<Void> restore=outcome.businessChanged()?Mono.empty():mongo.updateFirst(owner(id),new Update().inc("revision",-1),"restaurant_operations").then();
                            return restore.then(mongo.insert(new OperationReceiptCollection(UUID.randomUUID(),id,command.idempotencyKey(),
                                    command.fingerprint(),command.httpStatus(),outcome.body(),resultingRevision,command.location())))
                                    .thenReturn(new Result<>(outcome.body(),resultingRevision,command.httpStatus(),command.location()));
                        });
                    }));
                });
            return transactions.transactional(Mono.deferContextual(context -> body.timeout(java.time.Duration.ofNanos(
                            Math.max(1L,context.<Long>getOrDefault("availability.deadline",
                                    System.nanoTime()+properties.getTransactionTimeout().toNanos())-System.nanoTime())))))
                    .onErrorResume(Replay.class,replay -> {
                        @SuppressWarnings("unchecked") Result<T> saved=(Result<T>)replay.result;
                        replayed.run();
                        return telemetry.replay().thenReturn(saved); // rollback ya terminó antes de emitir el recibo
                    });
        },1)).onErrorMap(e -> {
            if(outcomeUnknown(e)) return new AvailabilityException("OPERATION_OUTCOME_UNKNOWN","Repetir la misma Idempotency-Key",e);
            if(e instanceof java.util.concurrent.TimeoutException)
                return new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Operación excedió presupuesto",e);
            if(MongoConfig.hasLabel(e,"TransientTransactionError"))
                return new AvailabilityException("DEPENDENCY_UNAVAILABLE","Conflicto transitorio agotó reintentos",e);
            return e;
        }).contextWrite(context -> context.put("availability.deadline",System.nanoTime()+properties.getTransactionTimeout().toNanos()));
    }
    @Override public <T> Mono<Result<T>> readSnapshot(UUID id,Function<Context,Mono<T>> work) {
        return telemetry.observe(AvailabilityTelemetry.Operation.READ,id,() -> readObserved(id,work));
    }
    private <T> Mono<Result<T>> readObserved(UUID id,Function<Context,Mono<T>> work) {
        return initializer.ensureInitialized(id).then(transactions.transactional(
                mongo.findOne(owner(id),Document.class,"restaurant_operations").flatMap(op -> {
                    long revision=((Number)op.get("revision")).longValue();
                    return work.apply(new Context(id,revision,clock.instant())).map(value -> new Result<>(value,revision,200,null));
                }).timeout(properties.getTransactionTimeout())));
    }
    @Override public <T> Mono<T> writeLegacy(UUID id,Function<Context,Mono<T>> work) {
        return telemetry.observe(AvailabilityTelemetry.Operation.LEGACY,id,() -> legacyObserved(id,work));
    }
    private <T> Mono<T> legacyObserved(UUID id,Function<Context,Mono<T>> work) {
        return initializer.ensureInitialized(id).then(attempt(n -> transactions.transactional(
                mongo.findAndModify(owner(id),new Update().inc("revision",1),FindAndModifyOptions.options().returnNew(true),
                        Document.class,"restaurant_operations").flatMap(op ->
                        // Materializar señal para que Mono<Void> también confirme y complete después de commit.
                        work.apply(new Context(id,((Number)op.get("revision")).longValue(),clock.instant())).materialize()
                                .flatMap(signal -> signal.isOnError()?Mono.error(signal.getThrowable()):Mono.just(signal)))
                        .timeout(properties.getTransactionTimeout()))
                .flatMap(signal -> signal.isOnError()?Mono.error(signal.getThrowable()):
                        signal.hasValue()?Mono.just(signal.get()):Mono.empty()),1));
    }
}

