package com.brenis.SpringWebFlux.handlers;

import com.brenis.SpringWebFlux.dtos.responses.RestaurantResponse;
import com.brenis.SpringWebFlux.enums.PriceEnum;
import com.brenis.SpringWebFlux.services.definitions.RestaurantBusinessService;
import com.brenis.SpringWebFlux.services.definitions.RestaurantCatalogService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.ServerRequest;
import org.springframework.web.reactive.function.server.ServerResponse;
import reactor.core.publisher.Mono;

import java.util.Arrays;
import java.util.Objects;

@Component
@RequiredArgsConstructor
public class RestaurantCatalogHandler {

    private final RestaurantBusinessService restaurantBusinessService;

    public Mono<ServerResponse> getAllRestaurants(ServerRequest serverRequest) {

        final Integer page = Integer.parseInt(serverRequest.queryParam("page").orElse("0"));
        final Integer size = Integer.parseInt(serverRequest.queryParam("size").orElse("10"));

        final var restauranFlux = this.restaurantBusinessService.readAll(page, size);

        return ServerResponse.ok()
                .contentType(MediaType.APPLICATION_JSON)
                .body(restauranFlux, RestaurantResponse.class)
                .switchIfEmpty(ServerResponse.notFound().build());
    }

    public Mono<ServerResponse> getRestaurantByName(ServerRequest serverRequest) {
        final var restaurantName = serverRequest.pathVariable("name");
        final var monoResponse = this.restaurantBusinessService.readByName(restaurantName);

        return monoResponse
                .flatMap(restaurantResponse ->  ServerResponse.ok()
                        .contentType(MediaType.APPLICATION_JSON)
                        .bodyValue(restaurantResponse))
                .switchIfEmpty(ServerResponse.notFound().build());
    }

    public Mono<ServerResponse> getRestaurantsByCousinType(ServerRequest serverRequest) {
        final var cousinType = serverRequest.queryParam("cousinType").orElse(null);

        if (Objects.isNull(cousinType)) {
            return ServerResponse.badRequest().bodyValue("cousinType is required");
        }

        final var fluxResponse = this.restaurantBusinessService.readByCuisineType(cousinType);

        return ServerResponse.ok()
                .contentType(MediaType.APPLICATION_JSON)
                .body(fluxResponse, RestaurantResponse.class)
                .switchIfEmpty(ServerResponse.notFound().build());
    }

    public Mono<ServerResponse> getRestaurantBetweenPrice(ServerRequest serverRequest) {
        final var prices = serverRequest.queryParam("prices").orElse(null);

        if (Objects.isNull(prices)) {
            return ServerResponse.badRequest().bodyValue("cousinTypes is required");
        }

        final var typesList = Arrays.stream(prices.split(","))
                .map(String::trim)
                .map(String::toUpperCase)
                .map(PriceEnum::valueOf)
                .toList();

        final var fluxResponse = this.restaurantBusinessService.readByPriceRangeIn(typesList);

        return ServerResponse.ok()
                .contentType(MediaType.APPLICATION_JSON)
                .body(fluxResponse, RestaurantResponse.class)
                .switchIfEmpty(ServerResponse.notFound().build());
    }

    public Mono<ServerResponse> getRestaurantsByCity(ServerRequest serverRequest) {
        final var city = serverRequest.queryParam("city").orElse(null);

        if (Objects.isNull(city)) {
            return ServerResponse.badRequest()
                    .bodyValue("city is required");
        }

        final var fluxRestaurants = this.restaurantBusinessService.readByCity(city);

        return ServerResponse.ok()
                .contentType(MediaType.APPLICATION_JSON)
                .body(fluxRestaurants, RestaurantResponse.class)
                .switchIfEmpty(ServerResponse.noContent().build());
    }

}
