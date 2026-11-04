package com.brenis.SpringWebFlux.services.impls;
import org.springframework.stereotype.Component;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.bson.Document;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.collections.ReservationPolicyCollection;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;

@Component
public class LegacyReservationWriteBarrier {
    private final ReactiveMongoTemplate mongo;
    public LegacyReservationWriteBarrier(ReactiveMongoTemplate mongo){this.mongo=mongo;}
    public Mono<Boolean> retired(){
        return mongo.findById(ReservationPolicyCollection.ID,Document.class,"reservation_policy")
                .map(d->{
                    if(!Boolean.TRUE.equals(d.get("legacyWritesRetired"))||!(d.get("cutoverAt") instanceof java.util.Date))
                        throw new AvailabilityException("DEPENDENCY_UNAVAILABLE","Política inválida");
                    return true;
                }).defaultIfEmpty(false)
                .onErrorMap(e->e instanceof AvailabilityException?e:new AvailabilityException("DEPENDENCY_UNAVAILABLE","Política no verificable",e));
    }
    public Mono<Void> check(){return retired().flatMap(active->active?Mono.error(new AvailabilityException("LEGACY_WRITES_RETIRED","Escritura antigua retirada")):Mono.empty());}
    public Mono<Void> checkTarget(java.util.UUID id){
        return mongo.findById(id,Document.class,"reservations").flatMap(d->isManaged(d)
            ?Mono.<Void>error(new AvailabilityException("LEGACY_RESERVATION_READ_ONLY","El CRUD antiguo no puede escribir reservas gestionadas")):Mono.<Void>empty())
            .onErrorMap(e->e instanceof AvailabilityException?e:new AvailabilityException("DEPENDENCY_UNAVAILABLE","Destino no verificable",e));
    }
    private boolean isManaged(Document document){return java.util.Objects.equals(2,document.get("schemaVersion"));}
}
