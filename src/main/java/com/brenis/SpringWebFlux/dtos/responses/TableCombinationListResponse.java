package com.brenis.SpringWebFlux.dtos.responses;

import java.util.List;

public record TableCombinationListResponse(List<TableCombinationResponse> items,long revision) {
    public TableCombinationListResponse { items=List.copyOf(items); }
}
