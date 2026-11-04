package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationQueryIntegrationSupport;
import com.brenis.SpringWebFlux.dtos.responses.LegacyReservationResponse;
import static org.assertj.core.api.Assertions.*;
class ReservationLegacyQueryIT extends ReservationQueryIntegrationSupport {
    @Test void adaptadorAntiguoAceptaUuidCadenaYRechazaLocalAjeno(){
        var id=java.util.UUID.randomUUID();var row=new org.bson.Document("_id",id.toString()).append("restaurantId",restaurant.toString()).append("customerName","Legado");
        mongo.insert(row,"reservations").block();ownIds.add(id.toString());
        assertThat(queries.oldById(manager,id).block()).isInstanceOf(LegacyReservationResponse.class);
        assertThatThrownBy(()->queries.oldById(customer("client"),id).block()).hasMessageContaining("FORBIDDEN");
    }
    @Test void adaptadorAntiguoLeeGestionadaBsonSinUsarDtoLegado(){
        var row=insertManaged(restaurant,"owner",false);
        assertThat(queries.oldById(manager,row.id()).block()).isInstanceOf(com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse.class);
        var other=insertManaged(java.util.UUID.randomUUID(),"owner",false);
        assertThatThrownBy(()->queries.oldById(manager,other.id()).block()).hasMessageContaining("NOT_FOUND");
    }
    @Test void legadoSoloParaManagerYHuerfanoNoSeExpone(){
        var row=insertLegacy(restaurant);String ref=legacyQueries.reference(row.get("_id"));
        var result=queries.legacy(manager,restaurant,ref).block();assertThat(result.kind()).isEqualTo("LEGACY");
        assertThat(result.toString()).doesNotContain("privado@example.test","no-autenticado");
        assertThatThrownBy(()->queries.legacy(customer("owner"),restaurant,ref).block()).hasMessageContaining("FORBIDDEN");
        var orphan=new org.bson.Document("_id",new org.bson.types.ObjectId()).append("customerName","Sin local");
        mongo.insert(orphan,"reservations").block();ownIds.add(orphan.get("_id"));
        assertThatThrownBy(()->queries.legacy(manager,restaurant,legacyQueries.reference(orphan.get("_id"))).block()).hasMessageContaining("NOT_FOUND");
        assertThat(queries.byRestaurant(manager,restaurant,0,20).block().items()).hasSize(1);
        assertThat(mongo.findById(orphan.get("_id"),org.bson.Document.class,"reservations").block()).isNotNull();
    }
}
