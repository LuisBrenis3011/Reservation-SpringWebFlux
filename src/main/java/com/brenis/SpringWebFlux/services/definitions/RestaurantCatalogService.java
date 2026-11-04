package com.brenis.SpringWebFlux.services.definitions;

import com.brenis.SpringWebFlux.collections.RestaurantCollection;
import com.brenis.SpringWebFlux.enums.PriceEnum;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.List;

public interface RestaurantCatalogService {

    Flux<RestaurantCollection> readAll(Integer page, Integer size);

    Flux<RestaurantCollection> readByCuisineType(String cuisineType);

    Mono<RestaurantCollection> readByName(String name);

    Flux<RestaurantCollection> readByPriceRangeIn(List<PriceEnum> priceRanges);

    Flux<RestaurantCollection> readByCity(String city);

}
