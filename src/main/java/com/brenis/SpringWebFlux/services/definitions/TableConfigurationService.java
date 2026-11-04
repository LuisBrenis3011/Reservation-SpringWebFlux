package com.brenis.SpringWebFlux.services.definitions;

import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.TableCreateRequest;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import com.brenis.SpringWebFlux.dtos.responses.*;
import reactor.core.publisher.Mono;
import java.security.Principal;
import java.util.UUID;

public interface TableConfigurationService {
    Mono<RestaurantOperationCoordinator.Result<TableAvailabilityResponse>> create(
            Principal principal,UUID restaurantId,TableCreateRequest request,CommandMetadata command);
    Mono<RestaurantOperationCoordinator.Result<TableAvailabilityResponse>> read(
            Principal principal,UUID restaurantId,UUID tableId);
    Mono<RestaurantOperationCoordinator.Result<TableListResponse>> list(Principal principal,UUID restaurantId);
    Mono<RestaurantOperationCoordinator.Result<TableAvailabilityResponse>> patch(
            Principal principal,UUID restaurantId,UUID tableId,TablePatchRequest request,CommandMetadata command);
}

