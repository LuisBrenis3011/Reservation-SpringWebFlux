package com.brenis.SpringWebFlux.services.impls;

import java.util.*;
import org.springframework.stereotype.Component;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection.TableSnapshot;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;

@Component
public class ReservationAssignmentPolicy {
    public record Option(UUID combinationId,List<TableSnapshot> tables) {
        public Option { if(tables!=null)tables=List.copyOf(tables); }
        public List<UUID> tableIds() { return tables.stream().map(TableSnapshot::id).sorted(Comparator.comparing(UUID::toString)).toList(); }
        public long capacity() {
            if(tables==null || tables.isEmpty()) throw new IllegalArgumentException("Opción vacía");
            long sum=0; var ids=new HashSet<UUID>();
            for(var t:tables) {
                if(t==null||t.id()==null||t.capacity()<=0||!ids.add(t.id())) throw new IllegalArgumentException("Opción inválida");
                sum=Math.addExact(sum,t.capacity());
            }
            return sum;
        }
    }
    public Optional<Option> select(Collection<Option> options,Set<UUID> occupied,int partySize) {
        if(partySize<1||partySize>20) throw new AvailabilityException("VALIDATION_ERROR","Grupo fuera de rango");
        try {
            var unique=new TreeMap<String,Option>();
            for(var option:options) {
                long capacity=option.capacity();
                if(capacity<partySize || option.tableIds().stream().anyMatch(occupied::contains)) continue;
                String key=option.tableIds().toString();
                unique.merge(key,option,(a,b)->Comparator.nullsFirst(Comparator.<UUID,String>comparing(UUID::toString))
                        .compare(a.combinationId(),b.combinationId())<=0?a:b);
            }
            return unique.values().stream().min(Comparator.comparingLong(Option::capacity)
                    .thenComparingInt(o->o.tables().size()).thenComparing(o->o.tableIds().toString()));
        } catch(RuntimeException e) {
            throw new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Oferta no verificable",e);
        }
    }
}
