package com.brenis.SpringWebFlux.collections;
import java.time.Instant;
import java.util.UUID;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
@Document("restaurant_shifts")
public record RestaurantShiftCollection(@Id UUID id,UUID restaurantId,String localStart,String localEnd,String zoneId,Instant startInstant,Instant endInstant) {}
