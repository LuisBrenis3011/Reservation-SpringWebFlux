package com.brenis.SpringWebFlux.records;

import lombok.Builder;

@Builder
public record Address(
        String street,
        String city,
        String postalCode
) {
}
