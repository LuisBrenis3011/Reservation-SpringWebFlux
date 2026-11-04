package com.brenis.SpringWebFlux.services.impls;

import com.brenis.SpringWebFlux.collections.TableCollection;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.TableCreateRequest;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import com.brenis.SpringWebFlux.dtos.responses.*;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.mappers.TableAvailabilityMapper;
import com.brenis.SpringWebFlux.repositories.TableRepository;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.validators.TableConfigurationValidator;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import java.security.Principal;
import java.util.UUID;
import static com.brenis.SpringWebFlux.services.impls.ReservationMutationGuard.MutationKind.CREATE_OPERATIONAL;
import static com.brenis.SpringWebFlux.services.impls.ReservationMutationGuard.MutationKind.LABEL_ONLY;
import static com.brenis.SpringWebFlux.services.impls.ReservationMutationGuard.MutationKind.TABLE_CAPACITY;

@Service
public class TableConfigurationServiceImpl implements TableConfigurationService {
    private final TableRepository repository;
    private final RestaurantOperationCoordinator coordinator;
    private final ReservationMutationGuard guard;
    private final RestaurantAccessPolicy access;
    private final TableConfigurationValidator validator;
    private final TableAvailabilityMapper mapper;
    public TableConfigurationServiceImpl(TableRepository repository,RestaurantOperationCoordinator coordinator,
            ReservationMutationGuard guard,RestaurantAccessPolicy access,TableConfigurationValidator validator,
            TableAvailabilityMapper mapper) {
        this.repository=repository; this.coordinator=coordinator; this.guard=guard;
        this.access=access; this.validator=validator; this.mapper=mapper;
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<TableAvailabilityResponse>> create(
            Principal principal,UUID owner,TableCreateRequest request,CommandMetadata headers) {
        return access.requireManager(principal,owner).then(Mono.defer(() -> {
            // Fuera del callback transaccional: estable en todos sus intentos.
            UUID id=UUID.randomUUID();
            var command=new CommandMetadata(headers.idempotencyKey(),headers.fingerprint(),null,201,
                    "/catalog/restaurants/"+owner+"/tables/"+id);
            return coordinator.write(owner,TableAvailabilityResponse.class,command,context -> Mono.defer(() -> {
                var input=validator.validate(request);
                return guard.check(context,CREATE_OPERATIONAL,null)
                    .then(repository.existsByRestaurantIdAndLabelKey(owner,input.labelKey()))
                    .flatMap(duplicate -> duplicate
                        ?Mono.<TableAvailabilityResponse>error(new AvailabilityException("DUPLICATE_LABEL","Etiqueta ya registrada"))
                        :repository.findAllByRestaurantId(owner).map(TableCollection::capacity)
                            .reduce(0L,validator::addCapacity)
                            .flatMap(total -> {
                                validator.addCapacity(total,input.capacity());
                                return repository.insert(new TableCollection(id,owner,input.label(),input.labelKey(),input.capacity()))
                                        .map(saved -> mapper.table(saved,context.revision()));
                            }));
            }))
                .onErrorMap(DuplicateKeyException.class,e ->
                        new AvailabilityException("DUPLICATE_LABEL","Etiqueta ya registrada",e));
        }));
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<TableAvailabilityResponse>> read(
            Principal principal,UUID owner,UUID tableId) {
        return access.requireManager(principal,owner).then(Mono.defer(() ->
            coordinator.readSnapshot(owner,context -> repository.findByIdAndRestaurantId(tableId,owner)
                .switchIfEmpty(Mono.error(new AvailabilityException("NOT_FOUND","Mesa inexistente")))
                .map(table -> mapper.table(table,context.revision())))));
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<TableListResponse>> list(Principal principal,UUID owner) {
        return access.requireManager(principal,owner).then(Mono.defer(() ->
            coordinator.readSnapshot(owner,context -> repository.findAllByRestaurantId(owner).collectList()
                    .map(tables -> mapper.list(tables,context.revision())))));
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<TableAvailabilityResponse>> patch(
            Principal principal,UUID owner,UUID tableId,TablePatchRequest request,CommandMetadata headers) {
        return access.requireManager(principal,owner).then(Mono.defer(() -> {
            if(headers.expectedRevision()==null)
                return Mono.error(new AvailabilityException("INVALID_REQUEST","If-Match requerido"));
            var command=new CommandMetadata(headers.idempotencyKey(),headers.fingerprint(),headers.expectedRevision(),200,null);
            return coordinator.write(owner,TableAvailabilityResponse.class,command,context ->
                repository.findByIdAndRestaurantId(tableId,owner)
                    .switchIfEmpty(Mono.error(new AvailabilityException("NOT_FOUND","Mesa inexistente")))
                    .flatMap(current -> {
                        var updated=validator.patch(current,request);
                        boolean capacityChanged=updated.capacity()!=current.capacity();
                        var unique=updated.labelKey().equals(current.labelKey())?Mono.just(false):
                                repository.existsByRestaurantIdAndLabelKey(owner,updated.labelKey());
                        return guard.check(context,capacityChanged?TABLE_CAPACITY:LABEL_ONLY,tableId)
                            .then(unique).flatMap(duplicate -> {
                                if(duplicate) return Mono.error(new AvailabilityException("DUPLICATE_LABEL","Etiqueta ya registrada"));
                                Mono<Void> totalCheck=capacityChanged
                                    ?repository.findAllByRestaurantId(owner).filter(table -> !table.id().equals(tableId))
                                        .map(TableCollection::capacity).reduce(0L,validator::addCapacity)
                                        .doOnNext(total -> validator.addCapacity(total,updated.capacity())).then()
                                    :Mono.empty();
                                return totalCheck.then(Mono.defer(() -> repository.save(updated)))
                                        .map(saved -> mapper.table(saved,context.revision()));
                            });
                    }))
                .onErrorMap(DuplicateKeyException.class,e ->
                        new AvailabilityException("DUPLICATE_LABEL","Etiqueta ya registrada",e));
        }));
    }
}

