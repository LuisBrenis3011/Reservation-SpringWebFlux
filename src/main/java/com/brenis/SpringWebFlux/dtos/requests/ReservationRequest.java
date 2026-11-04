package com.brenis.SpringWebFlux.dtos.requests;

import jakarta.validation.constraints.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ReservationRequest {

    @NotNull(message = "Restaurant ID is required")
    @Pattern(regexp = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
            message = "Restaurant ID must be a valid UUID")
    private String restaurantId;

    @NotNull(message = "Customer ID is required")
    @Pattern(regexp = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
            message = "Customer ID must be a valid UUID")
    private String customerId;

    @NotNull(message = "Customer name is required")
    @Size(min = 3, max = 21, message = "Customer name must be between 3 and 21 characters")
    private String customerName;

    @NotNull(message = "Customer email is required")
    @Email(message = "Customer email must be a valid email address")
    private String customerEmail;

    @NotNull(message = "Date and time is required")
    @Pattern(regexp = "^\\d{4}-\\d{2}-\\d{2},\\d{2}:\\d{2}$",
            message = "DateTime must be in format YYYY-MM-DD,HH:mm (example: 2025-06-16,15:30)")
    private String dateTime;

    @NotNull(message = "Party size is required")
    @Min(value = 1, message = "Party size must be at least 1")
    @Max(value = 20, message = "Party size cannot exceed 20")
    private Integer partySize;

    private String comment;

}
