package com.brenis.SpringWebFlux.services.definitions;

import com.brenis.SpringWebFlux.collections.RestaurantCollection;
import com.brenis.SpringWebFlux.dtos.responses.RestaurantResponse;
import com.brenis.SpringWebFlux.enums.PriceEnum;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.List;

public interface RestaurantBusinessService {

    Flux<RestaurantResponse> readAll(Integer page, Integer size);

    Flux<RestaurantResponse> readByCuisineType(String cuisineType);

    Mono<RestaurantResponse> readByName(String name);

    Flux<RestaurantResponse> readByPriceRangeIn(List<PriceEnum> priceRanges);

    Flux<RestaurantResponse> readByCity(String city);
}
