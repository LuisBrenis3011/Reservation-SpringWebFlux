package com.brenis.SpringWebFlux.validators;
import java.time.*;
import org.springframework.stereotype.Component;
import com.brenis.SpringWebFlux.dtos.requests.RestaurantShiftRequest;
import com.brenis.SpringWebFlux.collections.RestaurantShiftCollection;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.exceptions.ShiftLocalTimeException;
@Component
public class RestaurantShiftValidator {
    public record ValidatedShift(String localStart,String localEnd,String zoneId,Instant startInstant,Instant endInstant) {}
    private LocalDateTime local(String value){
        if(value==null || !value.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"))throw new DateTimeException("Formato local con segundos requerido");
        return LocalDateTime.parse(value);
    }
    private Instant instant(LocalDateTime value,ZoneId zone){
        var offsets=zone.getRules().getValidOffsets(value);
        if(offsets.isEmpty())throw new ShiftLocalTimeException(ShiftLocalTimeException.Reason.NONEXISTENT);
        if(offsets.size()>1)throw new ShiftLocalTimeException(ShiftLocalTimeException.Reason.AMBIGUOUS);
        return value.toInstant(offsets.getFirst());
    }
    public ValidatedShift validate(RestaurantShiftRequest request,String zoneId,Instant now){
        ValidatedShift result;
        try{
            if(request==null || zoneId==null || zoneId.isBlank())throw new DateTimeException("Zona requerida");
            var zone=ZoneId.of(zoneId);
            var start=instant(local(request.localStart()),zone);var end=instant(local(request.localEnd()),zone);
            if(!end.isAfter(start))throw new DateTimeException("Fin no posterior al inicio");
            result=new ValidatedShift(request.localStart(),request.localEnd(),zoneId,start,end);
        }catch(DateTimeException e){throw new AvailabilityException("VALIDATION_ERROR","Zona, fecha o interpretacion temporal invalida");}
        if(!result.startInstant().isAfter(now))throw new AvailabilityException("SHIFT_ALREADY_STARTED","Inicio debe ser futuro");
        return result;
    }
    public boolean overlaps(ValidatedShift input,RestaurantShiftCollection existing){
        if(existing.startInstant()==null || existing.endInstant()==null || !existing.endInstant().isAfter(existing.startInstant()))
            throw new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Intervalo persistido no verificable");
        return input.startInstant().isBefore(existing.endInstant()) && input.endInstant().isAfter(existing.startInstant());
    }
}
