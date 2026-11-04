package com.brenis.SpringWebFlux.services;
import java.util.*;
import java.time.Duration;
import java.util.concurrent.atomic.*;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.data.mongodb.core.*;
import org.springframework.data.mongodb.core.query.*;
import reactor.core.publisher.*;
import com.brenis.SpringWebFlux.support.ReservationCancellationSupport;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection;
import com.brenis.SpringWebFlux.repositories.ManagedReservationRepository;
import com.brenis.SpringWebFlux.configs.MongoConfig;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class ReservationCancellationConcurrencyIT extends ReservationCancellationSupport {
    @MockitoSpyBean ReactiveMongoTemplate observedMongo;
    @MockitoSpyBean ManagedReservationRepository observedReservations;
    @SuppressWarnings("unchecked")
    private List<Signal<?>> overlap(Mono<?> cancellation,Mono<?> competitor){
        var saved=Sinks.<Void>one();var conflict=Sinks.<Void>one();var held=new AtomicBoolean();var collisions=new AtomicInteger();
        doAnswer(call->{Mono<Boolean> real=(Mono<Boolean>)call.callRealMethod();return real.flatMap(value->{
            if(value&&held.compareAndSet(false,true)){saved.tryEmitEmpty();return conflict.asMono().timeout(Duration.ofSeconds(2)).thenReturn(value);}
            return Mono.just(value);
        });}).when(observedReservations).replace(any(ManagedReservationCollection.class),anyLong());
        doAnswer(call->{Mono<Document> real=(Mono<Document>)call.callRealMethod();return real.doOnError(error->{
            if(held.get()&&MongoConfig.hasLabel(error,"TransientTransactionError")){collisions.incrementAndGet();conflict.tryEmitEmpty();}
        });}).when(observedMongo).findAndModify(any(Query.class),any(UpdateDefinition.class),any(FindAndModifyOptions.class),eq(Document.class),eq("restaurant_operations"));
        try{
            var results=Mono.zip(cancellation.materialize(),saved.asMono().timeout(Duration.ofSeconds(2)).then(competitor).materialize())
                .map(pair->List.<Signal<?>>of(pair.getT1(),pair.getT2())).block(Duration.ofSeconds(8));
            assertThat(held).isTrue();assertThat(collisions.get()).isPositive();assertThat(results.get(0).hasValue()).isTrue();
            verify(observedReservations,times(1)).replace(any(ManagedReservationCollection.class),anyLong());return results;
        }finally{conflict.tryEmitEmpty();reset(observedMongo,observedReservations);}
    }
    @Test void esc0807_dosCancelacionesSoloUnaTransicionYNoopConfirmado(){
        var first=confirm("client","first",2).block().body();var original=raw(first.id());
        var results=overlap(cancel(customer("client"),first.id(),1,"one"),cancel(manager,first.id(),1,"two"));
        if(results.get(1).isOnError()){
            assertThat(results.get(1).getThrowable()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");
            assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);historyUnchanged(original,raw(first.id()));
        }
        var current=raw(first.id());
        var repeated=cancel(manager,first.id(),1,"two").block();assertThat(repeated.body().version()).isEqualTo(2);
        assertThat(raw(first.id())).isEqualTo(current);historyUnchanged(original,current);
        assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(3);
        var before=state();cancel(manager,first.id(),1,"two").block();assertThat(state()).isEqualTo(before);
    }
    @Test void esc0808_cancelarGanaAEdicionSinOcupacionHuerfana(){
        var first=confirm("client","first",2).block().body();var original=raw(first.id());
        var results=overlap(cancel(customer("client"),first.id(),1,"cancel"),replace(customer("client"),first.id(),1,"edit",shift,3,"No aplicar"));
        assertThat(results.get(1).isOnError()).isTrue();assertThat(results.get(1).getThrowable().getMessage()).containsAnyOf("RESERVATION_NOT_EDITABLE","DEPENDENCY_UNAVAILABLE");
        assertThat(raw(first.id()).getString("status")).isEqualTo("CANCELLED");historyUnchanged(original,raw(first.id()));
        assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);
        var before=state();assertThatThrownBy(()->replace(customer("client"),first.id(),1,"edit",shift,3,"No aplicar").block()).hasMessageContaining("RESERVATION_NOT_EDITABLE");assertThat(state()).isEqualTo(before);
        assertThat(confirm("other","reuse",2).block().body().tableIds()).isEqualTo(first.tableIds());
    }
    @Test void cancelacionYConfiguracionSeSerializanSinCambioParcial(){
        var first=confirm("client","first",2).block().body();
        var results=overlap(cancel(customer("client"),first.id(),1,"cancel"),patch(table,"reduce",new TablePatchRequest(null,2L),1));
        assertThat(results.get(1).isOnError()).isTrue();assertThat(results.get(1).getThrowable().getMessage()).containsAnyOf("REVISION_MISMATCH","DEPENDENCY_UNAVAILABLE");
        assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);
        assertThat(mongo.findById(table,com.brenis.SpringWebFlux.collections.TableCollection.class).block().capacity()).isEqualTo(4);
        patch(table,"reduce-current",new TablePatchRequest(null,2L),2).block();assertThat(revision()).isEqualTo(3);
    }
}
