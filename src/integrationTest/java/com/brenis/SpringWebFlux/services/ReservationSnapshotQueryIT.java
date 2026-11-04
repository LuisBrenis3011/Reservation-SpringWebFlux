package com.brenis.SpringWebFlux.services;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.mongodb.ReactiveMongoDatabaseFactory;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.transaction.reactive.TransactionalOperator;
import reactor.core.publisher.Flux;
import com.brenis.SpringWebFlux.support.ReservationQueryIntegrationSupport;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection.TableSnapshot;
import com.brenis.SpringWebFlux.configs.AvailabilityProperties;
import com.brenis.SpringWebFlux.mappers.ManagedReservationMapper;
import com.brenis.SpringWebFlux.repositories.LegacyReservationQueryRepository;
import com.brenis.SpringWebFlux.services.impls.*;
import static org.assertj.core.api.Assertions.*;
class ReservationSnapshotQueryIT extends ReservationQueryIntegrationSupport {
    @Autowired ReactiveMongoDatabaseFactory factory;
    @Autowired TransactionalOperator tx;
    @Autowired ReservationAccessPolicy access;
    @Autowired ManagedReservationMapper mapper;
    @Autowired AvailabilityProperties properties;
    @Autowired com.brenis.SpringWebFlux.repositories.LegacyReservationCommitmentAdapter commitments;
    @Test void snapshotHistoricoYCanceladaConservanEstado(){
        var original=insertManaged(restaurant,"client",true);
        mongo.insert(new com.brenis.SpringWebFlux.collections.RestaurantTimeZoneCollection(restaurant,"America/Lima")).block();
        try{
            var response=queries.managed(customer("client"),restaurant,original.id()).block();
            assertThat(response.status()).isEqualTo("CANCELLED");assertThat(response.zoneId()).isEqualTo("UTC");
            assertThat(response.startInstant()).isEqualTo(original.startInstant());assertThat(response.tableIds()).isEqualTo(original.tableIds());
            assertThat(commitments.read(restaurant,clock.instant()).block().protectedTableIds()).doesNotContain(original.tableIds().getFirst());
            assertThat(mongo.findById(original.id(),ManagedReservationCollection.class).block()).isEqualTo(original);
        }finally{mongo.remove(Query.query(org.springframework.data.mongodb.core.query.Criteria.where("_id").is(restaurant)),"restaurant_time_zones").block();}
    }
    @Test void paginaMultilocalNoMezclaEscrituraCompetidora(){
        var first=insertManaged(restaurant,"client",false);var second=insertManaged(UUID.randomUUID(),"client",false);
        insertManaged(UUID.randomUUID(),"other",false);
        var id=UUID.fromString("ffffffff-ffff-ffff-ffff-ffffffffffff");var table=UUID.randomUUID();
        var concurrent=new ManagedReservationCollection(id,2,UUID.randomUUID(),UUID.randomUUID(),List.of(table),null,
            first.customerIssuer(),first.customerSubject(),2,"",first.status(),1,first.localStart(),first.localEnd(),first.zoneId(),
            first.startInstant(),first.endInstant(),List.of(new TableSnapshot(table,4)),4,first.createdAt(),first.updatedAt(),null);
        ownIds.add(id);var inserted=new AtomicBoolean();
        var controlled=new ReactiveMongoTemplate(factory){
            @Override public <T> Flux<T> find(Query query,Class<T> type,String collection){
                query.cursorBatchSize(1);
                return super.find(query,type,collection).concatMap(value->{
                    if(!inserted.compareAndSet(false,true))return reactor.core.publisher.Mono.just(value);
                    // Escritura fuera del contexto transaccional del lector, entre elementos del cursor.
                    return mongo.insert(concurrent).contextWrite(context->reactor.util.context.Context.empty()).thenReturn(value);
                });
            }
        };
        var query=new ReservationQueryServiceImpl(controlled,tx,access,mapper,new LegacyReservationQueryRepository(controlled),properties);
        var result=query.mine(customer("client"),0,20,null).block();
        assertThat(inserted).isTrue();assertThat(result.items()).hasSize(2);
        assertThat(mongo.findById(id,ManagedReservationCollection.class).block()).isNotNull();
        assertThat(queries.mine(customer("client"),0,20,null).block().items()).hasSize(3);
        assertThat(mongo.exists(Query.query(org.springframework.data.mongodb.core.query.Criteria.where("_id").is(restaurant)),"restaurant_operations").block()).isFalse();
        assertThat(receiptCount()).isZero();
    }
}
