package com.brenis.SpringWebFlux.repositories;

import java.nio.charset.StandardCharsets;
import java.util.*;
import org.bson.*;
import org.bson.json.*;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.*;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.dtos.responses.LegacyReservationResponse;

/** Proyección estrictamente de lectura; nunca transforma o reescribe documentos legados. */
@Repository
public class LegacyReservationQueryRepository {
    private final ReactiveMongoTemplate mongo;
    private static final JsonWriterSettings CANONICAL=JsonWriterSettings.builder().outputMode(JsonMode.EXTENDED).build();
    public LegacyReservationQueryRepository(ReactiveMongoTemplate mongo){this.mongo=mongo;}
    public String reference(Object id){
        try{
            if(id==null)throw new IllegalArgumentException();
            Object value=id instanceof UUID uuid?new BsonBinary(uuid,UuidRepresentation.STANDARD):id;
            String encoded=Base64.getUrlEncoder().withoutPadding().encodeToString(new Document("_id",value).toJson(CANONICAL).getBytes(StandardCharsets.UTF_8));
            if(encoded.length()>4096)throw new IllegalArgumentException();
            return encoded;
        }catch(RuntimeException e){throw new AvailabilityException("RESERVATION_UNVERIFIABLE","Identificador legado no verificable",e);}
    }
    public Object parseReference(String reference){
        try{
            if(reference==null||reference.length()>4096||!reference.matches("[A-Za-z0-9_-]+"))throw new IllegalArgumentException();
            byte[] bytes=Base64.getUrlDecoder().decode(reference);
            String json=new String(bytes,StandardCharsets.UTF_8);
            if(!Arrays.equals(json.getBytes(StandardCharsets.UTF_8),bytes))throw new IllegalArgumentException();
            Document wrapper=Document.parse(json);
            if(wrapper.size()!=1||!wrapper.containsKey("_id")||wrapper.get("_id")==null||!reference(wrapper.get("_id")).equals(reference))throw new IllegalArgumentException();
            return wrapper.get("_id");
        }catch(RuntimeException e){throw new AvailabilityException("INVALID_REQUEST","Referencia legada inválida",e);}
    }
    public Mono<Document> find(UUID restaurant,Object id){
        return mongo.findOne(Query.query(Criteria.where("_id").is(id)),Document.class,"reservations")
            .filter(row->restaurant.equals(LegacyReservationCommitmentAdapter.uuid(row.get("restaurantId"))))
            .filter(row->!managed(row));
    }
    public LegacyReservationResponse project(Document row,UUID restaurant){
        if(!restaurant.equals(LegacyReservationCommitmentAdapter.uuid(row.get("restaurantId")))||managed(row))
            throw new AvailabilityException("RESERVATION_UNVERIFIABLE","Legado no verificable");
        return new LegacyReservationResponse("LEGACY",reference(row.get("_id")),restaurant,text(row,"status"),text(row,"customerName"),
            text(row,"date"),text(row,"time"),number(row,"partySize"),text(row,"notes"));
    }
    private String text(Document row,String field){Object value=row.get(field);return value instanceof String text?text:null;}
    private boolean managed(Document row){Object version=row.get("schemaVersion");if(version==null)return false;
        if(version instanceof Number n){if(n.doubleValue()==2.0)return true;if(n.doubleValue()==1.0)return false;}
        throw new AvailabilityException("RESERVATION_UNVERIFIABLE","Versión de reserva no verificable");}
    private Integer number(Document row,String field){Object value=row.get(field);if(!(value instanceof Number n))return null;
        long l=n.longValue();return l>=Integer.MIN_VALUE&&l<=Integer.MAX_VALUE&&n.doubleValue()==l?(int)l:null;}
}
