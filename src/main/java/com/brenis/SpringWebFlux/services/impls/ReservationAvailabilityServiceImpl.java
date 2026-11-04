package com.brenis.SpringWebFlux.services.impls;
import java.time.*;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.reactive.TransactionalOperator;
import reactor.core.publisher.*;
import com.brenis.SpringWebFlux.collections.*;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection.TableSnapshot;
import com.brenis.SpringWebFlux.configs.AvailabilityProperties;
import com.brenis.SpringWebFlux.dtos.responses.ReservationAvailabilityResponse;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.repositories.*;
import com.brenis.SpringWebFlux.services.definitions.ReservationAvailabilityService;
import com.brenis.SpringWebFlux.validators.ReservationTimePolicy;

@Service
public class ReservationAvailabilityServiceImpl implements ReservationAvailabilityService {
    private final RestaurantRepository restaurants; private final RestaurantShiftRepository shifts;
    private final TableRepository tables; private final TableCombinationRepository combinations;
    private final ReservationOccupancyReader occupancy; private final ReservationAssignmentPolicy assignment;
    private final ReservationTimePolicy time; private final TransactionalOperator transactions;
    private final Clock clock; private final AvailabilityProperties properties;
    public ReservationAvailabilityServiceImpl(RestaurantRepository restaurants,RestaurantShiftRepository shifts,TableRepository tables,
        TableCombinationRepository combinations,ReservationOccupancyReader occupancy,ReservationAssignmentPolicy assignment,
        ReservationTimePolicy time,TransactionalOperator transactions,Clock clock,AvailabilityProperties properties){
        this.restaurants=restaurants;this.shifts=shifts;this.tables=tables;this.combinations=combinations;this.occupancy=occupancy;
        this.assignment=assignment;this.time=time;this.transactions=transactions;this.clock=clock;this.properties=properties;
    }
    private static final class OccupancyFailure extends RuntimeException { OccupancyFailure(Throwable cause){super(cause);} }
    private record Offer(List<RestaurantShiftCollection> shifts,List<ReservationAssignmentPolicy.Option> options) {}
    @Override public Mono<ReservationAvailabilityResponse> list(UUID owner,LocalDate date,int size){
        return Mono.defer(()->{
            time.group(size);
            return snapshot(owner,date,size,false).onErrorResume(OccupancyFailure.class,error->snapshot(owner,date,size,true));
        }).onErrorMap(error->error instanceof AvailabilityException?error:new AvailabilityException("DEPENDENCY_UNAVAILABLE","No se pudo consultar la oferta",error));
    }
    private Mono<ReservationAvailabilityResponse> snapshot(UUID owner,LocalDate date,int size,boolean undetermined){
        return transactions.transactional(Mono.defer(()->{
            Instant now=clock.instant();
            return restaurants.existsById(owner).flatMap(exists->exists?offer(owner,date,now):Mono.error(new AvailabilityException("NOT_FOUND","Restaurante inexistente")))
                .flatMap(offer->Flux.fromIterable(offer.shifts()).concatMap(shift->{
                    Mono<String> state=undetermined?Mono.just("UNDETERMINED"):occupancy.read(owner,shift.id(),null,now)
                        .onErrorMap(OccupancyFailure::new).map(result->result.blocked()?"UNDETERMINED":
                            assignment.select(offer.options(),result.tableIds(),size).isPresent()?"AVAILABLE":"UNAVAILABLE");
                    return state.map(value->{String window=time.window(now,shift.startInstant()).name();
                        var format=java.time.format.DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ss");
                        return new ReservationAvailabilityResponse.Item(shift.id(),LocalDateTime.parse(shift.localStart()).format(format),LocalDateTime.parse(shift.localEnd()).format(format),shift.zoneId(),shift.startInstant(),shift.endInstant(),window,value,window.equals("OPEN")&&value.equals("AVAILABLE"));});
                }).collectList().map(items->new ReservationAvailabilityResponse(owner,date.toString(),size,now,items)));
        }).timeout(properties.getTransactionTimeout()));
    }
    private Mono<Offer> offer(UUID owner,LocalDate date,Instant now){
        return shifts.findAllByRestaurantId(owner).collectList().flatMap(rows->tables.findAllByRestaurantId(owner).collectList()
            .flatMap(physical->combinations.findAllByRestaurantId(owner).collectList().map(configured->{
                var selected=new ArrayList<RestaurantShiftCollection>();
                for(var row:rows){
                    try{
                        var local=LocalDateTime.parse(row.localStart());var end=LocalDateTime.parse(row.localEnd());var zone=ZoneId.of(row.zoneId());
                        var a=zone.getRules().getValidOffsets(local);var b=zone.getRules().getValidOffsets(end);
                        if(a.size()!=1||b.size()!=1||!local.toInstant(a.getFirst()).equals(row.startInstant())||!end.toInstant(b.getFirst()).equals(row.endInstant())||!row.endInstant().isAfter(row.startInstant()))throw new IllegalArgumentException();
                        if(local.toLocalDate().equals(date)&&row.startInstant().isAfter(now))selected.add(row);
                    }catch(RuntimeException e){throw new AvailabilityException("DEPENDENCY_UNAVAILABLE","Turno no verificable",e);}
                }
                selected.sort(Comparator.comparing(RestaurantShiftCollection::startInstant).thenComparing(s->s.id().toString()));
                var byId=new HashMap<UUID,TableSnapshot>();var options=new ArrayList<ReservationAssignmentPolicy.Option>();
                for(var table:physical){if(table.id()==null||table.capacity()<=0||byId.put(table.id(),new TableSnapshot(table.id(),table.capacity()))!=null)throw new AvailabilityException("DEPENDENCY_UNAVAILABLE","Mesa no verificable");}
                for(var table:byId.values())options.add(new ReservationAssignmentPolicy.Option(null,List.of(table)));
                for(var combo:configured){var members=new ArrayList<TableSnapshot>();for(var id:combo.tableIds()){
                    if(!byId.containsKey(id))throw new AvailabilityException("DEPENDENCY_UNAVAILABLE","Combinación no verificable");members.add(byId.get(id));}
                    var option=new ReservationAssignmentPolicy.Option(combo.id(),members);
                    try{option.capacity();}catch(RuntimeException e){throw new AvailabilityException("DEPENDENCY_UNAVAILABLE","Combinación no verificable",e);} options.add(option);
                }
                return new Offer(selected,options);
            })));
    }
}
