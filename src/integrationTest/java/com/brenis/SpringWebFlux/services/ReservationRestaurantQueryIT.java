package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationQueryIntegrationSupport;
import com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse;
import static org.assertj.core.api.Assertions.*;
class ReservationRestaurantQueryIT extends ReservationQueryIntegrationSupport {
    @Test void managerLocalYCuentaDualAislados(){
        var own=insertManaged(restaurant,"owner",false);var other=insertManaged(java.util.UUID.randomUUID(),"owner",false);
        var foreign=insertManaged(java.util.UUID.randomUUID(),"foreign",false);
        var before=mongo.find(new org.springframework.data.mongodb.core.query.Query(),org.bson.Document.class,"reservations").collectList().block();
        assertThat(queries.byRestaurant(manager,restaurant,0,20).block().items()).hasSize(1);
        assertThat(queries.managed(dual("owner"),restaurant,own.id()).block().id()).isEqualTo(own.id());
        assertThat(queries.mine(dual("owner"),0,20,null).block().items()).hasSize(2);
        assertThatThrownBy(()->queries.mine(manager,0,20,null).block()).hasMessageContaining("FORBIDDEN");
        assertThatThrownBy(()->queries.byRestaurant(manager,other.restaurantId(),0,20).block()).hasMessageContaining("FORBIDDEN");
        assertThatThrownBy(()->queries.managed(customer("other"),restaurant,own.id()).block()).hasMessageContaining("NOT_FOUND");
        assertThat(mongo.find(new org.springframework.data.mongodb.core.query.Query(),org.bson.Document.class,"reservations").collectList().block()).isEqualTo(before);
        assertThat(receiptCount()).isZero();assertThat(revision()).isZero();
    }
}
