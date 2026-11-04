package com.brenis.SpringWebFlux.services.impls;
import java.util.UUID;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
@Component
public class ReservationMutationGuard {
    public enum MutationKind { LABEL_ONLY,CREATE_OPERATIONAL,TABLE_CAPACITY,COMBINATION_MEMBERS,SHIFT,ZONE }
    private final ReservationCommitmentReader reader;
    private final org.springframework.data.mongodb.core.ReactiveMongoTemplate mongo;
    public ReservationMutationGuard(ReservationCommitmentReader reader,org.springframework.data.mongodb.core.ReactiveMongoTemplate mongo) {
        this.reader=reader; this.mongo=mongo;
    }
    public Mono<Void> check(RestaurantOperationCoordinator.Context context,MutationKind kind,UUID targetId) {
        if(kind==MutationKind.LABEL_ONLY) return Mono.empty();
        return reader.read(context.restaurantId(),context.now()).flatMap(s -> {
            if(s.globalBlocked() || s.legacyBlocked()) return Mono.error(new AvailabilityException("LEGACY_RESERVATION_BLOCK","Reservas sin adaptar"));
            if(kind==MutationKind.COMBINATION_MEMBERS) {
                return mongo.findOne(org.springframework.data.mongodb.core.query.Query.query(
                        org.springframework.data.mongodb.core.query.Criteria.where("_id").is(targetId)
                                .and("restaurantId").is(context.restaurantId())),org.bson.Document.class,"table_combinations")
                        .switchIfEmpty(Mono.error(new AvailabilityException("NOT_FOUND","Combinación inexistente")))
                        .flatMap(combination -> {
                            Object raw=combination.get("tableIds");
                            if(!(raw instanceof java.util.List<?> members))
                                return Mono.error(new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Referencias inválidas"));
                            for(Object member:members) {
                                UUID id=com.brenis.SpringWebFlux.repositories.LegacyReservationCommitmentAdapter.uuid(member);
                                if(id==null) return Mono.error(new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Referencia inválida"));
                                if(s.protectedTableIds().contains(id)) return Mono.error(new AvailabilityException("PROTECTED_RESERVATION","Reserva protegida"));
                            }
                            return Mono.<Void>empty();
                        });
            }
            boolean protectedTarget=switch(kind) {
                case TABLE_CAPACITY -> s.protectedTableIds().contains(targetId);
                case COMBINATION_MEMBERS -> false; // resuelto por integrantes arriba
                case SHIFT -> s.protectedShiftIds().contains(targetId);
                case ZONE -> !s.protectedShiftIds().isEmpty();
                default -> false;
            };
            return protectedTarget?Mono.error(new AvailabilityException("PROTECTED_RESERVATION","Reserva protegida")):Mono.empty();
        });
    }
}

