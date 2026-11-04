package com.brenis.SpringWebFlux.collections;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import java.util.UUID;

/** Identidad y restaurante inmutables; la suma del salón se calcula, no se almacena. */
@Document("restaurant_tables")
public record TableCollection(@Id UUID id, UUID restaurantId, String label, String labelKey, long capacity) {}

