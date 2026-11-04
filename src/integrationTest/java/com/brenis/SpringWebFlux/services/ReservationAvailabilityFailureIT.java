package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationAvailabilityIntegrationSupport;
import static org.assertj.core.api.Assertions.*;
class ReservationAvailabilityFailureIT extends ReservationAvailabilityIntegrationSupport {
    @org.junit.jupiter.params.ParameterizedTest
    @org.junit.jupiter.params.provider.ValueSource(strings={"missing-shift","foreign-shift","missing-table","foreign-table","bad-time"})
    void legadoSinVinculoNoSeConfundeConLleno(String mode){
        var id=java.util.UUID.randomUUID();var start=clock.instant().plusSeconds(10800);
        var referenceShift=mode.endsWith("shift")?java.util.UUID.randomUUID():shift;
        var referenceTable=mode.endsWith("table")?java.util.UUID.randomUUID():table;
        if(mode.equals("foreign-shift"))mongo.insert(new com.brenis.SpringWebFlux.collections.RestaurantShiftCollection(referenceShift,java.util.UUID.randomUUID(),
            java.time.LocalDateTime.ofInstant(start,java.time.ZoneOffset.UTC).toString(),java.time.LocalDateTime.ofInstant(start.plusSeconds(3600),java.time.ZoneOffset.UTC).toString(),"UTC",start,start.plusSeconds(3600))).block();
        if(mode.equals("foreign-table"))mongo.insert(new com.brenis.SpringWebFlux.collections.TableCollection(referenceTable,java.util.UUID.randomUUID(),"Ajena","ajena",4)).block();
        try{
        var legacy=new org.bson.Document("_id",id).append("restaurantId",restaurant).append("status","CONFIRMED")
            .append("shiftId",referenceShift).append("tableIds",java.util.List.of(referenceTable)).append("zoneId","UTC")
            .append("localStart",java.time.LocalDateTime.ofInstant(start,java.time.ZoneOffset.UTC).toString())
            .append("localEnd",java.time.LocalDateTime.ofInstant(start.plusSeconds(3600),java.time.ZoneOffset.UTC).toString())
            .append("startInstant",java.util.Date.from(start)).append("endInstant",java.util.Date.from(start.plusSeconds(mode.equals("bad-time")?3660:3600)));
        mongo.insert(legacy,"reservations").block();
        var result=availability.list(restaurant,day(),2).block().items().getFirst();
        assertThat(result.availability()).isEqualTo("UNDETERMINED");assertThat(result.reservable()).isFalse();
        assertThat(mongo.findById(id,org.bson.Document.class,"reservations").block()).isEqualTo(legacy);
        assertThat(revision()).isZero();assertThat(receiptCount()).isZero();
        }finally{
            if(mode.equals("foreign-shift"))mongo.remove(org.springframework.data.mongodb.core.query.Query.query(org.springframework.data.mongodb.core.query.Criteria.where("_id").is(referenceShift)),"restaurant_shifts").block();
            if(mode.equals("foreign-table"))mongo.remove(org.springframework.data.mongodb.core.query.Query.query(org.springframework.data.mongodb.core.query.Criteria.where("_id").is(referenceTable)),"restaurant_tables").block();
        }
    }
}
