package com.brenis.SpringWebFlux.support;

import java.security.Principal;
import java.util.*;
import org.bson.Document;
import org.springframework.data.mongodb.core.query.*;
import com.brenis.SpringWebFlux.collections.*;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.ManagedReservationRequest;
import com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse;
import com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator.Result;
import reactor.core.publisher.Mono;

/** Solo helpers sobre las fixtures existentes; no crea otro contexto ni Mongo. */
public abstract class ReservationReplacementSupport extends ReservationConfirmationSupport {
    protected Mono<Result<ManagedReservationResponse>> replace(Principal actor,UUID id,long version,String key,UUID target,int size,String notes){
        var body=new ManagedReservationRequest(target,size,notes);
        var identity=new com.brenis.SpringWebFlux.services.impls.ReservationAccessPolicy().actor(actor);
        return commands.replace(actor,restaurant,id,version,body,
            new CommandMetadata("rsv:replace:"+identity.issuer()+":"+identity.subject()+":"+key,
                id+":"+version+":"+body,null,200,null));
    }
    protected UUID destination(long seconds){
        UUID id=UUID.randomUUID();var start=clock.instant().plusSeconds(seconds);var end=start.plusSeconds(3600);
        mongo.insert(new RestaurantShiftCollection(id,restaurant,java.time.LocalDateTime.ofInstant(start,java.time.ZoneOffset.UTC).toString(),
            java.time.LocalDateTime.ofInstant(end,java.time.ZoneOffset.UTC).toString(),"UTC",start,end)).block();return id;
    }
    protected void extraTable(UUID id,int capacity){mongo.insert(new TableCollection(id,restaurant,"Extra-"+id,"extra-"+id,capacity)).block();}
    protected Map<String,Object> state(){
        var result=new LinkedHashMap<String,Object>();
        for(String name:List.of("restaurants","reservations","restaurant_operations","operation_receipts","restaurant_tables","table_combinations","restaurant_shifts","restaurant_time_zones","reservation_policy")){
            result.put(name,mongo.find(new Query().with(org.springframework.data.domain.Sort.by("_id")),Document.class,name).collectList().block());
            result.put(name+"-indexes",mongo.indexOps(name).getIndexInfo().collectList().block().toString());
        }
        return result;
    }
    protected Query byId(UUID id){return Query.query(Criteria.where("_id").is(id));}
}
