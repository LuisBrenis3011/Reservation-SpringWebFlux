package com.brenis.SpringWebFlux.dtos.requests;
import tools.jackson.databind.annotation.JsonDeserialize;
import tools.jackson.databind.deser.std.StdDeserializer;
import tools.jackson.databind.DeserializationContext;
import tools.jackson.core.JsonParser;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
@JsonDeserialize(using=RestaurantTimeZoneRequest.Deserializer.class)
public record RestaurantTimeZoneRequest(String zoneId) {
    public static class Deserializer extends StdDeserializer<RestaurantTimeZoneRequest> {
        public Deserializer(){super(RestaurantTimeZoneRequest.class);}
        @Override public RestaurantTimeZoneRequest deserialize(JsonParser parser,DeserializationContext context){
            tools.jackson.databind.JsonNode tree=parser.readValueAsTree();
            if(!tree.isObject() || tree.size()!=1 || !tree.has("zoneId") || !tree.get("zoneId").isString())
                throw new AvailabilityException("INVALID_REQUEST","Se requiere solo zoneId como string");
            return new RestaurantTimeZoneRequest(tree.get("zoneId").asString());
        }
    }
}
