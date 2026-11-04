package com.brenis.SpringWebFlux.repositories;
import java.time.*;
import java.util.*;
import org.bson.Document;
import org.springframework.stereotype.Component;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.Query;
import reactor.core.publisher.*;
import com.brenis.SpringWebFlux.collections.*;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.validators.ReservationIntegrityValidator;

@Component
public class ReservationOccupancyReader {
    public record Occupancy(Set<UUID> tableIds,boolean blocked) {}
    private final ReactiveMongoTemplate mongo;
    private final LegacyReservationCommitmentAdapter legacy;
    private final ReservationIntegrityValidator integrity;
    public ReservationOccupancyReader(ReactiveMongoTemplate mongo,LegacyReservationCommitmentAdapter legacy,ReservationIntegrityValidator integrity){this.mongo=mongo;this.legacy=legacy;this.integrity=integrity;}
    public Mono<Occupancy> read(UUID restaurant,UUID shift,UUID excluded,Instant now){
        return legacy.read(restaurant,now).flatMap(summary->{
            if(summary.globalBlocked()||summary.legacyBlocked())return Mono.just(new Occupancy(Set.of(),true));
            return mongo.find(new Query(),Document.class,"reservations")
                .filter(d->restaurant.equals(LegacyReservationCommitmentAdapter.uuid(d.get("restaurantId"))))
                .filter(d->"CONFIRMED".equals(d.getString("status")))
                .concatMap(d->verify(d,restaurant,shift,excluded,now))
                .collectList().map(values->{Set<UUID> ids=new HashSet<>();boolean blocked=false;for(var value:values){ids.addAll(value.tableIds());blocked|=value.blocked();}return new Occupancy(Set.copyOf(ids),blocked);});
        }).onErrorMap(e->e instanceof AvailabilityException?e:new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Ocupación no verificable",e));
    }
    private Mono<Occupancy> verify(Document d,UUID owner,UUID requested,UUID excluded,Instant now){
        return Mono.defer(()->{
            if(Objects.equals(2,d.get("schemaVersion"))) integrity.validate(mongo.getConverter().read(ManagedReservationCollection.class,d));
            Instant end=instant(d.get("endInstant"));
            if(end!=null&&!end.isAfter(now))return Mono.just(new Occupancy(Set.of(),false));
            UUID shiftId=LegacyReservationCommitmentAdapter.uuid(d.get("shiftId"));
            if(shiftId==null)return Mono.just(new Occupancy(Set.of(),true));
            return mongo.findById(shiftId,RestaurantShiftCollection.class).flatMap(s->{
                if(!owner.equals(s.restaurantId())||!Objects.equals(s.localStart(),d.get("localStart"))||!Objects.equals(s.localEnd(),d.get("localEnd"))
                        ||!Objects.equals(s.zoneId(),d.get("zoneId"))||!Objects.equals(s.startInstant(),instant(d.get("startInstant")))||!Objects.equals(s.endInstant(),end))return Mono.just(new Occupancy(Set.of(),true));
                if(!(d.get("tableIds") instanceof List<?> raw)||raw.isEmpty())return Mono.just(new Occupancy(Set.of(),true));
                Set<UUID> ids=new HashSet<>();for(Object value:raw){UUID id=LegacyReservationCommitmentAdapter.uuid(value);if(id==null||!ids.add(id))return Mono.just(new Occupancy(Set.of(),true));}
                return Flux.fromIterable(ids).concatMap(id->mongo.findById(id,TableCollection.class).map(t->owner.equals(t.restaurantId())).defaultIfEmpty(false))
                    .all(Boolean::booleanValue).map(valid->!valid?new Occupancy(Set.of(),true):new Occupancy(requested.equals(shiftId)&&!Objects.equals(excluded,LegacyReservationCommitmentAdapter.uuid(d.get("_id")))?Set.copyOf(ids):Set.of(),false));
            }).defaultIfEmpty(new Occupancy(Set.of(),true));
        });
    }
    private Instant instant(Object value){if(value instanceof Date d)return d.toInstant();if(value instanceof Instant i)return i;if(value instanceof String s){try{return Instant.parse(s);}catch(RuntimeException ignored){}}return null;}
}
