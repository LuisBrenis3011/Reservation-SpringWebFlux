package com.brenis.SpringWebFlux.services.impls;

import com.brenis.SpringWebFlux.collections.*;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.TableCombinationRequest;
import com.brenis.SpringWebFlux.dtos.responses.*;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.mappers.TableCombinationMapper;
import com.brenis.SpringWebFlux.repositories.*;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.validators.TableCombinationValidator;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import reactor.core.publisher.*;
import java.security.Principal;
import java.util.*;

@Service
public class TableCombinationServiceImpl implements TableCombinationService {
    private final TableCombinationRepository repository;
    private final TableRepository tables;
    private final RestaurantOperationCoordinator coordinator;
    private final ReservationMutationGuard guard;
    private final RestaurantAccessPolicy access;
    private final TableCombinationValidator validator;
    private final TableCombinationMapper mapper;
    public TableCombinationServiceImpl(TableCombinationRepository repository,TableRepository tables,
            RestaurantOperationCoordinator coordinator,ReservationMutationGuard guard,RestaurantAccessPolicy access,
            TableCombinationValidator validator,TableCombinationMapper mapper) {
        this.repository=repository; this.tables=tables; this.coordinator=coordinator; this.guard=guard;
        this.access=access; this.validator=validator; this.mapper=mapper;
    }
    private Mono<List<TableCollection>> members(UUID owner,List<UUID> ids) {
        // Una sesion Mongo no debe ejecutar operaciones paralelas: preservar concatMap.
        return Flux.fromIterable(ids).concatMap(id -> tables.findByIdAndRestaurantId(id,owner)).collectList();
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<TableCombinationResponse>> create(
            Principal principal,UUID owner,TableCombinationRequest request,CommandMetadata headers) {
        return access.requireManager(principal,owner).then(Mono.defer(() -> {
            UUID id=UUID.randomUUID(); // estable durante todos los intentos del comando
            var command=new CommandMetadata(headers.idempotencyKey(),headers.fingerprint(),null,201,
                    "/catalog/restaurants/"+owner+"/table-combinations/"+id);
            return coordinator.write(owner,TableCombinationResponse.class,command,context -> Mono.defer(() -> {
                var selected=validator.validate(request);
                var row=new TableCombinationCollection(id,owner,selected.tableIds(),selected.memberKey());
                return members(owner,selected.tableIds()).flatMap(found -> {
                        validator.requireOwned(owner,selected,found);
                        var response=mapper.response(row,found,context.revision());
                        return guard.check(context,ReservationMutationGuard.MutationKind.CREATE_OPERATIONAL,null)
                                .then(repository.existsByRestaurantIdAndMemberKey(owner,selected.memberKey()))
                                .flatMap(duplicate -> duplicate
                                        ?Mono.<TableCombinationResponse>error(new AvailabilityException("DUPLICATE_COMBINATION","Conjunto ya registrado"))
                                        :repository.insert(row).thenReturn(response));
                    });
            })).onErrorMap(DuplicateKeyException.class,e ->
                            new AvailabilityException("DUPLICATE_COMBINATION","Conjunto ya registrado",e));
        }));
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<TableCombinationResponse>> read(
            Principal principal,UUID owner,UUID combinationId) {
        return access.requireManager(principal,owner).then(Mono.defer(() -> coordinator.readSnapshot(owner,context ->
                repository.findByIdAndRestaurantId(combinationId,owner)
                        .switchIfEmpty(Mono.error(new AvailabilityException("NOT_FOUND","Combinacion inexistente")))
                        .flatMap(row -> members(owner,row.tableIds()).map(found -> mapper.response(row,found,context.revision()))))));
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<TableCombinationListResponse>> list(Principal principal,UUID owner) {
        return access.requireManager(principal,owner).then(Mono.defer(() -> coordinator.readSnapshot(owner,context ->
                repository.findAllByRestaurantId(owner).collectList().flatMap(rows ->
                        tables.findAllByRestaurantId(owner).collectList().map(found -> mapper.list(rows,found,context.revision()))))));
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<TableCombinationResponse>> replace(
            Principal principal,UUID owner,UUID combinationId,TableCombinationRequest request,CommandMetadata headers) {
        return access.requireManager(principal,owner).then(Mono.defer(() -> {
            if(headers.expectedRevision()==null)
                return Mono.error(new AvailabilityException("INVALID_REQUEST","If-Match requerido"));
            var command=new CommandMetadata(headers.idempotencyKey(),headers.fingerprint(),headers.expectedRevision(),200,null);
            return coordinator.write(owner,TableCombinationResponse.class,command,context ->
                    repository.findByIdAndRestaurantId(combinationId,owner)
                            .switchIfEmpty(Mono.error(new AvailabilityException("NOT_FOUND","Combinacion inexistente")))
                            .flatMap(current -> {
                                var selected=validator.validate(request);
                                var updated=new TableCombinationCollection(current.id(),current.restaurantId(),selected.tableIds(),selected.memberKey());
                                boolean changed=!current.tableIds().equals(selected.tableIds());
                                // Un PUT equivalente conserva integrantes pero sigue comprobando
                                // legado/fallos. Solo un cambio efectivo exige proteccion de miembros.
                                var kind=changed?ReservationMutationGuard.MutationKind.COMBINATION_MEMBERS
                                        :ReservationMutationGuard.MutationKind.CREATE_OPERATIONAL;
                                return members(owner,selected.tableIds()).flatMap(found -> {
                                    validator.requireOwned(owner,selected,found);
                                    var response=mapper.response(updated,found,context.revision());
                                    return guard.check(context,kind,current.id())
                                            .then(repository.existsByRestaurantIdAndMemberKeyAndIdNot(owner,selected.memberKey(),current.id()))
                                            .flatMap(duplicate -> duplicate
                                                    ?Mono.<TableCombinationResponse>error(new AvailabilityException("DUPLICATE_COMBINATION","Conjunto ya registrado"))
                                                    :repository.save(updated).thenReturn(response));
                                });
                            })).onErrorMap(DuplicateKeyException.class,e ->
                                    new AvailabilityException("DUPLICATE_COMBINATION","Conjunto ya registrado",e));
        }));
    }
}
