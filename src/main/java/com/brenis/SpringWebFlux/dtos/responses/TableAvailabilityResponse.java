package com.brenis.SpringWebFlux.dtos.responses;

import java.util.UUID;
public record TableAvailabilityResponse(UUID id,UUID restaurantId,String label,long capacity,long revision) {}

