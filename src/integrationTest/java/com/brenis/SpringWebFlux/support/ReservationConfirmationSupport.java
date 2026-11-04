package com.brenis.SpringWebFlux.support;
import java.util.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;
import org.springframework.data.mongodb.core.query.*;
import com.brenis.SpringWebFlux.collections.*;
import com.brenis.SpringWebFlux.services.definitions.ReservationCommandService;
import com.brenis.SpringWebFlux.dtos.requests.ManagedReservationRequest;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse;
import com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator.Result;
import reactor.core.publisher.Mono;

@SpringJUnitConfig(ReservationConfirmationSupport.Configuration.class)
public abstract class ReservationConfirmationSupport extends ManagedReservationIntegrationSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false)
    @org.springframework.context.annotation.Import({ManagedReservationIntegrationSupport.Configuration.class,
        com.brenis.SpringWebFlux.services.impls.ReservationCommandServiceImpl.class,
        com.brenis.SpringWebFlux.mappers.ManagedReservationMapper.class})
    public static class Configuration {}
    @Autowired protected ReservationCommandService commands;
    protected UUID shift,table;
    private boolean ownPolicy;
    @org.junit.jupiter.api.BeforeEach void prepareConfirmation(){
        ownPolicy=!mongo.exists(Query.query(Criteria.where("_id").is(ReservationPolicyCollection.ID)),"reservation_policy").block();
        if(ownPolicy)mongo.insert(new ReservationPolicyCollection(ReservationPolicyCollection.ID,true,clock.instant())).block();
        table=UUID.randomUUID();shift=UUID.randomUUID();
        mongo.insert(new TableCollection(table,restaurant,"Mesa","mesa",4)).block();
        var start=clock.instant().plusSeconds(10800);var end=start.plusSeconds(3600);
        mongo.insert(new RestaurantShiftCollection(shift,restaurant,java.time.LocalDateTime.ofInstant(start,java.time.ZoneOffset.UTC).toString(),
            java.time.LocalDateTime.ofInstant(end,java.time.ZoneOffset.UTC).toString(),"UTC",start,end)).block();
    }
    @org.junit.jupiter.api.AfterEach void cleanConfirmation(){
        try{
            for(String collection:List.of("reservations","restaurant_tables","table_combinations","restaurant_shifts","operation_receipts"))
                mongo.remove(Query.query(Criteria.where("restaurantId").is(restaurant)),collection).block();
        }finally{if(ownPolicy)mongo.remove(Query.query(Criteria.where("_id").is(ReservationPolicyCollection.ID)),"reservation_policy").block();}
    }
    protected Mono<Result<ManagedReservationResponse>> confirm(String subject,String key,int size){return confirm(subject,key,new ManagedReservationRequest(shift,size,""));}
    protected Mono<Result<ManagedReservationResponse>> confirm(String subject,String key,ManagedReservationRequest body){
        String internal;
        try{internal="rsv:"+HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest((subject+":"+key).getBytes(java.nio.charset.StandardCharsets.UTF_8)));}
        catch(java.security.NoSuchAlgorithmException impossible){throw new IllegalStateException(impossible);}
        return commands.confirm(customer(subject),restaurant,body,new CommandMetadata(internal,body.toString(),null,201,null));
    }
}
