package com.brenis.SpringWebFlux.mappers;

import com.brenis.SpringWebFlux.collections.*;
import com.brenis.SpringWebFlux.dtos.requests.TableCombinationRequest;
import com.brenis.SpringWebFlux.dtos.responses.*;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.validators.TableCombinationValidator;
import org.springframework.stereotype.Component;
import java.util.*;

@Component
public class TableCombinationMapper {
    private final TableCombinationValidator validator;
    public TableCombinationMapper(TableCombinationValidator validator) { this.validator=validator; }
    public TableCombinationResponse response(TableCombinationCollection combination,List<TableCollection> tables,long revision) {
        TableCombinationValidator.ValidatedCombination selected;
        List<TableCollection> members;
        try {
            selected=validator.validate(new TableCombinationRequest(combination.tableIds().stream().map(UUID::toString).toList()));
            Set<UUID> ids=new HashSet<>(selected.tableIds());
            members=tables.stream().filter(table -> ids.contains(table.id())).toList();
            validator.requireOwned(combination.restaurantId(),selected,members);
        } catch(AvailabilityException | NullPointerException invalidReferences) {
            throw new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Referencias de combinacion no disponibles",invalidReferences);
        }
        return new TableCombinationResponse(combination.id(),combination.restaurantId(),selected.tableIds(),validator.sum(members),revision);
    }
    public TableCombinationListResponse list(List<TableCombinationCollection> combinations,List<TableCollection> tables,long revision) {
        return new TableCombinationListResponse(combinations.stream().map(row -> response(row,tables,revision)).toList(),revision);
    }
}
