package com.brenis.SpringWebFlux.dtos.responses;
import java.util.UUID;
import com.fasterxml.jackson.annotation.JsonInclude;
@JsonInclude(JsonInclude.Include.ALWAYS)
public record RestaurantTimeZoneResponse(UUID restaurantId,String zoneId,long revision) {}
