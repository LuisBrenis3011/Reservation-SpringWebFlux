package com.brenis.SpringWebFlux.dtos.requests;

import tools.jackson.databind.annotation.JsonDeserialize;
import tools.jackson.databind.deser.std.StdDeserializer;
import tools.jackson.databind.DeserializationContext;
import tools.jackson.core.JsonParser;
import tools.jackson.databind.JsonNode;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import java.util.*;

/** Estructura estricta, sin coerciones; cardinalidad/UUID/pertenencia se validan como dominio. */
@JsonDeserialize(using=TableCombinationRequest.Deserializer.class)
public record TableCombinationRequest(List<String> tableIds) {
    public TableCombinationRequest {
        if(tableIds!=null) tableIds=Collections.unmodifiableList(new ArrayList<>(tableIds));
    }
    public static class Deserializer extends StdDeserializer<TableCombinationRequest> {
        public Deserializer() { super(TableCombinationRequest.class); }
        @Override public TableCombinationRequest deserialize(JsonParser parser,DeserializationContext context) {
            JsonNode tree=parser.readValueAsTree();
            if(!tree.isObject() || tree.size()!=1 || !tree.has("tableIds") || !tree.get("tableIds").isArray())
                throw new AvailabilityException("INVALID_REQUEST","Se requiere solo tableIds como array de strings UUID");
            JsonNode array=tree.get("tableIds");
            List<String> ids=new ArrayList<>();
            for(int i=0;i<array.size();i++) {
                if(!array.get(i).isString()) throw new AvailabilityException("INVALID_REQUEST","tableIds no admite null ni coerciones");
                ids.add(array.get(i).asString());
            }
            return new TableCombinationRequest(ids);
        }
    }
}
