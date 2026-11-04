package com.brenis.SpringWebFlux.dtos.requests;
import java.util.UUID;
public record ManagedReservationRequest(UUID shiftId,int partySize,String notes) {
    public ManagedReservationRequest { if(notes==null)notes=""; }
}
