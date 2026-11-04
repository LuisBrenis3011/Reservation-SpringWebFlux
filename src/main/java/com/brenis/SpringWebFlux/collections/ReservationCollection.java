package com.brenis.SpringWebFlux.collections;

import com.brenis.SpringWebFlux.enums.ReservationStatusEnum;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

import java.util.UUID;

@Document(collection = "reservations")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ReservationCollection {

    @Id
    private UUID id;
    @Indexed
    private String restaurantId;
    private String customerId;
    //@Field("name")
    private String customerName;
    private String customerEmail;
    private String date;
    private String time;
    private Integer partySize;
    @Indexed
    private ReservationStatusEnum status;

    private String notes;

}
