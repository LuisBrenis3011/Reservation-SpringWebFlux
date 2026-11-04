package com.brenis.SpringWebFlux.dtos.responses;

import java.util.List;
public record TableListResponse(List<TableAvailabilityResponse> items,long totalCapacity,long revision) {
    public TableListResponse { items=List.copyOf(items); }
}

