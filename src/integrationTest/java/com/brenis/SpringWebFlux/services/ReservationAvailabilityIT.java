package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationAvailabilityIntegrationSupport;
import static org.assertj.core.api.Assertions.*;
class ReservationAvailabilityIT extends ReservationAvailabilityIntegrationSupport {
    @Test void limitesEnRespuestaYFechaLocalLima(){
        var now=clock.instant();var exactNow=java.util.UUID.randomUUID();var twoHours=java.util.UUID.randomUUID();
        saveUtc(exactNow,now);saveUtc(twoHours,now.plusSeconds(7200));
        var items=availability.list(restaurant,day(),2).block().items();
        assertThat(items).noneMatch(i->i.shiftId().equals(exactNow));
        assertThat(items.stream().filter(i->i.shiftId().equals(twoHours)).findFirst().orElseThrow().bookingWindow()).isEqualTo("OPEN");
        var limit=now.plus(java.time.Duration.ofDays(90));var upper=java.util.UUID.randomUUID();var later=java.util.UUID.randomUUID();
        saveUtc(upper,limit);saveUtc(later,limit.plusSeconds(1));
        var future=availability.list(restaurant,java.time.LocalDate.ofInstant(limit,java.time.ZoneOffset.UTC),2).block().items();
        assertThat(future.stream().filter(i->i.shiftId().equals(upper)).findFirst().orElseThrow().bookingWindow()).isEqualTo("OPEN");
        var outside=future.stream().filter(i->i.shiftId().equals(later)).findFirst().orElseThrow();
        assertThat(outside.bookingWindow()).isEqualTo("TOO_FAR");assertThat(outside.availability()).isEqualTo("AVAILABLE");assertThat(outside.reservable()).isFalse();
        var date=day().plusDays(3);var start=date.atTime(22,0);var end=date.plusDays(1).atTime(2,0);var zone=java.time.ZoneId.of("America/Lima");var id=java.util.UUID.randomUUID();
        mongo.insert(new com.brenis.SpringWebFlux.collections.RestaurantShiftCollection(id,restaurant,start.toString(),end.toString(),zone.getId(),start.atZone(zone).toInstant(),end.atZone(zone).toInstant())).block();
        assertThat(availability.list(restaurant,date,2).block().items()).extracting(com.brenis.SpringWebFlux.dtos.responses.ReservationAvailabilityResponse.Item::shiftId).contains(id);
        assertThat(availability.list(restaurant,date.plusDays(1),2).block().items()).extracting(com.brenis.SpringWebFlux.dtos.responses.ReservationAvailabilityResponse.Item::shiftId).doesNotContain(id);
    }
    private void saveUtc(java.util.UUID id,java.time.Instant start){
        var end=start.plusSeconds(1800);
        mongo.insert(new com.brenis.SpringWebFlux.collections.RestaurantShiftCollection(id,restaurant,
            java.time.LocalDateTime.ofInstant(start,java.time.ZoneOffset.UTC).toString(),java.time.LocalDateTime.ofInstant(end,java.time.ZoneOffset.UTC).toString(),"UTC",start,end)).block();
    }
    @Test void fechaLocalCruceDeMedianocheYTurnosFueraDeVentana(){
        var next=day().plusDays(1);var start=next.atTime(23,30);var end=next.plusDays(1).atTime(1,0);
        var id=java.util.UUID.randomUUID();
        mongo.insert(new com.brenis.SpringWebFlux.collections.RestaurantShiftCollection(id,restaurant,start.toString(),end.toString(),"UTC",start.toInstant(java.time.ZoneOffset.UTC),end.toInstant(java.time.ZoneOffset.UTC))).block();
        assertThat(availability.list(restaurant,next,2).block().items()).extracting(com.brenis.SpringWebFlux.dtos.responses.ReservationAvailabilityResponse.Item::shiftId).containsExactly(id);
        assertThat(availability.list(restaurant,next.plusDays(1),2).block().items()).isEmpty();
        var early=java.util.UUID.randomUUID();var now=clock.instant();
        mongo.insert(new com.brenis.SpringWebFlux.collections.RestaurantShiftCollection(early,restaurant,
            java.time.LocalDateTime.ofInstant(now.plusSeconds(3600),java.time.ZoneOffset.UTC).toString(),java.time.LocalDateTime.ofInstant(now.plusSeconds(5400),java.time.ZoneOffset.UTC).toString(),"UTC",now.plusSeconds(3600),now.plusSeconds(5400))).block();
        var item=availability.list(restaurant,day(),2).block().items().stream().filter(i->i.shiftId().equals(early)).findFirst().orElseThrow();
        assertThat(item.bookingWindow()).isEqualTo("TOO_SOON");assertThat(item.availability()).isEqualTo("AVAILABLE");assertThat(item.reservable()).isFalse();
    }
    @Test void mesaLibreYCombinacionCompartenOcupacion(){
        var second=java.util.UUID.randomUUID();
        mongo.insert(new com.brenis.SpringWebFlux.collections.TableCollection(second,restaurant,"Otra","otra",4)).block();
        mongo.insert(new com.brenis.SpringWebFlux.collections.TableCombinationCollection(java.util.UUID.randomUUID(),restaurant,java.util.List.of(table,second),"fixture")).block();
        assertThat(availability.list(restaurant,day(),7).block().items().getFirst().availability()).isEqualTo("AVAILABLE");
        confirm("client","one",2).block();
        assertThat(availability.list(restaurant,day(),7).block().items().getFirst().availability()).isEqualTo("UNAVAILABLE");
        assertThat(availability.list(restaurant,day(),2).block().items().getFirst().availability()).isEqualTo("AVAILABLE");
    }
}
