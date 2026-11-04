package com.brenis.SpringWebFlux.support;

import com.brenis.SpringWebFlux.configs.TableCombinationIndexesContributor;
import com.brenis.SpringWebFlux.collections.TableCombinationCollection;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.TableCombinationRequest;
import com.brenis.SpringWebFlux.dtos.responses.TableCombinationResponse;
import com.brenis.SpringWebFlux.mappers.TableCombinationMapper;
import com.brenis.SpringWebFlux.repositories.TableCombinationRepository;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.services.impls.TableCombinationServiceImpl;
import com.brenis.SpringWebFlux.validators.TableCombinationValidator;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.*;
import org.springframework.test.context.ContextConfiguration;
import reactor.core.publisher.Mono;
import java.time.Instant;
import java.util.*;

/** Extiende la infraestructura propietaria; no crea Mongo, coordinador o fixtures alternativos. */
@ContextConfiguration(classes=AvailabilityCombinationIntegrationSupport.CombinationConfiguration.class)
public abstract class AvailabilityCombinationIntegrationSupport extends AvailabilityTableIntegrationSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false)
    @Import({TableCombinationIndexesContributor.class,TableCombinationServiceImpl.class,
            TableCombinationValidator.class,TableCombinationMapper.class})
    public static class CombinationConfiguration {}
    @Autowired protected TableCombinationService combinations;
    @Autowired protected TableCombinationRepository combinationRepository;
    protected UUID first,second;
    @BeforeEach void prepareMembers() {
        clock.set(Instant.parse("2026-11-01T10:00:00Z"));
        first=create("member-1","Uno",4).block().body().id();
        second=create("member-2","Dos",2).block().body().id();
    }
    protected TableCombinationRequest request(List<UUID> ids) { return new TableCombinationRequest(ids.stream().map(UUID::toString).toList()); }
    protected Mono<RestaurantOperationCoordinator.Result<TableCombinationResponse>> combine(String key,List<UUID> ids) {
        return combinations.create(manager,restaurant,request(ids),new CommandMetadata(key,
                "POST:/restaurants/"+restaurant+"/table-combinations:"+ids,null,201,null));
    }
    protected Mono<RestaurantOperationCoordinator.Result<TableCombinationResponse>> replace(
            UUID id,String key,List<UUID> ids,long expectedRevision) {
        return combinations.replace(manager,restaurant,id,request(ids),new CommandMetadata(key,
                "PUT:/restaurants/"+restaurant+"/table-combinations/"+id+":"+ids+":"+expectedRevision,
                expectedRevision,200,null));
    }
    protected List<TableCombinationCollection> storedCombinations() { return combinationRepository.findAllByRestaurantId(restaurant).collectList().block(); }
}
