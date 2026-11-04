package com.brenis.SpringWebFlux.services;
import java.util.*;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import com.brenis.SpringWebFlux.support.ManagedReservationIntegrationSupport;
import com.brenis.SpringWebFlux.repositories.ReservationOccupancyReader;
import com.brenis.SpringWebFlux.services.impls.LegacyReservationWriteBarrier;
import com.brenis.SpringWebFlux.collections.ReservationPolicyCollection;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.data.mongodb.core.query.Criteria.where;
import static org.springframework.data.mongodb.core.query.Query.query;

class ReservationInfrastructureIT extends ManagedReservationIntegrationSupport {
    @Autowired com.mongodb.reactivestreams.client.MongoClient fixtureClient;
    @Test void colisionDurantePreparacionNoBorraDocumentos(){
        // Base exclusiva dentro del mismo contenedor efímero, nunca el Mongo local.
        var isolated=new org.springframework.data.mongodb.core.ReactiveMongoTemplate(fixtureClient,"rsv_collision_"+UUID.randomUUID().toString().replace("-",""));
        UUID first=UUID.randomUUID(),second=UUID.randomUUID(),shift=UUID.randomUUID(),table=UUID.randomUUID();
        try{
            isolated.insert(active(first,shift,"first",List.of(table)),"reservations").block();
            isolated.insert(active(second,shift,"second",List.of(table)),"reservations").block();
            var before=isolated.find(new org.springframework.data.mongodb.core.query.Query(),Document.class,"reservations").collectList().block();
            assertThatThrownBy(()->new com.brenis.SpringWebFlux.configs.ReservationIndexesContributor(isolated).prepare().block()).isInstanceOf(org.springframework.dao.DataAccessException.class);
            assertThat(isolated.find(new org.springframework.data.mongodb.core.query.Query(),Document.class,"reservations").collectList().block()).containsExactlyInAnyOrderElementsOf(before);
        }finally{isolated.remove(query(where("_id").in(first,second)),"reservations").block();}
    }
    @Autowired com.brenis.SpringWebFlux.configs.AvailabilityInfrastructureInitializer initializer;
    @Autowired com.brenis.SpringWebFlux.configs.AvailabilityProperties properties;
    @Test void huerfanaSoloPermiteArranqueConCorteVerificadoYConservaBloqueo(){
        UUID id=UUID.randomUUID();boolean previous=properties.isEnabled();String issuer=properties.getIssuerUri(),jwk=properties.getJwkSetUri();
        mongo.insert(new Document("_id",id).append("status","PENDING"),"reservations").block();
        try{
            properties.setEnabled(true);properties.setIssuerUri("https://issuer.example.test");properties.setJwkSetUri("https://issuer.example.test/certs");
            assertThatThrownBy(()->initializer.prepare().block()).hasMessageContaining("huérfanas");
            mongo.insert(new ReservationPolicyCollection(ReservationPolicyCollection.ID,true,clock.instant())).block();
            assertThatCode(()->initializer.prepare().block()).doesNotThrowAnyException();
            assertThat(occupancy.read(restaurant,UUID.randomUUID(),null,clock.instant()).block().blocked()).isTrue();
        }finally{
            properties.setEnabled(previous);properties.setIssuerUri(issuer);properties.setJwkSetUri(jwk);
            mongo.remove(query(where("_id").is(id)),"reservations").block();
            mongo.remove(query(where("_id").is(ReservationPolicyCollection.ID)),"reservation_policy").block();
        }
    }
    @Test void politicaInvalidaNoSeInterpretaComoAusente(){
        mongo.insert(new Document("_id",ReservationPolicyCollection.ID).append("legacyWritesRetired",false),"reservation_policy").block();
        try{assertThatThrownBy(()->barrier.check().block()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");}
        finally{mongo.remove(query(where("_id").is(ReservationPolicyCollection.ID)),"reservation_policy").block();}
    }
    @Autowired ReservationOccupancyReader occupancy;
    @Autowired LegacyReservationWriteBarrier barrier;
    @Autowired com.brenis.SpringWebFlux.repositories.LegacyReservationCommitmentAdapter commitments;
    @org.junit.jupiter.params.ParameterizedTest
    @org.junit.jupiter.params.provider.ValueSource(strings={"valid","other-valid-shift","missing-table","foreign-table","foreign-shift","bad-time"})
    void vinculosDeLegadoSeCompruebanAntesDeFiltrar(String mode){
        UUID id=UUID.randomUUID(),table=UUID.randomUUID(),shift=UUID.randomUUID();
        var start=clock.instant().plusSeconds(10800);var end=start.plusSeconds(3600);
        String localStart=java.time.LocalDateTime.ofInstant(start,java.time.ZoneOffset.UTC).toString(),localEnd=java.time.LocalDateTime.ofInstant(end,java.time.ZoneOffset.UTC).toString();
        var raw=new Document("_id",id).append("restaurantId",restaurant).append("status","CONFIRMED").append("shiftId",shift)
            .append("tableIds",List.of(table)).append("zoneId","UTC").append("localStart",localStart).append("localEnd",localEnd)
            .append("startInstant",Date.from(start)).append("endInstant",Date.from(end));
        try{
            mongo.save(new com.brenis.SpringWebFlux.collections.RestaurantShiftCollection(shift,mode.equals("foreign-shift")?UUID.randomUUID():restaurant,
                localStart,localEnd,"UTC",start,mode.equals("bad-time")?end.plusSeconds(60):end)).block();
            if(!mode.equals("missing-table"))mongo.save(new com.brenis.SpringWebFlux.collections.TableCollection(table,
                mode.equals("foreign-table")?UUID.randomUUID():restaurant,"fixture","fixture",4)).block();
            mongo.insert(raw,"reservations").block();
            UUID target=mode.equals("other-valid-shift")?UUID.randomUUID():shift;
            var result=occupancy.read(restaurant,target,null,clock.instant()).block();
            boolean valid=mode.equals("valid")||mode.equals("other-valid-shift");
            assertThat(result.blocked()).isEqualTo(!valid);
            assertThat(result.tableIds()).isEqualTo(mode.equals("valid")?Set.of(table):Set.of());
            if(mode.equals("valid")){
                var protectedIds=commitments.read(restaurant,clock.instant()).block();
                assertThat(protectedIds.protectedTableIds()).contains(table);assertThat(protectedIds.protectedShiftIds()).contains(shift);
            }
        }finally{
            mongo.remove(query(where("_id").is(id)),"reservations").block();
            mongo.remove(query(where("_id").is(shift)),"restaurant_shifts").block();
            mongo.remove(query(where("_id").is(table)),"restaurant_tables").block();
        }
    }
    @Test void legadoCompletoConTurnoDesconocidoBloqueaAntesDeFiltrar(){
        UUID id=UUID.randomUUID();var start=clock.instant().plusSeconds(10800);var end=start.plusSeconds(3600);
        var raw=new Document("_id",id).append("restaurantId",restaurant).append("shiftId",UUID.randomUUID())
            .append("tableIds",List.of(UUID.randomUUID())).append("status","CONFIRMED").append("zoneId","UTC")
            .append("localStart",java.time.LocalDateTime.ofInstant(start,java.time.ZoneOffset.UTC).toString())
            .append("localEnd",java.time.LocalDateTime.ofInstant(end,java.time.ZoneOffset.UTC).toString())
            .append("startInstant",Date.from(start)).append("endInstant",Date.from(end));
        mongo.insert(raw,"reservations").block();
        Document before=mongo.findById(id,Document.class,"reservations").block();
        try{
            assertThat(occupancy.read(restaurant,UUID.randomUUID(),null,clock.instant()).block().blocked()).isTrue();
            assertThat(mongo.findById(id,Document.class,"reservations").block()).isEqualTo(before);
        }finally{mongo.remove(query(where("_id").is(id)),"reservations").block();}
    }
    @Test void politicaActivaRetiraEscriturasYSinPoliticaConservaModoPrevio(){
        assertThat(barrier.retired().block()).isFalse();
        var policy=new ReservationPolicyCollection(ReservationPolicyCollection.ID,true,clock.instant());
        mongo.insert(policy).block();
        try{
            assertThat(barrier.retired().block()).isTrue();
            assertThatThrownBy(()->barrier.check().block()).hasMessageContaining("LEGACY_WRITES_RETIRED");
        }finally{mongo.remove(query(where("_id").is(ReservationPolicyCollection.ID)),"reservation_policy").block();}
    }
    @Test void indiceMultikeyRechazaAFrenteACombinacionAB(){
        UUID a=UUID.randomUUID(),b=UUID.randomUUID(),shift=UUID.randomUUID(),id1=UUID.randomUUID(),id2=UUID.randomUUID();
        Document first=active(id1,shift,"one",List.of(a));Document second=active(id2,shift,"two",List.of(a,b));
        try{
            mongo.insert(first,"reservations").block();
            assertThatThrownBy(()->mongo.insert(second,"reservations").block()).isInstanceOf(org.springframework.dao.DuplicateKeyException.class);
            assertThat(mongo.count(query(where("_id").is(id2)),"reservations").block()).isZero();
        }finally{mongo.remove(query(where("_id").in(id1,id2)),"reservations").block();}
    }
    @Test void indiceDeTitularSeLiberaAlCancelarSinBorrarHistoria(){
        UUID shift=UUID.randomUUID(),id1=UUID.randomUUID(),id2=UUID.randomUUID();
        try{
            mongo.insert(active(id1,shift,"same",List.of(UUID.randomUUID())),"reservations").block();
            assertThatThrownBy(()->mongo.insert(active(id2,shift,"same",List.of(UUID.randomUUID())),"reservations").block()).isInstanceOf(org.springframework.dao.DuplicateKeyException.class);
            mongo.updateFirst(query(where("_id").is(id1)),new org.springframework.data.mongodb.core.query.Update().set("status","CANCELLED"),"reservations").block();
            mongo.insert(active(id2,shift,"same",List.of(UUID.randomUUID())),"reservations").block();
            assertThat(mongo.findById(id1,Document.class,"reservations").block().getString("status")).isEqualTo("CANCELLED");
        }finally{mongo.remove(query(where("_id").in(id1,id2)),"reservations").block();}
    }
    private Document active(UUID id,UUID shift,String customer,List<UUID> tables){
        return new Document("_id",id).append("schemaVersion",2).append("restaurantId",restaurant).append("shiftId",shift)
            .append("status","CONFIRMED").append("customerIssuer","issuer").append("customerSubject",customer).append("tableIds",tables);
    }
}
