package com.brenis.SpringWebFlux.dtos.requests;
import tools.jackson.databind.annotation.JsonDeserialize;
import tools.jackson.databind.deser.std.StdDeserializer;
import tools.jackson.databind.DeserializationContext;
import tools.jackson.databind.JsonNode;
import tools.jackson.core.JsonParser;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
@JsonDeserialize(using=RestaurantShiftRequest.Deserializer.class)
public record RestaurantShiftRequest(String localStart,String localEnd) {
    public static class Deserializer extends StdDeserializer<RestaurantShiftRequest> {
        public Deserializer(){super(RestaurantShiftRequest.class);}
        @Override public RestaurantShiftRequest deserialize(JsonParser parser,DeserializationContext context){
            JsonNode tree=parser.readValueAsTree();
            if(!tree.isObject() || tree.size()!=2 || !tree.has("localStart") || !tree.has("localEnd") || !tree.get("localStart").isString() || !tree.get("localEnd").isString())
                throw new AvailabilityException("INVALID_REQUEST","Se requieren solo localStart y localEnd como strings");
            return new RestaurantShiftRequest(tree.get("localStart").asString(),tree.get("localEnd").asString());
        }
    }
}
