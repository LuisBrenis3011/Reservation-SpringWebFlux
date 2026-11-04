package com.brenis.SpringWebFlux.services.impls;

import java.security.Principal;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.*;
import org.springframework.dao.DuplicateKeyException;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.collections.*;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection.TableSnapshot;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.ManagedReservationRequest;
import com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse;
import com.brenis.SpringWebFlux.enums.ManagedReservationStatus;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.mappers.ManagedReservationMapper;
import com.brenis.SpringWebFlux.repositories.*;
import com.brenis.SpringWebFlux.services.definitions.*;
import com.brenis.SpringWebFlux.validators.ReservationTimePolicy;

@Service
public class ReservationCommandServiceImpl implements ReservationCommandService {
    private final RestaurantOperationCoordinator coordinator;
    private final ReservationAccessPolicy access;
    private final LegacyReservationWriteBarrier barrier;
    private final ReservationTimePolicy time;
    private final ReservationAssignmentPolicy assignment;
    private final ReservationOccupancyReader occupancy;
    private final ManagedReservationRepository reservations;
    private final RestaurantShiftRepository shifts;
    private final TableRepository tables;
    private final TableCombinationRepository combinations;
    private final ManagedReservationMapper mapper;
    private final ReactiveMongoTemplate mongo;
    public ReservationCommandServiceImpl(RestaurantOperationCoordinator coordinator,ReservationAccessPolicy access,
        LegacyReservationWriteBarrier barrier,ReservationTimePolicy time,ReservationAssignmentPolicy assignment,
        ReservationOccupancyReader occupancy,ManagedReservationRepository reservations,RestaurantShiftRepository shifts,
        TableRepository tables,TableCombinationRepository combinations,ManagedReservationMapper mapper,ReactiveMongoTemplate mongo){
        this.coordinator=coordinator;this.access=access;this.barrier=barrier;this.time=time;this.assignment=assignment;
        this.occupancy=occupancy;this.reservations=reservations;this.shifts=shifts;this.tables=tables;
        this.combinations=combinations;this.mapper=mapper;this.mongo=mongo;
    }
    private Mono<Void> requireCutover(){return barrier.retired().flatMap(retired->retired?Mono.empty():Mono.error(
        new AvailabilityException("DEPENDENCY_UNAVAILABLE","El corte de reservas no está preparado")));}

    /** Perfil antes de buscar; titular/local antes de replay y otra vez en la sesión de escritura. */
    private Mono<ManagedReservationCollection> accessible(ReservationAccessPolicy.Actor actor,UUID owner,UUID id){
        if(!actor.isCustomer()&&!actor.manages(owner))return Mono.error(failure("FORBIDDEN"));
        var query=Query.query(Criteria.where("_id").is(id).and("restaurantId").in(owner,owner.toString()));
        return mongo.findOne(query,org.bson.Document.class,"reservations")
            .switchIfEmpty(Mono.error(failure("NOT_FOUND"))).map(raw->{
                if(!actor.manages(owner)&&(!actor.issuer().equals(raw.get("customerIssuer"))||!actor.subject().equals(raw.get("customerSubject"))))
                    throw failure("NOT_FOUND");
                Object schema=raw.get("schemaVersion");
                if(schema==null||Objects.equals(schema,1))throw failure(actor.manages(owner)?"LEGACY_RESERVATION_READ_ONLY":"NOT_FOUND");
                if(!Objects.equals(schema,2))throw failure("RESERVATION_UNVERIFIABLE");
                ManagedReservationCollection row;
                try{row=mongo.getConverter().read(ManagedReservationCollection.class,raw);}
                catch(RuntimeException error){throw new AvailabilityException("RESERVATION_UNVERIFIABLE","Reserva no verificable",error);}
                access.requireAccess(actor,row);
                mapper.response(row); // valida snapshot/identidad antes de usar la reserva
                return row;
            });
    }
    private AvailabilityException failure(String code){return new AvailabilityException(code,code);}

    @Override public Mono<RestaurantOperationCoordinator.Result<ManagedReservationResponse>> cancel(
        Principal principal,UUID owner,UUID id,long expectedVersion,CommandMetadata headers){
        return Mono.defer(()->{
            var actor=access.actor(principal);
            if(!actor.isCustomer()&&!actor.manages(owner))throw failure("FORBIDDEN");
            if(expectedVersion<0)throw failure("INVALID_REQUEST");
            var command=new CommandMetadata(headers.idempotencyKey(),headers.fingerprint(),null,200,null);
            // Autorizar recurso e integridad también antes de un replay, que no invoca callback.
            return accessible(actor,owner,id).then(requireCutover()).then(coordinator.writeWithOutcome(owner,ManagedReservationResponse.class,command,
                ctx->Mono.defer(()->{
                    var currentActor=access.actor(principal);
                    return requireCutover().then(accessible(currentActor,owner,id)).flatMap(original->{
                        if(original.status()==ManagedReservationStatus.CANCELLED){
                            // Nueva intención sobre una cancelada: recibo técnico, sin reescribir historia.
                            return Mono.just(new RestaurantOperationCoordinator.MutationOutcome<>(mapper.response(original),false));
                        }
                        if(original.status()!=ManagedReservationStatus.CONFIRMED)throw failure("RESERVATION_NOT_EDITABLE");
                        if(original.version()!=expectedVersion)throw failure("REVISION_MISMATCH");
                        time.cancel(ctx.now(),original.startInstant(),currentActor.manages(owner),false);
                        // Q4: el snapshot propio es autoritativo. No consultar ocupación/guard general.
                        var cancelled=new ManagedReservationCollection(original.id(),original.schemaVersion(),original.restaurantId(),original.shiftId(),
                            original.tableIds(),original.combinationId(),original.customerIssuer(),original.customerSubject(),original.partySize(),original.notes(),
                            ManagedReservationStatus.CANCELLED,Math.incrementExact(original.version()),original.localStart(),original.localEnd(),original.zoneId(),
                            original.startInstant(),original.endInstant(),original.tableSnapshots(),original.assignedCapacity(),original.createdAt(),ctx.now(),ctx.now());
                        var response=mapper.response(cancelled);
                        return reservations.replace(cancelled,expectedVersion).flatMap(changed->changed
                            ?Mono.just(new RestaurantOperationCoordinator.MutationOutcome<>(response,true))
                            :Mono.error(failure("REVISION_MISMATCH")));
                    });
                }))).onErrorMap(error->error instanceof AvailabilityException?error:
                    new AvailabilityException("DEPENDENCY_UNAVAILABLE","No se pudo verificar la cancelación",error));
        });
    }

    private Mono<ReservationAssignmentPolicy.Option> replacementOption(UUID owner,ManagedReservationCollection original,
            ManagedReservationRequest request,Set<UUID> occupied){
        return tables.findAllByRestaurantId(owner).collectList().flatMap(physical->
            combinations.findAllByRestaurantId(owner).collectList().map(configured->{
                var byId=new HashMap<UUID,TableSnapshot>();
                for(var table:physical)if(table.capacity()<=0||byId.put(table.id(),new TableSnapshot(table.id(),table.capacity()))!=null)
                    throw failure("COMMITMENT_CHECK_UNAVAILABLE");
                var options=new ArrayList<ReservationAssignmentPolicy.Option>();
                for(var table:byId.values())options.add(new ReservationAssignmentPolicy.Option(null,List.of(table)));
                for(var combination:configured){
                    var members=new ArrayList<TableSnapshot>();
                    for(UUID member:combination.tableIds()){
                        if(!byId.containsKey(member))throw failure("COMMITMENT_CHECK_UNAVAILABLE");
                        members.add(byId.get(member));
                    }
                    var option=new ReservationAssignmentPolicy.Option(combination.id(),members);
                    option.capacity(); // comprueba también opciones que no resulten elegidas
                    options.add(option);
                }
                if(original.shiftId().equals(request.shiftId())&&original.assignedCapacity()>=request.partySize()){
                    boolean valid=original.tableSnapshots().stream().allMatch(t->
                        t.equals(byId.get(t.id()))&&!occupied.contains(t.id()));
                    valid&=options.stream().anyMatch(o->Objects.equals(o.combinationId(),original.combinationId())&&o.tableIds().equals(original.tableIds()));
                    if(valid)return new ReservationAssignmentPolicy.Option(original.combinationId(),original.tableSnapshots());
                }
                return assignment.select(options,occupied,request.partySize()).orElseThrow(()->failure("NO_AVAILABILITY"));
            }));
    }

    @Override public Mono<RestaurantOperationCoordinator.Result<ManagedReservationResponse>> replace(
        Principal principal,UUID owner,UUID id,long expectedVersion,ManagedReservationRequest request,CommandMetadata headers){
        return Mono.defer(()->{
            var actor=access.actor(principal);
            if(!actor.isCustomer()&&!actor.manages(owner))throw failure("FORBIDDEN");
            if(request==null||request.shiftId()==null||expectedVersion<0)throw failure("INVALID_REQUEST");
            var command=new CommandMetadata(headers.idempotencyKey(),headers.fingerprint(),null,200,null);
            return accessible(actor,owner,id).then(requireCutover()).then(coordinator.write(owner,ManagedReservationResponse.class,command,
                ctx->Mono.defer(()->{
                    var currentActor=access.actor(principal);
                    return accessible(currentActor,owner,id).flatMap(original->{
                        if(original.status()!=ManagedReservationStatus.CONFIRMED)throw failure("RESERVATION_NOT_EDITABLE");
                        if(original.version()!=expectedVersion)throw failure("REVISION_MISMATCH");
                        return requireCutover().then(shifts.findByIdAndRestaurantId(request.shiftId(),owner))
                            .switchIfEmpty(Mono.error(failure("NOT_FOUND"))).flatMap(shift->{
                                time.replace(ctx.now(),original.startInstant(),shift.startInstant(),request.partySize(),currentActor.manages(owner));
                                var duplicate=Query.query(Criteria.where("schemaVersion").is(2).and("restaurantId").is(owner)
                                    .and("shiftId").is(shift.id()).and("customerIssuer").is(original.customerIssuer())
                                    .and("customerSubject").is(original.customerSubject()).and("status").is("CONFIRMED").and("_id").ne(id));
                                return mongo.exists(duplicate,"reservations").flatMap(exists->{
                                    if(exists)return Mono.error(failure("DUPLICATE_RESERVATION"));
                                    return occupancy.read(owner,shift.id(),id,ctx.now()).flatMap(occupied->{
                                        if(occupied.blocked())return Mono.error(failure("LEGACY_RESERVATION_BLOCK"));
                                        return replacementOption(owner,original,request,occupied.tableIds()).flatMap(option->{
                                            var row=new ManagedReservationCollection(original.id(),2,owner,shift.id(),option.tableIds(),option.combinationId(),
                                                original.customerIssuer(),original.customerSubject(),request.partySize(),request.notes(),ManagedReservationStatus.CONFIRMED,
                                                Math.incrementExact(original.version()),shift.localStart(),shift.localEnd(),shift.zoneId(),shift.startInstant(),shift.endInstant(),
                                                option.tables(),option.capacity(),original.createdAt(),ctx.now(),null);
                                            var response=mapper.response(row);
                                            return reservations.replace(row,expectedVersion).flatMap(changed->changed?Mono.just(response):Mono.error(failure("REVISION_MISMATCH")));
                                        });
                                    });
                                });
                            });
                    });
                }))).onErrorMap(error->{
                    if(error instanceof DuplicateKeyException)return failure(Objects.toString(error.getMessage(),"").contains("rsv_active_table_unique")?"NO_AVAILABILITY":"DUPLICATE_RESERVATION");
                    return error instanceof AvailabilityException?error:new AvailabilityException("DEPENDENCY_UNAVAILABLE","No se pudo verificar la modificación",error);
                });
        });
    }
    @Override public Mono<RestaurantOperationCoordinator.Result<ManagedReservationResponse>> confirm(
        Principal principal,UUID owner,ManagedReservationRequest request,CommandMetadata headers){
        return Mono.defer(()->{
            var actor=access.actor(principal);access.requireCustomer(actor);
            if(request==null||request.shiftId()==null)throw new AvailabilityException("INVALID_REQUEST","Turno requerido");
            UUID id=UUID.randomUUID();
            var command=new CommandMetadata(headers.idempotencyKey(),headers.fingerprint(),null,201,
                "/catalog/restaurants/"+owner+"/reservations/"+id);
            // Identidad y corte vigentes incluso antes de recuperar un recibo histórico.
            return requireCutover().then(coordinator.write(owner,ManagedReservationResponse.class,command,ctx->Mono.defer(()->{
                access.requireCustomer(access.actor(principal));
                return requireCutover().then(shifts.findByIdAndRestaurantId(request.shiftId(),owner))
                    .switchIfEmpty(Mono.error(new AvailabilityException("NOT_FOUND","Turno inexistente")))
                    .flatMap(shift->{
                        time.confirm(ctx.now(),shift.startInstant(),request.partySize());
                        var duplicate=Query.query(Criteria.where("schemaVersion").is(2).and("restaurantId").is(owner)
                            .and("shiftId").is(shift.id()).and("customerIssuer").is(actor.issuer())
                            .and("customerSubject").is(actor.subject()).and("status").is("CONFIRMED"));
                        return mongo.exists(duplicate,"reservations").flatMap(exists->{
                            if(exists)return Mono.error(new AvailabilityException("DUPLICATE_RESERVATION","Ya tienes una reserva confirmada en este turno"));
                            return occupancy.read(owner,shift.id(),null,ctx.now()).flatMap(occupied->{
                                if(occupied.blocked())return Mono.error(new AvailabilityException("LEGACY_RESERVATION_BLOCK","Hay compromisos no verificables"));
                                return tables.findAllByRestaurantId(owner).collectList().flatMap(physical->
                                    combinations.findAllByRestaurantId(owner).collectList().flatMap(configured->{
                                        var byId=new HashMap<UUID,TableSnapshot>();
                                        for(var table:physical){if(table.capacity()<=0||byId.put(table.id(),new TableSnapshot(table.id(),table.capacity()))!=null)
                                            throw new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Mesas no verificables");}
                                        var options=new ArrayList<ReservationAssignmentPolicy.Option>();
                                        for(var table:byId.values())options.add(new ReservationAssignmentPolicy.Option(null,List.of(table)));
                                        for(var combination:configured){
                                            var members=new ArrayList<TableSnapshot>();
                                            for(var member:combination.tableIds()){
                                                if(!byId.containsKey(member))throw new AvailabilityException("COMMITMENT_CHECK_UNAVAILABLE","Combinación no verificable");
                                                members.add(byId.get(member));
                                            }
                                            options.add(new ReservationAssignmentPolicy.Option(combination.id(),members));
                                        }
                                        var option=assignment.select(options,occupied.tableIds(),request.partySize()).orElseThrow(()->
                                            new AvailabilityException("NO_AVAILABILITY","No hay una opción disponible para el grupo"));
                                        var row=new ManagedReservationCollection(id,2,owner,shift.id(),option.tableIds(),option.combinationId(),
                                            actor.issuer(),actor.subject(),request.partySize(),request.notes(),ManagedReservationStatus.CONFIRMED,1,
                                            shift.localStart(),shift.localEnd(),shift.zoneId(),shift.startInstant(),shift.endInstant(),option.tables(),
                                            option.capacity(),ctx.now(),ctx.now(),null);
                                        var response=mapper.response(row);
                                        return reservations.insert(row).thenReturn(response);
                                    }));
                            });
                        });
                    });
            }))).doOnNext(result->{
                var savedOwner=result.body().owner();
                if(!actor.issuer().equals(savedOwner.issuer())||!actor.subject().equals(savedOwner.subject()))
                    throw new AvailabilityException("NOT_FOUND","Reserva no encontrada");
            }).onErrorMap(error->{
                if(error instanceof DuplicateKeyException){
                    boolean tableConflict=Objects.toString(error.getMessage(),"").contains("rsv_active_table_unique");
                    return new AvailabilityException(tableConflict?"NO_AVAILABILITY":"DUPLICATE_RESERVATION","La reserva entra en conflicto con otra confirmación",error);
                }
                return error instanceof AvailabilityException?error:new AvailabilityException("DEPENDENCY_UNAVAILABLE","No se pudo verificar la confirmación",error);
            });
        });
    }
}
