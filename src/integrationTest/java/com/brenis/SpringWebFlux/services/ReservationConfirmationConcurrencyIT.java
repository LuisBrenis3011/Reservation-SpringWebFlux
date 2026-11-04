package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationConfirmationSupport;
import static org.assertj.core.api.Assertions.*;
class ReservationConfirmationConcurrencyIT extends ReservationConfirmationSupport {
    private reactor.core.publisher.Mono<org.bson.Document> admin(org.bson.Document command){return mongo.getMongoDatabaseFactory().getMongoDatabase("admin").flatMap(db->reactor.core.publisher.Mono.from(db.runCommand(command)));}
    @Test void commitInciertoRecuperableNoDuplicaReserva(){
        coordinator.readSnapshot(restaurant,ctx->reactor.core.publisher.Mono.just(true)).block();
        admin(new org.bson.Document("configureFailPoint","failCommand").append("mode",new org.bson.Document("times",1))
            .append("data",new org.bson.Document("failCommands",java.util.List.of("commitTransaction")).append("errorCode",1)
                .append("errorLabels",java.util.List.of("UnknownTransactionCommitResult")))).block();
        try{
            var result=confirm("one","uncertain",3).block();assertThat(confirm("one","uncertain",3).block()).isEqualTo(result);
            assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
        }finally{admin(new org.bson.Document("configureFailPoint","failCommand").append("mode","off")).block();}
    }
    @Test void ultimaMesaConcurrenteNuncaDuplicaAsignacion(){
        var signals=reactor.core.publisher.Flux.merge(confirm("one","a",3).materialize(),confirm("two","b",3).materialize()).collectList().block();
        assertThat(signals.stream().filter(reactor.core.publisher.Signal::hasValue).count()).isEqualTo(1);
        assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
    }
    @Test void duplicadoDeTitularConservaReservaOriginal(){
        confirm("client","one",2).block();
        assertThatThrownBy(()->confirm("client","two",2).block()).hasMessageContaining("DUPLICATE_RESERVATION");
        assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
    }
    @Test void fixtureCanceladaLiberaIndiceSinReactivarNiBorrarHistoria(){
        var original=confirm("client","one",2).block().body();
        // Simula una fixture terminal; no implementa ni prueba el comando de SPEC-008.
        mongo.updateFirst(org.springframework.data.mongodb.core.query.Query.query(org.springframework.data.mongodb.core.query.Criteria.where("_id").is(original.id())),
            new org.springframework.data.mongodb.core.query.Update().set("status","CANCELLED").set("version",2L)
                .set("cancelledAt",java.util.Date.from(clock.instant())),"reservations").block();
        var next=confirm("client","two",2).block().body();assertThat(next.id()).isNotEqualTo(original.id());
        assertThat(mongo.findById(original.id(),org.bson.Document.class,"reservations").block().getString("status")).isEqualTo("CANCELLED");
        assertThat(receiptCount()).isEqualTo(2);
    }
    @Test void legadoDeOtroTurnoNoVerificableBloqueaSinEfectos(){
        var id=java.util.UUID.randomUUID();
        var row=new org.bson.Document("_id",id).append("restaurantId",restaurant).append("status","CONFIRMED")
            .append("shiftId",java.util.UUID.randomUUID()).append("tableIds",java.util.List.of(table)).append("zoneId","UTC")
            .append("localStart","2026-11-01T13:00").append("localEnd","2026-11-01T14:00")
            .append("startInstant",java.util.Date.from(clock.instant().plusSeconds(10800)))
            .append("endInstant",java.util.Date.from(clock.instant().plusSeconds(14400)));
        mongo.insert(row,"reservations").block();
        assertThatThrownBy(()->confirm("client","one",2).block()).hasMessageContaining("LEGACY_RESERVATION_BLOCK");
        assertThat(revision()).isZero();assertThat(receiptCount()).isZero();
        assertThat(mongo.findById(id,org.bson.Document.class,"reservations").block()).isEqualTo(row);
    }
}
