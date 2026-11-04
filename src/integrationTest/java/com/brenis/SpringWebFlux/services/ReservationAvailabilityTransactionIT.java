package com.brenis.SpringWebFlux.services;
import java.util.*;
import java.util.concurrent.atomic.*;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.mongodb.ReactiveMongoDatabaseFactory;
import org.springframework.data.mongodb.core.query.*;
import org.springframework.transaction.reactive.*;
import reactor.core.publisher.*;
import com.brenis.SpringWebFlux.support.ReservationAvailabilityIntegrationSupport;
import com.brenis.SpringWebFlux.repositories.*;
import com.brenis.SpringWebFlux.services.impls.*;
import com.brenis.SpringWebFlux.validators.ReservationTimePolicy;
import com.brenis.SpringWebFlux.configs.AvailabilityProperties;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class ReservationAvailabilityTransactionIT extends ReservationAvailabilityIntegrationSupport {
    @Autowired RestaurantRepository restaurants;
    @Autowired RestaurantShiftRepository shifts;
    @Autowired TableRepository tables;
    @Autowired TableCombinationRepository combinations;
    @Autowired ReservationAssignmentPolicy assignment;
    @Autowired ReservationTimePolicy time;
    @Autowired TransactionalOperator transactions;
    @Autowired ReactiveMongoDatabaseFactory factory;
    @Autowired AvailabilityProperties properties;
    private ReservationAvailabilityServiceImpl service(RestaurantShiftRepository offer,ReservationOccupancyReader reader){
        return new ReservationAvailabilityServiceImpl(restaurants,offer,tables,combinations,reader,assignment,time,transactions,clock,properties);
    }
    @Test void errorMongoEnOcupacionAbortaYFallbackUsaOtraSesion(){
        var reader=mock(ReservationOccupancyReader.class);var offer=mock(RestaurantShiftRepository.class);
        var sessions=new java.util.concurrent.CopyOnWriteArrayList<Object>();var databaseFailed=new AtomicBoolean();
        when(offer.findAllByRestaurantId(restaurant)).thenAnswer(call->TransactionSynchronizationManager.forCurrentTransaction().flatMapMany(manager->{
            sessions.add(manager.getResource(factory));return shifts.findAllByRestaurantId(restaurant);
        }));
        when(reader.read(eq(restaurant),eq(shift),isNull(),eq(clock.instant()))).thenAnswer(call->{
            // La colección restaurants contiene la fixture; dividir entre cero falla en el servidor dentro de la sesión.
            var divide=new Document("$divide",List.of(1,0));
            var expression=new Document("$eq",List.of(divide,1));
            var query=Query.query(Criteria.where("$expr").is(expression));
            return mongo.findOne(query,Document.class,"restaurants").doOnError(error->databaseFailed.set(true))
                .then(Mono.<ReservationOccupancyReader.Occupancy>error(new AssertionError("Mongo debía rechazar la consulta")));
        });
        var result=service(offer,reader).list(restaurant,day(),2).block();
        assertThat(databaseFailed).isTrue();assertThat(sessions).hasSize(2);
        assertThat(sessions.get(0)).isNotSameAs(sessions.get(1));
        assertThat(result.items().getFirst().availability()).isEqualTo("UNDETERMINED");
        assertThat(result.items().getFirst().reservable()).isFalse();assertThat(revision()).isZero();assertThat(receiptCount()).isZero();
        verify(reader,times(1)).read(eq(restaurant),eq(shift),isNull(),eq(clock.instant()));
    }
    @Test void ofertaInicialFallidaRechazaSinInventarLista(){
        var reader=mock(ReservationOccupancyReader.class);var offer=mock(RestaurantShiftRepository.class);
        when(offer.findAllByRestaurantId(restaurant)).thenReturn(Flux.error(new IllegalStateException("oferta caida")));
        assertThatThrownBy(()->service(offer,reader).list(restaurant,day(),2).block()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");
        verifyNoInteractions(reader);assertThat(revision()).isZero();assertThat(receiptCount()).isZero();
    }
    @Test void ofertaDeFallbackFallidaRechazaSinInventarLista(){
        var reader=mock(ReservationOccupancyReader.class);var offer=mock(RestaurantShiftRepository.class);var calls=new AtomicInteger();
        when(offer.findAllByRestaurantId(restaurant)).thenAnswer(call->Flux.defer(()->calls.incrementAndGet()==1?
            shifts.findAllByRestaurantId(restaurant):Flux.error(new IllegalStateException("oferta caida"))));
        when(reader.read(eq(restaurant),eq(shift),isNull(),eq(clock.instant()))).thenReturn(Mono.error(new IllegalStateException("ocupacion caida")));
        assertThatThrownBy(()->service(offer,reader).list(restaurant,day(),2).block()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");
        assertThat(calls).hasValue(2);assertThat(revision()).isZero();assertThat(receiptCount()).isZero();
    }
}
