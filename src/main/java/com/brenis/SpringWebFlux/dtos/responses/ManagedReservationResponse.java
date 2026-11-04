package com.brenis.SpringWebFlux.dtos.responses;
import java.time.Instant;
import java.util.*;
public record ManagedReservationResponse(String kind,UUID id,UUID restaurantId,Owner owner,UUID shiftId,
        int partySize,String notes,String status,long version,List<UUID> tableIds,UUID combinationId,
        long assignedCapacity,String localStart,String localEnd,String zoneId,Instant startInstant,
        Instant endInstant,Instant createdAt,Instant updatedAt,Instant cancelledAt) {
    public record Owner(String issuer,String subject) {}
}
