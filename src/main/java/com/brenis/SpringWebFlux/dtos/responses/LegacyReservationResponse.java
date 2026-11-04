package com.brenis.SpringWebFlux.dtos.responses;
import java.util.UUID;
public record LegacyReservationResponse(String kind,String legacyRef,UUID restaurantId,String status,
                                        String customerName,String date,String time,Integer partySize,String notes) {}
