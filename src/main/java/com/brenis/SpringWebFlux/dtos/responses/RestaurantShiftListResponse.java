package com.brenis.SpringWebFlux.dtos.responses;
import java.util.List;
public record RestaurantShiftListResponse(List<RestaurantShiftResponse> items,long revision) {
    public RestaurantShiftListResponse{items=List.copyOf(items);}
}
