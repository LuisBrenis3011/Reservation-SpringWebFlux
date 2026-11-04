package com.brenis.SpringWebFlux.mappers;

import com.brenis.SpringWebFlux.collections.TableCollection;
import com.brenis.SpringWebFlux.dtos.responses.*;
import com.brenis.SpringWebFlux.validators.TableConfigurationValidator;
import org.springframework.stereotype.Component;
import java.util.List;

@Component
public class TableAvailabilityMapper {
    private final TableConfigurationValidator validator;
    public TableAvailabilityMapper(TableConfigurationValidator validator) { this.validator=validator; }
    public TableAvailabilityResponse table(TableCollection table,long revision) {
        return new TableAvailabilityResponse(table.id(),table.restaurantId(),table.label(),table.capacity(),revision);
    }
    public TableListResponse list(List<TableCollection> tables,long revision) {
        long total=0;
        for(var table:tables) total=validator.addCapacity(total,table.capacity());
        return new TableListResponse(tables.stream().map(t -> table(t,revision)).toList(),total,revision);
    }
}

