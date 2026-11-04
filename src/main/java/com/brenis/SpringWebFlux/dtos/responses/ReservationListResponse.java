package com.brenis.SpringWebFlux.dtos.responses;
import java.util.List;
public record ReservationListResponse(List<?> items,int page,int size) {
    public ReservationListResponse { items=List.copyOf(items); }
}
