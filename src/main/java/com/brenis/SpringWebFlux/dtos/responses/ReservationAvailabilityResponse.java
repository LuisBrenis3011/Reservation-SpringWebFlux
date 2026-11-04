package com.brenis.SpringWebFlux.dtos.responses;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
public record ReservationAvailabilityResponse(UUID restaurantId,String date,int partySize,Instant observedAt,List<Item> items) {
    public record Item(UUID shiftId,String localStart,String localEnd,String zoneId,Instant startInstant,Instant endInstant,
                       String bookingWindow,String availability,boolean reservable) {}
}
