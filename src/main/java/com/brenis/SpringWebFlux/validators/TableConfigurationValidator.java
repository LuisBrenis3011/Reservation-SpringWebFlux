package com.brenis.SpringWebFlux.validators;

import com.brenis.SpringWebFlux.dtos.requests.TableCreateRequest;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import com.brenis.SpringWebFlux.collections.TableCollection;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import org.springframework.stereotype.Component;
import java.util.Locale;

@Component
public class TableConfigurationValidator {
    public record ValidatedTable(String label,String labelKey,long capacity) {}
    public ValidatedTable validate(TableCreateRequest request) {
        if(request==null || request.label()==null || request.label().trim().isEmpty()
                || request.capacity()==null || request.capacity()<1)
            throw new AvailabilityException("VALIDATION_ERROR","Etiqueta y capacidad positiva requeridas");
        String label=request.label().trim();
        return new ValidatedTable(label,label.toLowerCase(Locale.ROOT),request.capacity());
    }
    public long addCapacity(long left,long right) {
        try { return Math.addExact(left,right); }
        catch(ArithmeticException overflow) {
            throw new AvailabilityException("VALIDATION_ERROR","Capacidad total fuera de int64",overflow);
        }
    }
    public TableCollection patch(TableCollection current,TablePatchRequest request) {
        if(request==null) throw new AvailabilityException("INVALID_REQUEST","PATCH requerido");
        var input=validate(new TableCreateRequest(
                request.label()==null?current.label():request.label(),
                request.capacity()==null?current.capacity():request.capacity()));
        return new TableCollection(current.id(),current.restaurantId(),input.label(),input.labelKey(),input.capacity());
    }
}

