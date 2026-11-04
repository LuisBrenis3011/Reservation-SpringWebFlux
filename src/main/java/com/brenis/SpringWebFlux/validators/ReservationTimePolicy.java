package com.brenis.SpringWebFlux.validators;

import java.time.*;
import org.springframework.stereotype.Component;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;

@Component
public class ReservationTimePolicy {
    public enum BookingWindow { OPEN, TOO_SOON, TOO_FAR }
    public BookingWindow window(Instant now,Instant start) {
        if(start.isBefore(now.plus(Duration.ofHours(2)))) return BookingWindow.TOO_SOON;
        return start.isAfter(now.plus(Duration.ofDays(90)))?BookingWindow.TOO_FAR:BookingWindow.OPEN;
    }
    public void confirm(Instant now,Instant start,int partySize) {
        group(partySize);
        if(window(now,start)!=BookingWindow.OPEN) reject();
    }
    public void replace(Instant now,Instant original,Instant destination,int partySize,boolean manager) {
        group(partySize); cancel(now,original,manager,false);
        if(manager) { if(!destination.isAfter(now)||destination.isAfter(now.plus(Duration.ofDays(90)))) reject(); }
        else if(window(now,destination)!=BookingWindow.OPEN) reject();
    }
    public void cancel(Instant now,Instant original,boolean manager,boolean alreadyCancelled) {
        if(alreadyCancelled) return;
        if(manager?!original.isAfter(now):original.isBefore(now.plus(Duration.ofHours(2)))) reject();
    }
    public void group(int size) { if(size<1||size>20) throw new AvailabilityException("VALIDATION_ERROR","Grupo fuera de rango"); }
    private void reject() { throw new AvailabilityException("RESERVATION_WINDOW_CLOSED","Fuera del plazo permitido"); }
}
