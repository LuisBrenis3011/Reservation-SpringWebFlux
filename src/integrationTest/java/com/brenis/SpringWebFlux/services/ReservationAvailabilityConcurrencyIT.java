package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationAvailabilityIntegrationSupport;
import static org.assertj.core.api.Assertions.*;
class ReservationAvailabilityConcurrencyIT extends ReservationAvailabilityIntegrationSupport {
    private java.util.Map<String,Object> snapshot(){
        var data=new java.util.TreeMap<String,Object>();
        for(String name:java.util.List.of("restaurants","reservations","restaurant_operations","operation_receipts","restaurant_tables","table_combinations","restaurant_shifts","restaurant_time_zones","reservation_policy")){
            data.put(name+":documents",mongo.find(new org.springframework.data.mongodb.core.query.Query(),org.bson.Document.class,name).collectList().block());
            if(Boolean.TRUE.equals(mongo.collectionExists(name).block()))data.put(name+":indexes",mongo.indexOps(name).getIndexInfo().map(Object::toString).collectList().block());
        }
        return data;
    }
    @Test void consultaNoApartaYConfirmacionPosteriorReevalua(){
        var before=snapshot();
        assertThat(availability.list(restaurant,day(),3).block().items().getFirst().availability()).isEqualTo("AVAILABLE");
        assertThat(snapshot()).isEqualTo(before);
        assertThat(availability.list(restaurant,day(),3).block().items().getFirst().availability()).isEqualTo("AVAILABLE");
        assertThat(revision()).isZero();assertThat(receiptCount()).isZero();
        assertThat(snapshot()).isEqualTo(before);
        assertThat(mongo.exists(org.springframework.data.mongodb.core.query.Query.query(org.springframework.data.mongodb.core.query.Criteria.where("_id").is(restaurant)),"restaurant_operations").block()).isFalse();
        confirm("other","one",3).block();
        assertThatThrownBy(()->confirm("client","two",3).block()).hasMessageContaining("NO_AVAILABILITY");
        assertThat(availability.list(restaurant,day(),3).block().items().getFirst().availability()).isEqualTo("UNAVAILABLE");
        assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
    }
}
