package com.brenis.SpringWebFlux.services.impls;

import com.brenis.SpringWebFlux.dtos.responses.RestaurantResponse;
import com.brenis.SpringWebFlux.enums.PriceEnum;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.ReactiveRedisTemplate;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.List;
import java.util.stream.Collectors;

@Service
@Slf4j
@RequiredArgsConstructor
public class CatalogCacheService {

    private final ReactiveRedisTemplate<String, RestaurantResponse> redisTemplate;
    private final ReactiveRedisTemplate<String, List<RestaurantResponse>> redisListTemplate;

    private static final Duration DEFAULT_TTL = Duration.ofHours(1);
    private static final String KEY_PREFIX = "restaurant:";

    public Mono<RestaurantResponse> getCacheRestaurant(String key) {
        return this.redisTemplate
                .opsForValue().get(key)
                .doOnNext(restaurantResponse -> log.info("Get cached restaurant " + restaurantResponse.getName()))
                .doOnSubscribe(subscription -> log.info("Looking restaurant with key: {}", key));
    }


    public Flux<RestaurantResponse> getCacheRestaurants(String key) {
        return redisListTemplate.opsForValue()
                .get(KEY_PREFIX + key)
                .flatMapMany(Flux::fromIterable)
                .doOnNext(response -> log.debug("Cache hit for list key: {}", key))
                .doOnSubscribe(s -> log.debug("Looking in cache for list key: {}", key));
    }

    public Mono<RestaurantResponse> cacheRestaurant(String key, RestaurantResponse restaurant) {
        return this.redisTemplate
                .opsForValue()
                .set(KEY_PREFIX + key, restaurant, DEFAULT_TTL)
                .thenReturn(restaurant)
                .doOnSubscribe(subscription -> log.info("Cache restaurant {}", restaurant.getName()));
    }

    public Flux<RestaurantResponse> cacheRestaurants(String key, Flux<RestaurantResponse> restaurants) {
        return restaurants.collectList()
                .flatMap(list -> redisListTemplate.opsForValue()
                        .set(KEY_PREFIX + key, list, DEFAULT_TTL)
                        .thenReturn(list))
                .flatMapMany(Flux::fromIterable)
                .doOnComplete(() -> log.debug("Cached restaurant list with key: {}", key));
    }

    public Mono<Boolean> evictCacheRestaurant(String key) {
        return this.redisTemplate
                .delete(KEY_PREFIX + key)
                .map(count -> count > 0)
                .doOnNext(isDeleted -> {
                    if (isDeleted)
                        log.info("Cache evicted restaurant with key: {}", key);
                });
    }

    public Mono<Void> evictCacheAllRestaurant() {
        return this.redisTemplate.getConnectionFactory()
                .getReactiveConnection()
                .serverCommands()
                .flushAll()
                .then(Mono.fromRunnable(() -> log.info("Cache evicted all restaurants")));
    }

    public static String buildNameKey(String name) {
        return "name:" + name.toLowerCase();
    }

    public static String buildCuisineTypeKey(String cuisineType) {
        return "cuisine:" + cuisineType.toLowerCase();
    }

    public static String buildCityKey(String city) {
        return "city:" + city.toLowerCase();
    }

    public static String buildPriceKey(List<PriceEnum> prices) {
        String pricesList = prices.stream()
                .map(PriceEnum::toString)
                .sorted()
                .collect(Collectors.joining(","));

        return "price:" + pricesList;
    }
}