package com.brenis.SpringWebFlux.services.definitions;
import com.brenis.SpringWebFlux.dtos.requests.RestaurantShiftRequest;
import com.brenis.SpringWebFlux.dtos.responses.RestaurantShiftResponse;
import com.brenis.SpringWebFlux.dtos.responses.RestaurantShiftListResponse;
import java.security.Principal;
import java.util.UUID;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.RestaurantTimeZoneRequest;
import com.brenis.SpringWebFlux.dtos.responses.RestaurantTimeZoneResponse;
public interface RestaurantShiftService {
    Mono<RestaurantOperationCoordinator.Result<RestaurantShiftResponse>> replace(Principal actor,UUID owner,UUID shiftId,RestaurantShiftRequest request,CommandMetadata command);
    Mono<RestaurantOperationCoordinator.Result<RestaurantShiftResponse>> create(Principal actor,UUID owner,RestaurantShiftRequest request,CommandMetadata command);
    Mono<RestaurantOperationCoordinator.Result<RestaurantShiftResponse>> read(Principal actor,UUID owner,UUID shiftId);
    Mono<RestaurantOperationCoordinator.Result<RestaurantShiftListResponse>> list(Principal actor,UUID owner);
    Mono<RestaurantOperationCoordinator.Result<RestaurantTimeZoneResponse>> readZone(Principal actor,UUID owner);
    Mono<RestaurantOperationCoordinator.Result<RestaurantTimeZoneResponse>> replaceZone(Principal actor,UUID owner,RestaurantTimeZoneRequest request,CommandMetadata command);
}
