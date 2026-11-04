package com.brenis.SpringWebFlux.support;
import java.util.*;
import java.time.*;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.mongodb.core.query.*;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection.TableSnapshot;
import com.brenis.SpringWebFlux.enums.ManagedReservationStatus;
import com.brenis.SpringWebFlux.services.definitions.ReservationQueryService;
import com.brenis.SpringWebFlux.repositories.LegacyReservationQueryRepository;
@SpringJUnitConfig(ReservationQueryIntegrationSupport.Configuration.class)
public abstract class ReservationQueryIntegrationSupport extends ManagedReservationIntegrationSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false)
    @org.springframework.context.annotation.Import({ManagedReservationIntegrationSupport.Configuration.class,
        com.brenis.SpringWebFlux.services.impls.ReservationQueryServiceImpl.class,
        com.brenis.SpringWebFlux.mappers.ManagedReservationMapper.class,LegacyReservationQueryRepository.class})
    public static class Configuration {}
    @Autowired protected ReservationQueryService queries;
    @Autowired protected LegacyReservationQueryRepository legacyQueries;
    protected final List<Object> ownIds=new ArrayList<>();
    protected ManagedReservationCollection insertManaged(UUID owner,String subject,boolean cancelled){
        var id=UUID.randomUUID();var table=UUID.randomUUID();var start=clock.instant().plusSeconds(10800);
        var row=new ManagedReservationCollection(id,2,owner,UUID.randomUUID(),List.of(table),null,"https://issuer.example.test",subject,2,"nota",
            cancelled?ManagedReservationStatus.CANCELLED:ManagedReservationStatus.CONFIRMED,1,
            LocalDateTime.ofInstant(start,ZoneOffset.UTC).toString(),LocalDateTime.ofInstant(start.plusSeconds(3600),ZoneOffset.UTC).toString(),
            "UTC",start,start.plusSeconds(3600),List.of(new TableSnapshot(table,4)),4,clock.instant(),clock.instant(),cancelled?clock.instant():null);
        mongo.insert(row).block();ownIds.add(id);return row;
    }
    protected org.bson.Document insertLegacy(UUID owner){
        var id=new org.bson.types.ObjectId();var row=new org.bson.Document("_id",id).append("restaurantId",owner.toString()).append("customerName","Ejemplo")
            .append("customerEmail","privado@example.test").append("customerId","no-autenticado").append("status","PENDING");
        mongo.insert(row,"reservations").block();ownIds.add(id);return row;
    }
    @org.junit.jupiter.api.AfterEach void cleanQueries(){for(var id:ownIds)mongo.remove(Query.query(Criteria.where("_id").is(id)),"reservations").block();ownIds.clear();}
}
