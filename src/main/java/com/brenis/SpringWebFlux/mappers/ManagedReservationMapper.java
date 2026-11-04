package com.brenis.SpringWebFlux.mappers;
import org.springframework.stereotype.Component;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection;
import com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse;
import com.brenis.SpringWebFlux.validators.ReservationIntegrityValidator;
@Component
public class ManagedReservationMapper {
    private final ReservationIntegrityValidator integrity;
    public ManagedReservationMapper(ReservationIntegrityValidator integrity){this.integrity=integrity;}
    public ManagedReservationResponse response(ManagedReservationCollection r){
        integrity.validate(r);
        return new ManagedReservationResponse("MANAGED",r.id(),r.restaurantId(),new ManagedReservationResponse.Owner(r.customerIssuer(),r.customerSubject()),
            r.shiftId(),r.partySize(),r.notes(),r.status().name(),r.version(),java.util.List.copyOf(r.tableIds()),r.combinationId(),r.assignedCapacity(),r.localStart(),r.localEnd(),r.zoneId(),r.startInstant(),r.endInstant(),r.createdAt(),r.updatedAt(),r.cancelledAt());
    }
}
