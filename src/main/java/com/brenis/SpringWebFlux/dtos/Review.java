package com.brenis.SpringWebFlux.dtos;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Review {

    private Object customerId;
    private String customerName;
    private Integer rating;
    private String comment;
    private Instant timestamp;;
}
