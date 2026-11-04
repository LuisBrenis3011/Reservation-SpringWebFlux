package com.brenis.SpringWebFlux;

import com.brenis.SpringWebFlux.collections.RestaurantCollection;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;

import java.util.UUID;

public interface Repo extends ReactiveMongoRepository<RestaurantCollection, UUID> {
}
