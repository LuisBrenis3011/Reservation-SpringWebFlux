package com.brenis.SpringWebFlux.dtos.responses;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ReservationResponse {
    private String restaurantId;
    private String customerName;
    private String dateTime;
    private Integer partySize;

}
