package com.brenis.SpringWebFlux.services;
import java.util.*;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.data.mongodb.core.query.Update;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.support.ReservationCancellationSupport;
import com.brenis.SpringWebFlux.repositories.*;
import com.brenis.SpringWebFlux.services.impls.ReservationMutationGuard;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class ReservationCancellationFailureIT extends ReservationCancellationSupport {
    @MockitoSpyBean ReservationOccupancyReader occupancy;
    @MockitoSpyBean LegacyReservationCommitmentAdapter legacy;
    @MockitoSpyBean ReservationMutationGuard guard;
    @Test void esc0811_q4_noInvocaNingunLectorNiGuardGlobalCaidos(){
        var first=confirm("client","first",2).block().body();
        doReturn(Mono.error(new IllegalStateException("lector global caido"))).when(occupancy).read(any(UUID.class),any(UUID.class),nullable(UUID.class),any(java.time.Instant.class));
        doReturn(Mono.error(new IllegalStateException("legado caido"))).when(legacy).read(any(UUID.class),any(java.time.Instant.class));
        doReturn(Mono.error(new IllegalStateException("guard caido"))).when(guard).check(any(),any(),nullable(UUID.class));
        clearInvocations(occupancy,legacy,guard);
        try{
            assertThat(cancel(customer("client"),first.id(),1,"cancel").block().body().status()).isEqualTo("CANCELLED");
            verifyNoInteractions(occupancy,legacy,guard);assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);
        }finally{reset(occupancy,legacy,guard);}
    }
    @Test void esc0811_legadoAjenoNoImpideCancelarNiPierdeSuBloqueo(){
        var first=confirm("client","first",2).block().body();UUID legacyId=UUID.randomUUID();
        mongo.insert(new Document("_id",legacyId).append("restaurantId",restaurant).append("status","PENDING"),"reservations").block();
        var originalLegacy=raw(legacyId);
        try{
            assertThat(cancel(customer("client"),first.id(),1,"cancel").block().body().status()).isEqualTo("CANCELLED");
            assertThat(raw(legacyId)).isEqualTo(originalLegacy);var before=state();
            assertThatThrownBy(()->confirm("new","blocked",2).block()).hasMessageContaining("LEGACY_RESERVATION_BLOCK");assertThat(state()).isEqualTo(before);
        }finally{mongo.remove(byId(legacyId),"reservations").block();}
    }
    @Test void esc0812_snapshotPropioCorruptoNoSeLiberaNiAunqueYaEsteCancelada(){
        var first=confirm("client","first",2).block().body();
        mongo.updateFirst(byId(first.id()),new Update().set("assignedCapacity",99L),"reservations").block();var before=state();
        assertThatThrownBy(()->cancel(customer("client"),first.id(),1,"bad").block()).hasMessageContaining("RESERVATION_UNVERIFIABLE");assertThat(state()).isEqualTo(before);
        mongo.updateFirst(byId(first.id()),new Update().set("assignedCapacity",4L),"reservations").block();
        cancel(customer("client"),first.id(),1,"cancel").block();
        mongo.updateFirst(byId(first.id()),new Update().set("tableIds",List.of()),"reservations").block();before=state();
        assertThatThrownBy(()->cancel(customer("client"),first.id(),0,"bad-cancelled").block()).hasMessageContaining("RESERVATION_UNVERIFIABLE");assertThat(state()).isEqualTo(before);
    }
    @Test void esc0810_falloDeLecturaPropiaYFalloDeReciboConservanTodo(){
        var first=confirm("client","first",2).block().body();
        for(String command:List.of("find","insert")){
            var before=state();
            admin(new Document("configureFailPoint","failCommand").append("mode",new Document("times",1))
                .append("data",new Document("failCommands",List.of(command)).append("errorCode",2))).block();
            try{assertThatThrownBy(()->cancel(customer("client"),first.id(),1,"failure").block()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");}
            finally{admin(new Document("configureFailPoint","failCommand").append("mode","off")).block();}
            assertThat(state()).isEqualTo(before);
        }
        assertThat(cancel(customer("client"),first.id(),1,"failure").block().body().status()).isEqualTo("CANCELLED");
    }
    @Test void esc0810_commitInciertoNoRepiteTransicionYNoopConservaVersion(){
        var first=confirm("client","first",2).block().body();
        for(boolean noop:List.of(false,true)){
            admin(new Document("configureFailPoint","failCommand").append("mode",new Document("times",1))
                .append("data",new Document("failCommands",List.of("commitTransaction")).append("errorCode",1)
                    .append("errorLabels",List.of("UnknownTransactionCommitResult")))).block();
            try{
                var result=cancel(customer("client"),first.id(),noop?0:1,noop?"noop":"cancel").block();
                assertThat(cancel(customer("client"),first.id(),noop?0:1,noop?"noop":"cancel").block()).isEqualTo(result);
                assertThat(result.body().version()).isEqualTo(2);assertThat(revision()).isEqualTo(2);
                assertThat(receiptCount()).isEqualTo(noop?3:2);
            }finally{admin(new Document("configureFailPoint","failCommand").append("mode","off")).block();}
        }
    }
}
