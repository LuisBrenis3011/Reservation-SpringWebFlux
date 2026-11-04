package com.brenis.SpringWebFlux.services;
import java.util.*;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.springframework.data.mongodb.core.query.*;
import com.brenis.SpringWebFlux.dtos.requests.ManagedReservationRequest;
import com.brenis.SpringWebFlux.support.ReservationReplacementSupport;
import static org.assertj.core.api.Assertions.*;

class ReservationReplaceRollbackIT extends ReservationReplacementSupport {
    @Test void esc0708_destinoOcupadoYDuplicadoConservanTodo(){
        var first=confirm("client","first",3).block().body();UUID target=destination(18000);
        confirm("other","busy",new ManagedReservationRequest(target,3,"")).block();var before=state();
        assertThatThrownBy(()->replace(customer("client"),first.id(),1,"busy",target,3,"").block()).hasMessageContaining("NO_AVAILABILITY");
        assertThat(state()).isEqualTo(before);
        UUID another=destination(25200);confirm("client","duplicate",new ManagedReservationRequest(another,3,"")).block();before=state();
        assertThatThrownBy(()->replace(customer("client"),first.id(),1,"duplicate",another,3,"").block()).hasMessageContaining("DUPLICATE_RESERVATION");
        assertThat(state()).isEqualTo(before);
    }
    @Test void esc0708_u1_otroTurnoDesconocidoYSnapshotDiscrepanteBloqueanInclusoNotas(){
        var first=confirm("client","first",3).block().body();
        UUID legacyId=UUID.randomUUID();
        var raw=new Document("_id",legacyId).append("restaurantId",restaurant).append("status","CONFIRMED")
            .append("shiftId",UUID.randomUUID()).append("tableIds",List.of(table)).append("zoneId","UTC")
            .append("localStart",first.localStart()).append("localEnd",first.localEnd())
            .append("startInstant",Date.from(first.startInstant())).append("endInstant",Date.from(first.endInstant()));
        mongo.insert(raw,"reservations").block();
        try{
            var before=state();
            assertThatThrownBy(()->replace(customer("client"),first.id(),1,"unknown",shift,3,"Notas").block()).hasMessageContaining("LEGACY_RESERVATION_BLOCK");
            assertThat(state()).isEqualTo(before);
            UUID otherShift=destination(18000);
            mongo.updateFirst(byId(legacyId),new Update().set("shiftId",otherShift),"reservations").block();
            before=state();
            assertThatThrownBy(()->replace(customer("client"),first.id(),1,"snapshot",shift,3,"Notas").block()).hasMessageContaining("LEGACY_RESERVATION_BLOCK");
            assertThat(state()).isEqualTo(before);
            mongo.updateFirst(byId(legacyId),new Update().set("shiftId",shift).set("tableIds",List.of(UUID.randomUUID())),"reservations").block();
            before=state();
            assertThatThrownBy(()->replace(customer("client"),first.id(),1,"unknown-table",shift,3,"Notas").block()).hasMessageContaining("LEGACY_RESERVATION_BLOCK");
            assertThat(state()).isEqualTo(before);
            UUID foreignTable=UUID.randomUUID();
            mongo.insert(new com.brenis.SpringWebFlux.collections.TableCollection(foreignTable,UUID.randomUUID(),"Ajena","ajena",4)).block();
            try{
                mongo.updateFirst(byId(legacyId),new Update().set("tableIds",List.of(foreignTable)),"reservations").block();before=state();
                assertThatThrownBy(()->replace(customer("client"),first.id(),1,"foreign-table",shift,3,"Notas").block()).hasMessageContaining("LEGACY_RESERVATION_BLOCK");
                assertThat(state()).isEqualTo(before);
            }finally{mongo.remove(byId(foreignTable),"restaurant_tables").block();}
        }finally{mongo.remove(byId(legacyId),"reservations").block();}
    }
    @Test void esc0702_canceladaLegacyYAjenaNoSeEditan(){
        var first=confirm("client","first",3).block().body();var before=state();
        assertThatThrownBy(()->replace(otherCustomer(),first.id(),1,"foreign",shift,2,"").block()).hasMessageContaining("NOT_FOUND");
        assertThat(state()).isEqualTo(before);
        mongo.updateFirst(byId(first.id()),new Update().set("status","CANCELLED").set("cancelledAt",Date.from(clock.instant())),"reservations").block();before=state();
        assertThatThrownBy(()->replace(customer("client"),first.id(),1,"cancelled",shift,2,"").block()).hasMessageContaining("RESERVATION_NOT_EDITABLE");
        assertThat(state()).isEqualTo(before);
        UUID legacy=UUID.randomUUID();mongo.insert(new Document("_id",legacy).append("restaurantId",restaurant),"reservations").block();
        try{before=state();assertThatThrownBy(()->replace(manager,legacy,1,"legacy",shift,2,"").block()).hasMessageContaining("LEGACY_RESERVATION_READ_ONLY");assertThat(state()).isEqualTo(before);}
        finally{mongo.remove(byId(legacy),"reservations").block();}
    }
    private reactor.core.publisher.Mono<Document> admin(Document command){return mongo.getMongoDatabaseFactory().getMongoDatabase("admin").flatMap(db->reactor.core.publisher.Mono.from(db.runCommand(command)));}
    @Test void falloRealDeEscrituraRevierteReservaRevisionYRecibo(){
        var first=confirm("client","first",3).block().body();var before=state();
        admin(new Document("configureFailPoint","failCommand").append("mode",new Document("times",1))
            .append("data",new Document("failCommands",List.of("insert")).append("errorCode",2))).block();
        try{assertThatThrownBy(()->replace(customer("client"),first.id(),1,"failure",shift,3,"Notas").block()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");}
        finally{admin(new Document("configureFailPoint","failCommand").append("mode","off")).block();}
        assertThat(state()).isEqualTo(before);
        assertThat(replace(customer("client"),first.id(),1,"failure",shift,3,"Notas").block().body().version()).isEqualTo(2);
    }
    @Test void limitesRealesPorActorConservanTodoAlRechazar(){
        var first=confirm("client","first",3).block().body();var instant=clock.instant();
        try{
            clock.advance(java.time.Duration.ofHours(2)); // original a una hora
            var before=state();
            assertThatThrownBy(()->replace(customer("client"),first.id(),1,"late-client",shift,3,"Notas").block()).hasMessageContaining("RESERVATION_WINDOW_CLOSED");
            assertThat(state()).isEqualTo(before);
            assertThat(replace(dual("client"),first.id(),1,"dual-manager",shift,3,"Notas").block().body().version()).isEqualTo(2);
            clock.advance(java.time.Duration.ofHours(1)); // inicio exacto
            before=state();
            assertThatThrownBy(()->replace(manager,first.id(),2,"started",shift,3,"Otra").block()).hasMessageContaining("RESERVATION_WINDOW_CLOSED");
            assertThat(state()).isEqualTo(before);
        }finally{clock.set(instant);}
    }
}
