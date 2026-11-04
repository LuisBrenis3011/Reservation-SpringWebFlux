package com.brenis.SpringWebFlux.services.impls;
import java.security.Principal;
import java.time.format.DateTimeFormatter;
import java.time.LocalDateTime;
import java.util.*;
import org.bson.Document;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.reactive.TransactionalOperator;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection;
import com.brenis.SpringWebFlux.configs.AvailabilityProperties;
import com.brenis.SpringWebFlux.dtos.responses.*;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.mappers.ManagedReservationMapper;
import com.brenis.SpringWebFlux.repositories.*;
import com.brenis.SpringWebFlux.services.definitions.ReservationQueryService;

@Service
public class ReservationQueryServiceImpl implements ReservationQueryService {
    private final ReactiveMongoTemplate mongo;private final TransactionalOperator transactions;
    private final ReservationAccessPolicy access;private final ManagedReservationMapper mapper;
    private final LegacyReservationQueryRepository legacy;private final AvailabilityProperties properties;
    public ReservationQueryServiceImpl(ReactiveMongoTemplate mongo,TransactionalOperator transactions,ReservationAccessPolicy access,
            ManagedReservationMapper mapper,LegacyReservationQueryRepository legacy,AvailabilityProperties properties){
        this.mongo=mongo;this.transactions=transactions;this.access=access;this.mapper=mapper;this.legacy=legacy;this.properties=properties;
    }
    private AvailabilityException error(String code){return new AvailabilityException(code,code);}
    private void page(int page,int size){if(page<0||size<1||size>100)throw error("INVALID_REQUEST");}
    private void manager(ReservationAccessPolicy.Actor actor,UUID owner){if(!actor.manages(owner))throw error("FORBIDDEN");}
    private Query paged(Criteria criteria,int page,int size){return Query.query(criteria).with(Sort.by(Sort.Direction.ASC,"_id")).skip((long)page*size).limit(size);}
    private Criteria owner(UUID id){return Criteria.where("restaurantId").in(id,id.toString());}
    private boolean managed(Document d){Object value=d.get("schemaVersion");if(value==null)return false;
        if(value instanceof Number n){if(n.doubleValue()==2.0)return true;if(n.doubleValue()==1.0)return false;}
        throw error("RESERVATION_UNVERIFIABLE");}
    private ManagedReservationCollection decode(Document d){
        try{return mongo.getConverter().read(ManagedReservationCollection.class,d);}
        catch(RuntimeException e){throw new AvailabilityException("RESERVATION_UNVERIFIABLE","Reserva no verificable",e);}
    }
    private ManagedReservationResponse project(ManagedReservationCollection row){
        var r=mapper.response(row);var f=DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ss");
        var start=LocalDateTime.parse(r.localStart());var end=LocalDateTime.parse(r.localEnd());
        if(start.getNano()!=0||end.getNano()!=0)throw error("RESERVATION_UNVERIFIABLE");
        return new ManagedReservationResponse(r.kind(),r.id(),r.restaurantId(),r.owner(),r.shiftId(),r.partySize(),r.notes(),r.status(),r.version(),r.tableIds(),r.combinationId(),r.assignedCapacity(),
            start.format(f),end.format(f),r.zoneId(),r.startInstant(),r.endInstant(),r.createdAt(),r.updatedAt(),r.cancelledAt());
    }
    private <T> Mono<T> snapshot(Mono<T> work){
        return transactions.transactional(work.timeout(properties.getTransactionTimeout())).onErrorMap(e->
            e instanceof AvailabilityException?e:new AvailabilityException("DEPENDENCY_UNAVAILABLE","No se pudo consultar reservas",e));
    }
    @Override public Mono<ReservationListResponse> mine(Principal principal,int page,int size,String status){
        return Mono.defer(()->{
            var actor=access.actor(principal);access.requireCustomer(actor);page(page,size);
            if(status!=null&&!Set.of("CONFIRMED","CANCELLED").contains(status))throw error("INVALID_REQUEST");
            var criteria=Criteria.where("schemaVersion").is(2).and("customerIssuer").is(actor.issuer()).and("customerSubject").is(actor.subject());
            if(status!=null)criteria=criteria.and("status").is(status);
            return snapshot(mongo.find(paged(criteria,page,size),Document.class,"reservations").map(this::decode).map(row->{
                access.requireAccess(actor,row);return project(row);
            }).collectList().map(rows->new ReservationListResponse(rows,page,size)));
        });
    }
    @Override public Mono<ReservationListResponse> byRestaurant(Principal principal,UUID owner,int page,int size){
        return Mono.defer(()->{
            var actor=access.actor(principal);manager(actor,owner);page(page,size);
            return snapshot(mongo.find(paged(owner(owner),page,size),Document.class,"reservations").map(row->
                managed(row)?project(decode(row)):legacy.project(row,owner)).collectList().map(rows->new ReservationListResponse(rows,page,size)));
        });
    }
    @Override public Mono<ManagedReservationResponse> managed(Principal principal,UUID owner,UUID id){
        return Mono.defer(()->{var actor=access.actor(principal);
            if(!actor.isCustomer()&&!actor.manages(owner))throw error("FORBIDDEN");
            var query=Query.query(new Criteria().andOperator(owner(owner),Criteria.where("_id").is(id),Criteria.where("schemaVersion").is(2)));
            return snapshot(mongo.findOne(query,Document.class,"reservations").switchIfEmpty(Mono.error(error("NOT_FOUND"))).map(this::decode).map(row->{
                access.requireAccess(actor,row);return project(row);
            }));
        });
    }
    @Override public Mono<LegacyReservationResponse> legacy(Principal principal,UUID owner,String reference){
        return Mono.defer(()->{var actor=access.actor(principal);manager(actor,owner);Object id=legacy.parseReference(reference);
            return snapshot(legacy.find(owner,id).switchIfEmpty(Mono.error(error("NOT_FOUND"))).map(row->legacy.project(row,owner)));
        });
    }
    @Override public Mono<Object> oldById(Principal principal,UUID id){
        return Mono.defer(()->{var actor=access.actor(principal);if(actor.managerRestaurantIds().isEmpty())throw error("FORBIDDEN");
            var values=new ArrayList<Object>();for(var owner:actor.managerRestaurantIds()){values.add(owner);values.add(owner.toString());}
            var query=Query.query(new Criteria().andOperator(Criteria.where("_id").in(id,id.toString()),Criteria.where("restaurantId").in(values)));
            return snapshot(mongo.find(query,Document.class,"reservations").take(2).collectList().flatMap(rows->{
                if(rows.isEmpty())return Mono.error(error("NOT_FOUND"));
                if(rows.size()!=1)return Mono.error(error("RESERVATION_UNVERIFIABLE"));
                var row=rows.getFirst();UUID owner=LegacyReservationCommitmentAdapter.uuid(row.get("restaurantId"));
                if(owner==null||!actor.manages(owner))return Mono.error(error("NOT_FOUND"));
                if(managed(row)){var decoded=decode(row);manager(actor,decoded.restaurantId());return Mono.just((Object)project(decoded));}
                return Mono.just((Object)legacy.project(row,owner));
            }));
        });
    }
}
