package com.brenis.SpringWebFlux.services.definitions;

import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.TableCombinationRequest;
import com.brenis.SpringWebFlux.dtos.responses.*;
import reactor.core.publisher.Mono;
import java.security.Principal;
import java.util.UUID;

public interface TableCombinationService {
    Mono<RestaurantOperationCoordinator.Result<TableCombinationResponse>> create(
            Principal principal,UUID restaurantId,TableCombinationRequest request,CommandMetadata command);
    Mono<RestaurantOperationCoordinator.Result<TableCombinationResponse>> read(Principal principal,UUID restaurantId,UUID combinationId);
    Mono<RestaurantOperationCoordinator.Result<TableCombinationListResponse>> list(Principal principal,UUID restaurantId);
    Mono<RestaurantOperationCoordinator.Result<TableCombinationResponse>> replace(
            Principal principal,UUID restaurantId,UUID combinationId,TableCombinationRequest request,CommandMetadata command);
}
