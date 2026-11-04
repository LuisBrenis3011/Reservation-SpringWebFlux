package com.brenis.SpringWebFlux.validators;

import com.brenis.SpringWebFlux.collections.TableCollection;
import com.brenis.SpringWebFlux.dtos.requests.TableCombinationRequest;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import org.springframework.stereotype.Component;
import java.util.*;

@Component
public class TableCombinationValidator {
    public record ValidatedCombination(List<UUID> tableIds,String memberKey) {
        public ValidatedCombination { tableIds=List.copyOf(tableIds); }
    }
    private final TableConfigurationValidator tableValidator;
    public TableCombinationValidator(TableConfigurationValidator tableValidator) { this.tableValidator=tableValidator; }
    private AvailabilityException invalid() { return new AvailabilityException("VALIDATION_ERROR","Se requieren al menos dos mesas propias distintas y existentes"); }
    public ValidatedCombination validate(TableCombinationRequest request) {
        if(request==null || request.tableIds()==null || request.tableIds().size()<2) throw invalid();
        List<UUID> ids=new ArrayList<>();
        Set<UUID> seen=new HashSet<>();
        for(String value:request.tableIds()) {
            UUID id;
            try {
                id=UUID.fromString(value);
                if(!id.toString().equalsIgnoreCase(value)) throw invalid();
            } catch(IllegalArgumentException | NullPointerException malformed) { throw invalid(); }
            if(!seen.add(id)) throw invalid(); // no eliminar repetidos silenciosamente
            ids.add(id);
        }
        ids.sort(Comparator.comparing(UUID::toString));
        String key=String.join(",",ids.stream().map(UUID::toString).toList());
        return new ValidatedCombination(ids,key);
    }
    public void requireOwned(UUID owner,ValidatedCombination selected,List<TableCollection> members) {
        if(members.size()!=selected.tableIds().size()) throw invalid();
        Set<UUID> found=new HashSet<>();
        for(TableCollection table:members) {
            if(!owner.equals(table.restaurantId()) || !selected.tableIds().contains(table.id()) || !found.add(table.id())) throw invalid();
        }
    }
    public long sum(List<TableCollection> members) {
        long result=0;
        for(TableCollection table:members) {
            if(table.capacity()<1) throw invalid();
            result=tableValidator.addCapacity(result,table.capacity());
        }
        return result;
    }
}
