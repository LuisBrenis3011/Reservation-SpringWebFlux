package com.brenis.SpringWebFlux.validators;

import com.brenis.SpringWebFlux.collections.ManagedReservationCollection;
import com.brenis.SpringWebFlux.enums.ManagedReservationStatus;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import java.time.*;
import java.util.*;
import org.springframework.stereotype.Component;

@Component
public class ReservationIntegrityValidator {
    public void validate(ManagedReservationCollection r) {
        try {
            if (r == null || r.schemaVersion()!=2 || r.id()==null || r.restaurantId()==null
                    || r.shiftId()==null || r.customerIssuer()==null || r.customerIssuer().isBlank()
                    || r.customerSubject()==null || r.customerSubject().isBlank() || r.notes()==null
                    || r.status()==null || r.version()<1 || r.partySize()<1 || r.partySize()>20
                    || r.createdAt()==null || r.updatedAt()==null || r.tableIds()==null
                    || r.tableIds().isEmpty() || r.tableSnapshots()==null) throw new IllegalArgumentException();
            var ids=new HashSet<>(r.tableIds());
            if(ids.contains(null) || ids.size()!=r.tableIds().size()) throw new IllegalArgumentException();
            if(!r.tableIds().equals(r.tableIds().stream().sorted(Comparator.comparing(UUID::toString)).toList()))throw new IllegalArgumentException();
            var snapshotIds=new HashSet<UUID>(); long capacity=0;
            for(var t:r.tableSnapshots()) {
                if(t==null || t.id()==null || t.capacity()<=0 || !snapshotIds.add(t.id())) throw new IllegalArgumentException();
                capacity=Math.addExact(capacity,t.capacity());
            }
            if(!ids.equals(snapshotIds) || capacity!=r.assignedCapacity() || capacity<r.partySize()) throw new IllegalArgumentException();
            var zone=ZoneId.of(r.zoneId());
            if(!java.net.URI.create(r.customerIssuer()).isAbsolute())throw new IllegalArgumentException();
            var start=LocalDateTime.parse(r.localStart()); var end=LocalDateTime.parse(r.localEnd());
            var so=zone.getRules().getValidOffsets(start); var eo=zone.getRules().getValidOffsets(end);
            if(so.size()!=1 || eo.size()!=1 || !start.toInstant(so.getFirst()).equals(r.startInstant())
                    || !end.toInstant(eo.getFirst()).equals(r.endInstant()) || !r.endInstant().isAfter(r.startInstant())) throw new IllegalArgumentException();
            if((r.status()==ManagedReservationStatus.CANCELLED)!=(r.cancelledAt()!=null)) throw new IllegalArgumentException();
        } catch(RuntimeException e) {
            throw new AvailabilityException("RESERVATION_UNVERIFIABLE","No se pudo verificar la reserva",e);
        }
    }
}
