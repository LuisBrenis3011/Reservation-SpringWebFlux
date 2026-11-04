package com.brenis.SpringWebFlux.support;

import com.brenis.SpringWebFlux.collections.*;
import com.brenis.SpringWebFlux.configs.*;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.TableCreateRequest;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import com.brenis.SpringWebFlux.dtos.responses.TableAvailabilityResponse;
import com.brenis.SpringWebFlux.mappers.TableAvailabilityMapper;
import com.brenis.SpringWebFlux.repositories.TableRepository;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.services.impls.*;
import com.brenis.SpringWebFlux.validators.TableConfigurationValidator;
import org.bson.Document;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.*;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;
import java.security.Principal;
import java.util.UUID;
import reactor.core.publisher.Mono;
import static org.springframework.data.mongodb.core.query.Criteria.where;
import static org.springframework.data.mongodb.core.query.Query.query;

@SpringJUnitConfig(AvailabilityTableIntegrationSupport.Configuration.class)
public abstract class AvailabilityTableIntegrationSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false)
    @Import({AvailabilityIntegrationConfiguration.class,TableIndexesContributor.class,
            TableConfigurationServiceImpl.class,TableConfigurationValidator.class,
            TableAvailabilityMapper.class,RestaurantAccessPolicy.class})
    public static class Configuration {}
    @Autowired protected TableConfigurationService tables;
    @Autowired protected TableRepository repository;
    @Autowired protected ReactiveMongoTemplate mongo;
    @Autowired protected RestaurantOperationCoordinator coordinator;
    @Autowired protected AvailabilityClockFixture clock;
    protected UUID restaurant;
    protected Principal manager;
    @BeforeEach void prepareTableOwner() {
        restaurant=UUID.randomUUID();
        mongo.save(RestaurantCollection.builder().id(restaurant).name("Salón").capacity(5).build()).block();
        manager=new JwtAuthenticationToken(AvailabilityIdentityFixture.managerJwt(restaurant,clock));
    }
    protected CommandMetadata command(String key,String label,long capacity) {
        return new CommandMetadata(key,"POST:/restaurants/"+restaurant+"/tables:"+label+":"+capacity,null,201,null);
    }
    protected Mono<RestaurantOperationCoordinator.Result<TableAvailabilityResponse>> create(String key,String label,long capacity) {
        return tables.create(manager,restaurant,new TableCreateRequest(label,capacity),command(key,label,capacity));
    }
    protected Mono<RestaurantOperationCoordinator.Result<TableAvailabilityResponse>> patch(
            UUID table,String key,TablePatchRequest request,long expectedRevision) {
        var metadata=new CommandMetadata(key,"PATCH:/restaurants/"+restaurant+"/tables/"+table+":"+
                request.label()+":"+request.capacity()+":"+expectedRevision,expectedRevision,200,null);
        return tables.patch(manager,restaurant,table,request,metadata);
    }
    protected long revision() {
        Document state=mongo.findById(restaurant,Document.class,"restaurant_operations").block();
        return state==null?0:((Number)state.get("revision")).longValue();
    }
    protected long receiptCount() {
        return mongo.count(query(where("restaurantId").is(restaurant)),"operation_receipts").block();
    }
}

