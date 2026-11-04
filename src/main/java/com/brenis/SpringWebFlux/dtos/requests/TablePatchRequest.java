package com.brenis.SpringWebFlux.dtos.requests;

import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import tools.jackson.core.JsonParser;
import tools.jackson.databind.*;
import tools.jackson.databind.annotation.JsonDeserialize;
import tools.jackson.databind.deser.std.StdDeserializer;

/** null interno significa campo omitido; un null explícito en JSON nunca se acepta. */
@JsonDeserialize(using=TablePatchRequest.Deserializer.class)
public record TablePatchRequest(String label,Long capacity) {
    public TablePatchRequest {
        if(label==null && capacity==null)
            throw new AvailabilityException("INVALID_REQUEST","Enviar al menos label o capacity");
    }
    public static class Deserializer extends StdDeserializer<TablePatchRequest> {
        public Deserializer() { super(TablePatchRequest.class); }
        @Override public TablePatchRequest deserialize(JsonParser parser,DeserializationContext context) {
            JsonNode tree=parser.readValueAsTree();
            if(!tree.isObject() || tree.isEmpty())
                throw invalid();
            for(var field:tree.properties())
                if(!field.getKey().equals("label") && !field.getKey().equals("capacity")) throw invalid();
            if(tree.has("label") && !tree.get("label").isString()) throw invalid();
            if(tree.has("capacity") && (!tree.get("capacity").isIntegralNumber()
                    || !tree.get("capacity").canConvertToLong())) throw invalid();
            return new TablePatchRequest(tree.has("label")?tree.get("label").asString():null,
                    tree.has("capacity")?tree.get("capacity").longValue():null);
        }
        private AvailabilityException invalid() {
            return new AvailabilityException("INVALID_REQUEST","PATCH admite solo label string y capacity int64 no nulos");
        }
    }
}

