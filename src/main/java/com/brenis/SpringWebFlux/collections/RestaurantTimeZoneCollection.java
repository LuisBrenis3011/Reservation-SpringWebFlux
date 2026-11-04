package com.brenis.SpringWebFlux.collections;
import java.util.UUID;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
@Document("restaurant_time_zones")
public record RestaurantTimeZoneCollection(@Id UUID id,String zoneId) {}
