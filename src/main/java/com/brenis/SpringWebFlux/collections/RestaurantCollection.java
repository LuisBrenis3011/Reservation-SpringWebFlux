package com.brenis.SpringWebFlux.collections;

import com.brenis.SpringWebFlux.dtos.Review;
import com.brenis.SpringWebFlux.enums.PriceEnum;
import com.brenis.SpringWebFlux.records.Address;
import com.brenis.SpringWebFlux.records.ContactInfo;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;


import java.util.List;
import java.util.UUID;

@Document(collection = "restaurants")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class RestaurantCollection {
    @Id
    private UUID id;
    @Indexed
    private String name;
    private Integer capacity;
    private Address address;
    @Indexed
    private String cuisineType;
    @Indexed
    private PriceEnum priceRange;
    private String openHours;
    private String logoUrl;
    private String closeAt;
    private ContactInfo contactInfo;
    private List<Review> reviews;
}
