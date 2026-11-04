package com.brenis.SpringWebFlux.collections;

import com.brenis.SpringWebFlux.enums.ManagedReservationStatus;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

@Document("reservations")
public record ManagedReservationCollection(@Id UUID id, int schemaVersion,
        UUID restaurantId, UUID shiftId, List<UUID> tableIds, UUID combinationId,
        String customerIssuer, String customerSubject, int partySize, String notes,
        ManagedReservationStatus status, long version, String localStart, String localEnd,
        String zoneId, Instant startInstant, Instant endInstant,
        List<TableSnapshot> tableSnapshots, long assignedCapacity,
        Instant createdAt, Instant updatedAt, Instant cancelledAt) {
    public ManagedReservationCollection {
        if(tableIds!=null)tableIds=List.copyOf(tableIds);
        if(tableSnapshots!=null)tableSnapshots=List.copyOf(tableSnapshots);
    }
    public record TableSnapshot(UUID id, long capacity) { }
}
