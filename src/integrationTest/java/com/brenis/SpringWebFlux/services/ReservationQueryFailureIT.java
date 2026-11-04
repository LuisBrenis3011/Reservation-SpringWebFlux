package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationQueryIntegrationSupport;
import static org.assertj.core.api.Assertions.*;
class ReservationQueryFailureIT extends ReservationQueryIntegrationSupport {
    private reactor.core.publisher.Mono<org.bson.Document> admin(org.bson.Document command){return mongo.getMongoDatabaseFactory().getMongoDatabase("admin").flatMap(db->reactor.core.publisher.Mono.from(db.runCommand(command)));}
    @Test void falloRealDeLecturaNoSeConvierteEnListaVacia(){
        admin(new org.bson.Document("configureFailPoint","failCommand").append("mode",new org.bson.Document("times",1))
            .append("data",new org.bson.Document("failCommands",java.util.List.of("find")).append("errorCode",1))).block();
        try{assertThatThrownBy(()->queries.mine(customer("sin-reservas"),0,20,null).block()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");}
        finally{admin(new org.bson.Document("configureFailPoint","failCommand").append("mode","off")).block();}
        assertThat(receiptCount()).isZero();assertThat(revision()).isZero();
    }
    @Test void sinReservasListaVaciaSinMetadataNueva(){
        var before=receiptCount();
        assertThat(queries.mine(customer("sin-reservas"),0,20,null).block().items()).isEmpty();
        assertThat(receiptCount()).isEqualTo(before);
        assertThat(mongo.exists(org.springframework.data.mongodb.core.query.Query.query(org.springframework.data.mongodb.core.query.Criteria.where("_id").is(restaurant)),"restaurant_operations").block()).isFalse();
    }
    @Test void v2InvalidaNoSeProyectaComoLegado(){
        var row=insertManaged(restaurant,"client",false);
        mongo.updateFirst(org.springframework.data.mongodb.core.query.Query.query(org.springframework.data.mongodb.core.query.Criteria.where("_id").is(row.id())),
            new org.springframework.data.mongodb.core.query.Update().set("assignedCapacity",0),"reservations").block();
        assertThatThrownBy(()->queries.byRestaurant(manager,restaurant,0,20).block()).hasMessageContaining("RESERVATION_UNVERIFIABLE");
    }
    @Test void esquemaDesconocidoNoSeDisfrazaDeLegado(){
        var id=new org.bson.types.ObjectId();ownIds.add(id);
        mongo.insert(new org.bson.Document("_id",id).append("restaurantId",restaurant.toString()).append("schemaVersion","2"),"reservations").block();
        assertThatThrownBy(()->queries.byRestaurant(manager,restaurant,0,20).block()).hasMessageContaining("RESERVATION_UNVERIFIABLE");
    }
}
