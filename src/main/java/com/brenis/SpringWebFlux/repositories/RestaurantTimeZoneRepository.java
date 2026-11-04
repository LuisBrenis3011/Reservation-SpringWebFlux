package com.brenis.SpringWebFlux.repositories;
import java.util.UUID;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import com.brenis.SpringWebFlux.collections.RestaurantTimeZoneCollection;
public interface RestaurantTimeZoneRepository extends ReactiveMongoRepository<RestaurantTimeZoneCollection,UUID> {}
