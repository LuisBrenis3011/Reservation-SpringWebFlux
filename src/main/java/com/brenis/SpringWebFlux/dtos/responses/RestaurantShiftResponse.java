package com.brenis.SpringWebFlux.dtos.responses;
import java.util.UUID;
import java.time.Instant;
public record RestaurantShiftResponse(UUID id,UUID restaurantId,String localStart,String localEnd,String zoneId,Instant startInstant,Instant endInstant,long revision) {}
