package com.brenis.SpringWebFlux.dtos.responses;

import com.brenis.SpringWebFlux.enums.PriceEnum;
import com.brenis.SpringWebFlux.records.Address;
import com.brenis.SpringWebFlux.records.ContactInfo;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Builder
@NoArgsConstructor
@AllArgsConstructor
@Data
public class RestaurantResponse {

    private String name;
    private Address address;
    private String cuisineType;
    private PriceEnum priceRange;
    private String openHours;
    private String logoUrl;
    private String closeAt;
    private ContactInfo contactInfo;
    private Double globalRating;
}

