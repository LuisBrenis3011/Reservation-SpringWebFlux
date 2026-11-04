package com.brenis.SpringWebFlux.collections;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import java.util.List;
import java.util.UUID;

/** El conjunto es canonico; su capacidad se deriva de las mesas, nunca se persiste aqui. */
@Document("table_combinations")
public record TableCombinationCollection(@Id UUID id, UUID restaurantId, List<UUID> tableIds, String memberKey) {
    public TableCombinationCollection { tableIds=List.copyOf(tableIds); }
}
