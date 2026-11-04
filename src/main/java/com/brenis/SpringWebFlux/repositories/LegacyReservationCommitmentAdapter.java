package com.brenis.SpringWebFlux.repositories;
import java.time.*;
import java.util.*;
import org.bson.Document;
import org.bson.types.Binary;
import org.bson.BsonBinary;
import org.bson.UuidRepresentation;
import org.springframework.stereotype.Component;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.Query;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.services.definitions.ReservationCommitmentReader;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
@Component
public class LegacyReservationCommitmentAdapter implements ReservationCommitmentReader {
    private final ReactiveMongoTemplate mongo;
    private final Duration timeout;
    public LegacyReservationCommitmentAdapter(ReactiveMongoTemplate mongo) { this.mongo=mongo; this.timeout=Duration.ofSeconds(3); }
    @org.springframework.beans.factory.annotation.Autowired
    public LegacyReservationCommitmentAdapter(ReactiveMongoTemplate mongo,com.brenis.SpringWebFlux.configs.AvailabilityProperties properties) {
        this.mongo=mongo; this.timeout=properties.getCommitmentCheckTimeout();
    }
    public static UUID uuid(Object value) {
        try {
            if(value instanceof UUID id) return id;
            if(value instanceof String text) return UUID.fromString(text);
            if(value instanceof Binary b && b.getType()==4) return new BsonBinary(b.getType(),b.getData()).asUuid(UuidRepresentation.STANDARD);
            if(value instanceof BsonBinary b && b.getType()==4) return b.asUuid(UuidRepresentation.STANDARD);
        } catch(RuntimeException ignored) { }
        return null;
    }
    private static Instant instant(Object value) {
        try { if(value instanceof Date d) return d.toInstant();
            if(value instanceof Instant i) return i;
            if(value instanceof String s) return Instant.parse(s);
        } catch(RuntimeException ignored) {}
        return null;
    }
    @Override public Mono<CommitmentSummary> read(UUID restaurantId,Instant now) {
        return mongo.find(new Query(),Document.class,"reservations").collectList().map(records -> {
            boolean legacy=false,global=false; Set<UUID> tables=new HashSet<>(),shifts=new HashSet<>();
            for(Document raw:records) {
                UUID owner=uuid(raw.get("restaurantId"));
                if(owner==null) { global=true; continue; }
                if(!owner.equals(restaurantId)) continue;
                String status=Objects.toString(raw.get("status"),"").toUpperCase(Locale.ROOT);
                if(Set.of("CANCELLED","ATTENDED","NO_SHOW").contains(status)) continue;
                Instant end=instant(raw.get("endInstant")),start=instant(raw.get("startInstant"));
                boolean reliable=end!=null && start!=null && end.isAfter(start);
                try {
                    ZoneId zone=ZoneId.of(raw.getString("zoneId"));
                    LocalDateTime localStart=LocalDateTime.parse(raw.getString("localStart"));
                    LocalDateTime localEnd=LocalDateTime.parse(raw.getString("localEnd"));
                    var startOffsets=zone.getRules().getValidOffsets(localStart);
                    var endOffsets=zone.getRules().getValidOffsets(localEnd);
                    reliable=reliable && startOffsets.size()==1 && endOffsets.size()==1
                            && localStart.toInstant(startOffsets.getFirst()).equals(start)
                            && localEnd.toInstant(endOffsets.getFirst()).equals(end);
                } catch(RuntimeException invalidTime) { reliable=false; }
                if(reliable && !end.isAfter(now)) continue;
                UUID shift=uuid(raw.get("shiftId"));
                List<?> ids=raw.get("tableIds") instanceof List<?> l?l:List.of();
                Set<UUID> parsed=new HashSet<>(); for(Object id:ids) { UUID v=uuid(id); if(v!=null) parsed.add(v); }
                boolean complete=reliable && shift!=null && !ids.isEmpty() && parsed.size()==ids.size();
                if(!complete || !status.equals("CONFIRMED")) { legacy=true; continue; }
                tables.addAll(parsed); shifts.add(shift);
            }
            return new CommitmentSummary(legacy,global,Set.copyOf(tables),Set.copyOf(shifts));
        }).timeout(timeout).onErrorMap(e -> e instanceof AvailabilityException?e:
                new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","No se pudieron comprobar reservas",e));
    }
}

