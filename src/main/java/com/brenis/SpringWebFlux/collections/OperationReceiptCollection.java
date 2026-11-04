package com.brenis.SpringWebFlux.collections;
import java.util.UUID;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
/** Índice compuesto único preparado por el inicializador. Sin TTL. */
@Document("operation_receipts")
public record OperationReceiptCollection(@Id UUID id,UUID restaurantId,String idempotencyKey,
        String fingerprint,int httpStatus,Object responseBody,long resultingRevision,String location) {}

