package com.brenis.SpringWebFlux.services.definitions;
import java.time.Instant;
import java.util.Set;
import java.util.UUID;
import reactor.core.publisher.Mono;
public interface ReservationCommitmentReader {
    record CommitmentSummary(boolean legacyBlocked,boolean globalBlocked,
                             Set<UUID> protectedTableIds,Set<UUID> protectedShiftIds) {}
    Mono<CommitmentSummary> read(UUID restaurantId,Instant now);
}

