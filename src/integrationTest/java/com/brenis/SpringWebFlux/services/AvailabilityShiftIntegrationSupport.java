package com.brenis.SpringWebFlux.services;
import com.brenis.SpringWebFlux.support.*;
import com.brenis.SpringWebFlux.configs.RestaurantShiftIndexesContributor;
import com.brenis.SpringWebFlux.services.impls.RestaurantShiftServiceImpl;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.mappers.RestaurantShiftMapper;
import com.brenis.SpringWebFlux.validators.RestaurantShiftValidator;
import com.brenis.SpringWebFlux.repositories.RestaurantShiftRepository;
import com.brenis.SpringWebFlux.dtos.requests.*;
import com.brenis.SpringWebFlux.dtos.responses.RestaurantShiftResponse;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import org.springframework.context.annotation.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.ContextConfiguration;
import org.junit.jupiter.api.*;
import reactor.core.publisher.Mono;
import java.time.*;
@ContextConfiguration(classes=AvailabilityShiftIntegrationSupport.ShiftConfiguration.class)
abstract class AvailabilityShiftIntegrationSupport extends AvailabilityTableIntegrationSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false)
    @Import({RestaurantShiftIndexesContributor.class,RestaurantShiftServiceImpl.class,RestaurantShiftMapper.class,RestaurantShiftValidator.class})
    static class ShiftConfiguration {
        @Bean @Primary AvailabilityTimeZoneIT.ControlledReader shiftReader(com.brenis.SpringWebFlux.repositories.LegacyReservationCommitmentAdapter delegate){return new AvailabilityTimeZoneIT.ControlledReader(delegate);}
    }
    @Autowired RestaurantShiftService shifts;
    @Autowired RestaurantShiftRepository shiftRepository;
    @Autowired AvailabilityTimeZoneIT.ControlledReader reader;
    @BeforeEach void prepareZone(){clock.set(Instant.parse("2026-11-01T10:00:00Z"));reader.mode="";shifts.replaceZone(manager,restaurant,new RestaurantTimeZoneRequest("America/Lima"),new CommandMetadata("zone","zone",0L,200,null)).block();}
    @AfterEach void resetShiftReader(){reader.mode="";clock.set(Instant.parse("2026-11-01T10:00:00Z"));}
    Mono<RestaurantOperationCoordinator.Result<RestaurantShiftResponse>> edit(java.util.UUID id,String key,String start,String end,long version){return shifts.replace(manager,restaurant,id,new RestaurantShiftRequest(start,end),new CommandMetadata(key,"edit:"+id+":"+start+":"+end+":"+version,version,200,null));}
    Mono<RestaurantOperationCoordinator.Result<RestaurantShiftResponse>> createShift(String key,String start,String end){return shifts.create(manager,restaurant,new RestaurantShiftRequest(start,end),new CommandMetadata(key,"POST:shift:"+start+":"+end,null,201,null));}
}
