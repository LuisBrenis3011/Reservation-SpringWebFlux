package com.brenis.SpringWebFlux.services.impls;
import com.brenis.SpringWebFlux.collections.RestaurantShiftCollection;
import com.brenis.SpringWebFlux.dtos.requests.RestaurantShiftRequest;
import com.brenis.SpringWebFlux.dtos.responses.RestaurantShiftResponse;
import com.brenis.SpringWebFlux.dtos.responses.RestaurantShiftListResponse;
import com.brenis.SpringWebFlux.repositories.RestaurantShiftRepository;
import com.brenis.SpringWebFlux.validators.RestaurantShiftValidator;
import java.security.Principal;
import java.util.UUID;
import java.time.*;
import org.bson.Document;
import org.springframework.stereotype.Service;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.*;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.collections.RestaurantTimeZoneCollection;
import com.brenis.SpringWebFlux.repositories.RestaurantTimeZoneRepository;
import com.brenis.SpringWebFlux.mappers.RestaurantShiftMapper;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.RestaurantTimeZoneRequest;
import com.brenis.SpringWebFlux.dtos.responses.RestaurantTimeZoneResponse;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
@Service
public class RestaurantShiftServiceImpl implements RestaurantShiftService {
    private final RestaurantTimeZoneRepository zones;
    private final RestaurantOperationCoordinator coordinator;
    private final ReservationMutationGuard guard;
    private final RestaurantAccessPolicy access;
    private final RestaurantShiftMapper mapper;
    private final ReactiveMongoTemplate mongo;
    private final RestaurantShiftRepository shifts;
    private final RestaurantShiftValidator validator;
    public RestaurantShiftServiceImpl(RestaurantTimeZoneRepository zones,RestaurantOperationCoordinator coordinator,ReservationMutationGuard guard,RestaurantAccessPolicy access,RestaurantShiftMapper mapper,ReactiveMongoTemplate mongo,RestaurantShiftRepository shifts,RestaurantShiftValidator validator){
        this.zones=zones;this.coordinator=coordinator;this.guard=guard;this.access=access;this.mapper=mapper;this.mongo=mongo;
        this.shifts=shifts;this.validator=validator;
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<RestaurantShiftResponse>> create(Principal actor,UUID owner,RestaurantShiftRequest request,CommandMetadata headers){
        return access.requireManager(actor,owner).then(Mono.defer(() -> {
            UUID id=UUID.randomUUID();
            var command=new CommandMetadata(headers.idempotencyKey(),headers.fingerprint(),null,201,"/catalog/restaurants/"+owner+"/shifts/"+id);
            return coordinator.write(owner,RestaurantShiftResponse.class,command,ctx ->
                zones.findById(owner).switchIfEmpty(Mono.error(new AvailabilityException("VALIDATION_ERROR","Configurar zona antes del turno")))
                .flatMap(zone -> {
                    var input=validator.validate(request,zone.zoneId(),ctx.now());
                    return guard.check(ctx,ReservationMutationGuard.MutationKind.CREATE_OPERATIONAL,null)
                        .then(shifts.findAllByRestaurantId(owner).collectList()).flatMap(existing -> {
                            if(existing.stream().anyMatch(row -> validator.overlaps(input,row)))return Mono.error(new AvailabilityException("SHIFT_OVERLAP","Intervalo superpuesto"));
                            var row=new RestaurantShiftCollection(id,owner,input.localStart(),input.localEnd(),input.zoneId(),input.startInstant(),input.endInstant());
                            return shifts.insert(row).map(saved -> mapper.shift(saved,ctx.revision()));
                        });
                }));
        }));
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<RestaurantShiftResponse>> read(Principal actor,UUID owner,UUID shiftId){
        return access.requireManager(actor,owner).then(Mono.defer(() -> coordinator.readSnapshot(owner,ctx -> shifts.findByIdAndRestaurantId(shiftId,owner)
            .switchIfEmpty(Mono.error(new AvailabilityException("NOT_FOUND","Turno inexistente"))).map(row -> mapper.shift(row,ctx.revision())))));
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<RestaurantShiftListResponse>> list(Principal actor,UUID owner){
        return access.requireManager(actor,owner).then(Mono.defer(() -> coordinator.readSnapshot(owner,ctx -> shifts.findAllByRestaurantId(owner).collectList().map(rows -> mapper.list(rows,ctx.revision())))));
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<RestaurantTimeZoneResponse>> readZone(Principal actor,UUID owner){
        return access.requireManager(actor,owner).then(Mono.defer(() -> coordinator.readSnapshot(owner,ctx ->
            zones.findById(owner).map(row -> mapper.zone(owner,row.zoneId(),ctx.revision())).defaultIfEmpty(mapper.zone(owner,null,ctx.revision())))));
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<RestaurantShiftResponse>> replace(Principal actor,UUID owner,UUID shiftId,RestaurantShiftRequest request,CommandMetadata headers){
        return access.requireManager(actor,owner).then(Mono.defer(() -> {
            if(headers.expectedRevision()==null)return Mono.error(new AvailabilityException("INVALID_REQUEST","If-Match requerido"));
            var command=new CommandMetadata(headers.idempotencyKey(),headers.fingerprint(),headers.expectedRevision(),200,null);
            return coordinator.write(owner,RestaurantShiftResponse.class,command,ctx -> shifts.findByIdAndRestaurantId(shiftId,owner)
                .switchIfEmpty(Mono.error(new AvailabilityException("NOT_FOUND","Turno inexistente"))).flatMap(original -> {
                    if(original.startInstant()==null)return Mono.error(new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Inicio no verificable"));
                    if(!original.startInstant().isAfter(ctx.now()))return Mono.error(new AvailabilityException("SHIFT_ALREADY_STARTED","Turno iniciado"));
                    return zones.findById(owner).switchIfEmpty(Mono.error(new AvailabilityException("VALIDATION_ERROR","Zona requerida"))).flatMap(zone -> {
                        var input=validator.validate(request,zone.zoneId(),ctx.now());
                        return guard.check(ctx,ReservationMutationGuard.MutationKind.SHIFT,shiftId).then(shifts.findAllByRestaurantId(owner).collectList()).flatMap(rows -> {
                            if(rows.stream().filter(row -> !row.id().equals(shiftId)).anyMatch(row -> validator.overlaps(input,row)))return Mono.error(new AvailabilityException("SHIFT_OVERLAP","Intervalo superpuesto"));
                            var updated=new RestaurantShiftCollection(original.id(),original.restaurantId(),input.localStart(),input.localEnd(),input.zoneId(),input.startInstant(),input.endInstant());
                            return shifts.save(updated).map(row -> mapper.shift(row,ctx.revision()));
                        });
                    });
                }));
        }));
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<RestaurantTimeZoneResponse>> replaceZone(Principal actor,UUID owner,RestaurantTimeZoneRequest request,CommandMetadata headers){
        return access.requireManager(actor,owner).then(Mono.defer(() -> {
            if(headers.expectedRevision()==null)return Mono.error(new AvailabilityException("INVALID_REQUEST","If-Match requerido"));
            var command=new CommandMetadata(headers.idempotencyKey(),headers.fingerprint(),headers.expectedRevision(),200,null);
            return coordinator.write(owner,RestaurantTimeZoneResponse.class,command,ctx -> Mono.defer(() -> {
                String zone=request==null?null:request.zoneId();
                try{if(zone==null || zone.isBlank())throw new DateTimeException("Zona requerida");ZoneId.of(zone);}
                catch(DateTimeException e){return Mono.error(new AvailabilityException("VALIDATION_ERROR","Zona desconocida o vacia"));}
                return guard.check(ctx,ReservationMutationGuard.MutationKind.ZONE,owner)
                    .then(shifts.findAllByRestaurantId(owner).collectList()).flatMap(rows -> {
                        var recalculated=new java.util.ArrayList<RestaurantShiftCollection>();
                        var future=new java.util.ArrayList<RestaurantShiftCollection>();
                        for(var row:rows){
                            if(row.startInstant()==null || row.endInstant()==null || !row.endInstant().isAfter(row.startInstant()))throw new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Historia temporal no verificable");
                            if(!row.startInstant().isAfter(ctx.now())){recalculated.add(row);continue;}
                            var input=validator.validate(new RestaurantShiftRequest(row.localStart(),row.localEnd()),zone,ctx.now());
                            var next=new RestaurantShiftCollection(row.id(),row.restaurantId(),input.localStart(),input.localEnd(),input.zoneId(),input.startInstant(),input.endInstant());
                            future.add(next);recalculated.add(next);
                        }
                        // Validar todos antes de la primera escritura; historia conserva sus instantes.
                        for(var candidate:future){
                            var input=new RestaurantShiftValidator.ValidatedShift(candidate.localStart(),candidate.localEnd(),candidate.zoneId(),candidate.startInstant(),candidate.endInstant());
                            if(recalculated.stream().filter(row -> !row.id().equals(candidate.id())).anyMatch(row -> validator.overlaps(input,row)))throw new AvailabilityException("SHIFT_OVERLAP","Cambio de zona superpone turnos");
                        }
                        return reactor.core.publisher.Flux.fromIterable(future).concatMap(shifts::save).then(zones.save(new RestaurantTimeZoneCollection(owner,zone)))
                            .map(row -> mapper.zone(owner,row.zoneId(),ctx.revision()));
                    });
            }));
        }));
    }
}
