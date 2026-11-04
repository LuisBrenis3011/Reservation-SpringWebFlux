package com.brenis.SpringWebFlux.services;
import java.util.*;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationReplacementSupport;
import com.brenis.SpringWebFlux.dtos.requests.*;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.FindAndModifyOptions;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.UpdateDefinition;
import com.brenis.SpringWebFlux.repositories.ReservationOccupancyReader;
import com.brenis.SpringWebFlux.configs.MongoConfig;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class ReservationReplaceConcurrencyIT extends ReservationReplacementSupport {
    @MockitoSpyBean ReactiveMongoTemplate observedMongo;
    @MockitoSpyBean ReservationOccupancyReader observedOccupancy;

    /** Retiene el primer callback con su revision bloqueada hasta observar un conflicto Mongo real del competidor. */
    @SuppressWarnings("unchecked")
    private java.util.List<reactor.core.publisher.Signal<?>> overlap(Mono<?> first,Mono<?> second){
        var acquired=Sinks.<Void>one();var collided=Sinks.<Void>one();
        var held=new AtomicBoolean();var conflicts=new AtomicInteger();
        doAnswer(call->{
            Mono<ReservationOccupancyReader.Occupancy> real=(Mono<ReservationOccupancyReader.Occupancy>)call.callRealMethod();
            return real.flatMap(value->{
                if(!held.compareAndSet(false,true))return Mono.just(value);
                acquired.tryEmitEmpty();
                return collided.asMono().timeout(Duration.ofSeconds(2)).thenReturn(value);
            });
        }).when(observedOccupancy).read(eq(restaurant),any(UUID.class),any(UUID.class),any(java.time.Instant.class));
        doAnswer(call->{
            Mono<Document> real=(Mono<Document>)call.callRealMethod();
            return real.doOnError(error->{
                if(held.get()&&MongoConfig.hasLabel(error,"TransientTransactionError")){
                    conflicts.incrementAndGet();collided.tryEmitEmpty();
                }
            });
        }).when(observedMongo).findAndModify(any(Query.class),any(UpdateDefinition.class),any(FindAndModifyOptions.class),eq(Document.class),eq("restaurant_operations"));
        try{
            var result=Mono.zip(first.materialize(),
                acquired.asMono().timeout(Duration.ofSeconds(2)).then(second).materialize())
                .map(pair->java.util.List.<reactor.core.publisher.Signal<?>>of(pair.getT1(),pair.getT2()))
                .block(Duration.ofSeconds(8));
            assertThat(held).isTrue();assertThat(conflicts.get()).isGreaterThan(0);
            return result;
        }finally{collided.tryEmitEmpty();reset(observedMongo,observedOccupancy);}
    }
    private boolean exhausted(java.util.List<reactor.core.publisher.Signal<?>> signals){
        return signals.stream().anyMatch(s->s.isOnError()&&s.getThrowable().getMessage().contains("DEPENDENCY_UNAVAILABLE"));
    }
    private void rejectWithoutChanges(Runnable attempt,String code){
        var before=state();assertThatThrownBy(attempt::run).hasMessageContaining(code);assertThat(state()).isEqualTo(before);
    }
    @Test void esc0709_dosEdicionesDeLaMismaVersionNoSeSobrescriben(){
        var first=confirm("client","first",3).block().body();
        var signals=overlap(replace(customer("client"),first.id(),1,"one",shift,3,"Uno"),
            replace(customer("client"),first.id(),1,"two",shift,3,"Dos"));
        assertThat(signals.stream().filter(reactor.core.publisher.Signal::hasValue).count()).isEqualTo(1);
        for(var s:signals)if(s.isOnError())assertThat(s.getThrowable().getMessage()).containsAnyOf("REVISION_MISMATCH","DEPENDENCY_UNAVAILABLE");
        assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);
        if(exhausted(signals)){
            boolean firstWon=signals.get(0).hasValue();
            rejectWithoutChanges(()->replace(customer("client"),first.id(),1,firstWon?"two":"one",shift,3,firstWon?"Dos":"Uno").block(),"REVISION_MISMATCH");
        }
        var before=state();assertThatThrownBy(()->replace(customer("client"),first.id(),1,"stale",shift,3,"Viejo").block()).hasMessageContaining("REVISION_MISMATCH");
        assertThat(state()).isEqualTo(before);
    }
    @Test void esc0710_edicionYConfirmacionCompitenPorDestinoSinPerderOrigen(){
        var first=confirm("client","first",3).block().body();UUID target=destination(18000);
        var signals=overlap(replace(customer("client"),first.id(),1,"move",target,3,""),
            confirm("other","target",new ManagedReservationRequest(target,3,"")));
        assertThat(signals.stream().filter(reactor.core.publisher.Signal::hasValue).count()).isEqualTo(1);
        for(var s:signals)if(s.isOnError())assertThat(s.getThrowable().getMessage()).containsAnyOf("NO_AVAILABILITY","DEPENDENCY_UNAVAILABLE");
        var current=mongo.findById(first.id(),Document.class,"reservations").block();
        boolean moved=((Number)current.get("version")).longValue()==2;
        assertThat(com.brenis.SpringWebFlux.repositories.LegacyReservationCommitmentAdapter.uuid(current.get("shiftId"))).isEqualTo(moved?target:shift);
        assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);
        var targetRows=mongo.find(org.springframework.data.mongodb.core.query.Query.query(
            org.springframework.data.mongodb.core.query.Criteria.where("restaurantId").is(restaurant).and("shiftId").is(target)),Document.class,"reservations").collectList().block();
        assertThat(targetRows).hasSize(1);
        if(exhausted(signals)){
            if(signals.get(0).hasValue())rejectWithoutChanges(()->confirm("other","target",new ManagedReservationRequest(target,3,"")).block(),"NO_AVAILABILITY");
            else rejectWithoutChanges(()->replace(customer("client"),first.id(),1,"move",target,3,"").block(),"NO_AVAILABILITY");
        }
    }
    @Test void configuracionConcurrenteNoCambiaCapacidadComprometida(){
        var first=confirm("client","first",3).block().body();
        var signals=overlap(replace(customer("client"),first.id(),1,"notes",shift,3,"Notas"),
            patch(table,"capacity",new TablePatchRequest(null,2L),1));
        assertThat(signals.stream().filter(reactor.core.publisher.Signal::hasValue).count()).isEqualTo(1);
        for(var s:signals)if(s.isOnError())assertThat(s.getThrowable().getMessage()).containsAnyOf("PROTECTED_RESERVATION","REVISION_MISMATCH","DEPENDENCY_UNAVAILABLE");
        assertThat(mongo.findById(table,com.brenis.SpringWebFlux.collections.TableCollection.class).block().capacity()).isEqualTo(4);
        assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);
        if(exhausted(signals))rejectWithoutChanges(()->patch(table,"capacity",new TablePatchRequest(null,2L),1).block(),"REVISION_MISMATCH");
    }
    @Test void t188_edicionGanaACancelacionConSolapamientoReal(){
        var first=confirm("client","first",3).block().body();
        var metadata=new com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata("cancel-race","cancel:"+first.id()+":1",null,200,null);
        var signals=overlap(replace(customer("client"),first.id(),1,"edit-before-cancel",shift,3,"Editada"),
            commands.cancel(customer("client"),restaurant,first.id(),1,metadata));
        assertThat(signals.get(0).hasValue()).isTrue();assertThat(signals.get(1).isOnError()).isTrue();
        assertThat(signals.get(1).getThrowable().getMessage()).containsAnyOf("REVISION_MISMATCH","DEPENDENCY_UNAVAILABLE");
        var current=mongo.findById(first.id(),Document.class,"reservations").block();
        assertThat(current.getString("status")).isEqualTo("CONFIRMED");assertThat(current.getString("notes")).isEqualTo("Editada");
        assertThat(((Number)current.get("version")).longValue()).isEqualTo(2);assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);
        rejectWithoutChanges(()->commands.cancel(customer("client"),restaurant,first.id(),1,metadata).block(),"REVISION_MISMATCH");
        commands.cancel(customer("client"),restaurant,first.id(),2,
            new com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata("cancel-current","cancel:"+first.id()+":2",null,200,null)).block();
        assertThat(revision()).isEqualTo(3);assertThat(mongo.findById(first.id(),Document.class,"reservations").block().getString("status")).isEqualTo("CANCELLED");
    }
}
