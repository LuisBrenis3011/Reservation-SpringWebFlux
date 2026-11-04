package com.brenis.SpringWebFlux.dtos.responses;

import java.util.List;
import java.util.UUID;

public record TableCombinationResponse(UUID id,UUID restaurantId,List<UUID> tableIds,long capacity,long revision) {
    public TableCombinationResponse { tableIds=List.copyOf(tableIds); }
}
