package com.brenis.SpringWebFlux.collections;
import java.util.UUID;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
@Document("restaurant_operations")
public record RestaurantOperationCollection(@Id UUID id,long revision,int schemaVersion) {}

