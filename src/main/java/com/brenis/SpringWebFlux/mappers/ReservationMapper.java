package com.brenis.SpringWebFlux.mappers;

import com.brenis.SpringWebFlux.collections.ReservationCollection;
import com.brenis.SpringWebFlux.dtos.requests.ReservationRequest;
import com.brenis.SpringWebFlux.dtos.responses.ReservationResponse;
import org.mapstruct.AfterMapping;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.MappingTarget;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@Mapper(componentModel = "spring")
public interface ReservationMapper {

    @Mapping(target = "dateTime", expression = "java(collection.getDate() + \",\" + collection.getTime())")
    ReservationResponse toResponse(ReservationCollection collection);

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "date", ignore = true)
    @Mapping(target = "time", ignore = true)
    @Mapping(target = "status", ignore = true)
    @Mapping(target = "notes", source = "comment", defaultValue = "")
    ReservationCollection toCollection(ReservationRequest request);

    default Flux<ReservationResponse> toResponseFlux(Flux<ReservationCollection> collections) {
        return collections.map(this::toResponse);
    }

    default Mono<ReservationResponse> toResponseMono(Mono<ReservationCollection> collection) {
        return collection.map(this::toResponse);
    }

    default  Flux<ReservationCollection> toCollectionFlux(Flux<ReservationRequest> requests){
        return requests.map(this::toCollection);
    }

    default Mono<ReservationCollection> toCollectionMono(Mono<ReservationRequest> request) {
        return request.map(this::toCollection);
    }

    @AfterMapping
    default void splitDateTime(ReservationRequest request, @MappingTarget ReservationCollection collection) {
        if (request.getDateTime() != null && request.getDateTime().contains(",")) {
            String[] parts = request.getDateTime().split(",");
            collection.setDate(parts[0]);
            collection.setTime(parts[1]);
        }
    }
}
