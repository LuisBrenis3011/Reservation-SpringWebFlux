package com.brenis.SpringWebFlux.dtos.requests;

import tools.jackson.databind.annotation.JsonDeserialize;
import tools.jackson.databind.deser.std.StdDeserializer;
import tools.jackson.databind.DeserializationContext;
import tools.jackson.core.JsonParser;
import tools.jackson.databind.JsonNode;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;

/** El deserializador impide coerciones de strings, fracciones y campos ausentes. */
@JsonDeserialize(using=TableCreateRequest.Deserializer.class)
public record TableCreateRequest(String label,Long capacity) {
    public static class Deserializer extends StdDeserializer<TableCreateRequest> {
        public Deserializer() { super(TableCreateRequest.class); }
        @Override public TableCreateRequest deserialize(JsonParser parser,DeserializationContext context) {
            JsonNode tree=parser.readValueAsTree();
            if(!tree.isObject() || tree.size()!=2 || !tree.has("label") || !tree.has("capacity")
                    || !tree.get("label").isString() || !tree.get("capacity").isIntegralNumber()
                    || !tree.get("capacity").canConvertToLong())
                throw new AvailabilityException("INVALID_REQUEST","Se requieren label string y capacity int64");
            return new TableCreateRequest(tree.get("label").asString(),tree.get("capacity").longValue());
        }
    }
}

