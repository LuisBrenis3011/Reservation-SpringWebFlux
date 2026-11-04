package com.brenis.SpringWebFlux.mappers;
import com.brenis.SpringWebFlux.collections.RestaurantShiftCollection;
import com.brenis.SpringWebFlux.dtos.responses.RestaurantShiftResponse;
import com.brenis.SpringWebFlux.dtos.responses.RestaurantShiftListResponse;
import java.util.UUID;
import org.springframework.stereotype.Component;
import com.brenis.SpringWebFlux.dtos.responses.RestaurantTimeZoneResponse;
@Component
public class RestaurantShiftMapper {
    public RestaurantShiftResponse shift(RestaurantShiftCollection row,long revision){
        if(row.id()==null || row.restaurantId()==null || row.localStart()==null || row.localEnd()==null || row.zoneId()==null || row.startInstant()==null || row.endInstant()==null)
            throw new com.brenis.SpringWebFlux.exceptions.AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Turno persistido incompleto");
        return new RestaurantShiftResponse(row.id(),row.restaurantId(),row.localStart(),row.localEnd(),row.zoneId(),row.startInstant(),row.endInstant(),revision);
    }
    public RestaurantShiftListResponse list(java.util.List<RestaurantShiftCollection> rows,long revision){
        return new RestaurantShiftListResponse(rows.stream().map(row -> shift(row,revision))
            .sorted(java.util.Comparator.comparing(RestaurantShiftResponse::startInstant).thenComparing(row -> row.id().toString())).toList(),revision);
    }
    public RestaurantTimeZoneResponse zone(UUID owner,String zoneId,long revision){return new RestaurantTimeZoneResponse(owner,zoneId,revision);}
}
