package com.brenis.SpringWebFlux.support;

import java.security.Principal;
import java.util.*;
import org.bson.Document;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse;
import com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator.Result;
import static org.assertj.core.api.Assertions.*;

/** Helpers sobre el contexto/replica/Clock existentes; no crea otra infraestructura. */
public abstract class ReservationCancellationSupport extends ReservationReplacementSupport {
    protected Mono<Result<ManagedReservationResponse>> cancel(Principal actor,UUID id,long version,String key){
        var identity=new com.brenis.SpringWebFlux.services.impls.ReservationAccessPolicy().actor(actor);
        String internal;
        try{internal="rsv:"+HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256")
            .digest((identity.issuer()+"|"+identity.subject()+"|"+key).getBytes(java.nio.charset.StandardCharsets.UTF_8)));}
        catch(java.security.NoSuchAlgorithmException impossible){throw new IllegalStateException(impossible);}
        return commands.cancel(actor,restaurant,id,version,new CommandMetadata(internal,"POST:cancellation:"+id+":"+version,null,200,null));
    }
    protected Document raw(UUID id){return mongo.findById(id,Document.class,"reservations").block();}
    protected void historyUnchanged(Document before,Document after){
        var left=new Document(before);var right=new Document(after);
        for(String field:List.of("status","version","updatedAt","cancelledAt")){left.remove(field);right.remove(field);}
        assertThat(right).isEqualTo(left);
    }
    protected Mono<Document> admin(Document command){return mongo.getMongoDatabaseFactory().getMongoDatabase("admin").flatMap(db->Mono.from(db.runCommand(command)));}
}
