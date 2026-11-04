package com.brenis.SpringWebFlux.dtos;
import java.time.Instant;
public final class AvailabilityHttpModels {
    private AvailabilityHttpModels() {}
    public record CommandMetadata(String idempotencyKey, String fingerprint, Long expectedRevision,
                                  int httpStatus, String location) {
        public CommandMetadata {
            if(idempotencyKey==null || idempotencyKey.isEmpty() || idempotencyKey.length()>128)
                throw new com.brenis.SpringWebFlux.exceptions.AvailabilityException("INVALID_REQUEST","Idempotency-Key inválida");
            if(expectedRevision!=null && expectedRevision<0)
                throw new com.brenis.SpringWebFlux.exceptions.AvailabilityException("INVALID_REQUEST","Revisión inválida");
        }
    }
    public record ApiError(String code,String message,int status,String operationId,Instant timestamp) {}
}

