package com.brenis.SpringWebFlux.collections;
import java.time.Instant;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
@Document("reservation_policy")
public record ReservationPolicyCollection(@Id String id,boolean legacyWritesRetired,Instant cutoverAt) {
    public static final String ID="managed-reservations-v1";
}
