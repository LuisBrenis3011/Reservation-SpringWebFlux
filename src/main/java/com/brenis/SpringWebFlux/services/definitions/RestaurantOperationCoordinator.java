package com.brenis.SpringWebFlux.services.definitions;
import java.time.Instant;
import java.util.UUID;
import java.util.function.Function;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
public interface RestaurantOperationCoordinator {
    record Context(UUID restaurantId,long revision,Instant now) {}
    record Result<T>(T body,long revision,int httpStatus,String location) {}
    record MutationOutcome<T>(T body,boolean businessChanged) {}
    <T> Mono<Result<T>> writeWithOutcome(UUID restaurantId,Class<T> responseType,CommandMetadata command,Function<Context,Mono<MutationOutcome<T>>> work);
    <T> Mono<Result<T>> write(UUID restaurantId,Class<T> responseType,CommandMetadata command,Function<Context,Mono<T>> work);
    <T> Mono<Result<T>> readSnapshot(UUID restaurantId,Function<Context,Mono<T>> work);
    <T> Mono<T> writeLegacy(UUID restaurantId,Function<Context,Mono<T>> work);
}

