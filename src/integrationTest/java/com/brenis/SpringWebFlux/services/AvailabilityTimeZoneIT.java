package com.brenis.SpringWebFlux.services;
import com.brenis.SpringWebFlux.support.*;
import com.brenis.SpringWebFlux.configs.RestaurantShiftIndexesContributor;
import com.brenis.SpringWebFlux.mappers.RestaurantShiftMapper;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.services.impls.RestaurantShiftServiceImpl;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.RestaurantTimeZoneRequest;
import com.brenis.SpringWebFlux.dtos.responses.RestaurantTimeZoneResponse;
import com.brenis.SpringWebFlux.repositories.RestaurantTimeZoneRepository;
import org.springframework.context.annotation.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.ContextConfiguration;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.bson.Document;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;
import java.util.*;
import static org.assertj.core.api.Assertions.*;
@ContextConfiguration(classes=AvailabilityTimeZoneIT.ZoneConfiguration.class)
class AvailabilityTimeZoneIT extends AvailabilityTableIntegrationSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false)
    @Import({RestaurantShiftIndexesContributor.class,RestaurantShiftServiceImpl.class,RestaurantShiftMapper.class,com.brenis.SpringWebFlux.validators.RestaurantShiftValidator.class})
    static class ZoneConfiguration {
        @Bean @Primary ControlledReader zoneReader(com.brenis.SpringWebFlux.repositories.LegacyReservationCommitmentAdapter delegate){return new ControlledReader(delegate);}
    }
    static class ControlledReader implements ReservationCommitmentReader {
        final ReservationCommitmentReader delegate;String mode="";
        ControlledReader(ReservationCommitmentReader delegate){this.delegate=delegate;}
        public Mono<CommitmentSummary> read(UUID owner,java.time.Instant now){
            if(mode.equals("fail"))return Mono.error(new com.brenis.SpringWebFlux.exceptions.AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Fallo controlado"));
            if(mode.equals("delay"))return Mono.<CommitmentSummary>never().timeout(java.time.Duration.ofMillis(20)).onErrorMap(e -> new com.brenis.SpringWebFlux.exceptions.AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Demora controlada",e));
            return delegate.read(owner,now);
        }
    }
    @Autowired ControlledReader reader;
    @AfterEach void resetControlledReader(){reader.mode="";}
    @Autowired RestaurantShiftService zones;
    @Autowired RestaurantTimeZoneRepository zoneRepository;
    Mono<RestaurantOperationCoordinator.Result<RestaurantTimeZoneResponse>> put(String key,String zone,long version){
        return zones.replaceZone(manager,restaurant,new RestaurantTimeZoneRequest(zone),new CommandMetadata(key,"PUT:zone:"+zone+":"+version,version,200,null));
    }
    @Test void zonaInicialRepeticionYReplaySinDefault(){
        var empty=zones.readZone(manager,restaurant).block();
        assertThat(empty.body().zoneId()).isNull();assertThat(revision()).isZero();
        var first=put("first","America/Lima",0).block();
        assertThat(first.body().zoneId()).isEqualTo("America/Lima");assertThat(first.revision()).isEqualTo(1);
        put("repeat","America/Lima",1).block();
        assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);
        assertThat(put("first","America/Lima",0).block()).isEqualTo(first);
        assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);
        StepVerifier.create(put("stale","America/Lima",0)).expectErrorMatches(e -> e.getMessage().contains("REVISION_MISMATCH")).verify();
        StepVerifier.create(put("first","UTC",0)).expectErrorMatches(e -> e.getMessage().contains("IDEMPOTENCY_CONFLICT")).verify();
    }
    @ParameterizedTest @ValueSource(strings={""," ","Not/AZone"})
    void zonaInvalidaNoPersiste(String zone){
        StepVerifier.create(put("invalid",zone,0)).expectErrorMatches(e -> e.getMessage().contains("VALIDATION_ERROR")).verify();
        assertThat(zoneRepository.findById(restaurant).block()).isNull();assertThat(revision()).isZero();assertThat(receiptCount()).isZero();
    }
    @Test void legadoConservaZonaYRevision(){
        put("before","America/Lima",0).block();
        var fixture=AvailabilityMongoFixture.unresolvedLegacy(restaurant,false,"CONFIRMED");
        mongo.insert(fixture,"reservations").block();
        var saved=mongo.findById(fixture.get("_id"),Document.class,"reservations").block();
        StepVerifier.create(put("blocked","UTC",1)).expectErrorMatches(e -> e.getMessage().contains("LEGACY_RESERVATION_BLOCK")).verify();
        assertThat(zones.readZone(manager,restaurant).block().body().zoneId()).isEqualTo("America/Lima");
        assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
        assertThat(mongo.findById(fixture.get("_id"),Document.class,"reservations").block()).isEqualTo(saved);
    }
    @Test void turnoPersistidoIncompletoRechazaCambioSinMutacion(){
        put("before","America/Lima",0).block();
        var shift=mongo.insert(new Document("_id",UUID.randomUUID()).append("restaurantId",restaurant),"restaurant_shifts").block();
        var stored=mongo.findById(shift.get("_id"),Document.class,"restaurant_shifts").block();
        StepVerifier.create(put("blocked","America/Lima",1)).expectErrorMatches(e -> e.getMessage().contains("COMMITMENT_CHECK_UNAVAILABLE")).verify();
        assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
        assertThat(zoneRepository.findById(restaurant).block().zoneId()).isEqualTo("America/Lima");
        assertThat(mongo.findById(shift.get("_id"),Document.class,"restaurant_shifts").block()).isEqualTo(stored);
    }
    @Test void reservaProtegidaBloqueaZona(){
        var snapshot=AvailabilityMongoFixture.confirmedSnapshot(restaurant,UUID.randomUUID(),UUID.randomUUID(),clock.instant().plusSeconds(600),clock.instant().plusSeconds(3600));
        mongo.insert(snapshot,"reservations").block();
        StepVerifier.create(put("protected","America/Lima",0)).expectErrorMatches(e -> e.getMessage().contains("PROTECTED_RESERVATION")).verify();
        assertThat(revision()).isZero();assertThat(receiptCount()).isZero();assertThat(zoneRepository.findById(restaurant).block()).isNull();
    }
    @ParameterizedTest @ValueSource(strings={"fail","delay"})
    void falloODemoraConservaZonaRevisionYPermiteReintentar(String mode){
        put("before","America/Lima",0).block();reader.mode=mode;
        try{StepVerifier.create(put("retry","UTC",1)).expectErrorMatches(e -> e.getMessage().contains("COMMITMENT_CHECK_UNAVAILABLE")).verify();}
        finally{reader.mode="";}
        assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
        assertThat(zoneRepository.findById(restaurant).block().zoneId()).isEqualTo("America/Lima");
        assertThat(put("retry","UTC",1).block().body().zoneId()).isEqualTo("UTC");
    }
    @Test void huerfanoBloqueaSinCrearZona(){
        var orphan=mongo.insert(new Document("_id",UUID.randomUUID()).append("status","CONFIRMED"),"reservations").block();
        try {
        var stored=mongo.findById(orphan.get("_id"),Document.class,"reservations").block();
        StepVerifier.create(put("orphan","America/Lima",0)).expectErrorMatches(e -> e.getMessage().contains("LEGACY_RESERVATION_BLOCK")).verify();
        assertThat(zoneRepository.findById(restaurant).block()).isNull();assertThat(revision()).isZero();assertThat(receiptCount()).isZero();
        assertThat(mongo.findById(orphan.get("_id"),Document.class,"reservations").block()).isEqualTo(stored);
        } finally {
            // Solo la fixture propia de este caso, en el Mongo efimero del IT.
            // Un huerfano conservado bloquearia tambien los restaurantes de otros casos.
            var removed=mongo.remove(org.springframework.data.mongodb.core.query.Query.query(
                org.springframework.data.mongodb.core.query.Criteria.where("_id").is(orphan.get("_id"))),"reservations").block();
            assertThat(removed.getDeletedCount()).isEqualTo(1);
        }
    }
}
