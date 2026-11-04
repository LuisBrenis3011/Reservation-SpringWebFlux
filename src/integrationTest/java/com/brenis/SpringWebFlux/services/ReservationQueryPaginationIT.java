package com.brenis.SpringWebFlux.services;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.bson.Document;
import org.springframework.data.mongodb.core.query.*;
import org.springframework.data.domain.Sort;
import com.brenis.SpringWebFlux.support.ReservationQueryIntegrationSupport;
import com.brenis.SpringWebFlux.dtos.responses.ManagedReservationResponse;
import static org.assertj.core.api.Assertions.*;
class ReservationQueryPaginationIT extends ReservationQueryIntegrationSupport {
    @Test void paginasYFiltroRespetanOrdenBsonSinCruzarTitulares(){
        var a=insertManaged(restaurant,"client",false);var b=insertManaged(UUID.randomUUID(),"client",true);
        var c=insertManaged(UUID.randomUUID(),"client",false);insertManaged(UUID.randomUUID(),"other",false);insertLegacy(restaurant);
        var otherIssuer=insertManaged(UUID.randomUUID(),"client",false);
        mongo.updateFirst(Query.query(Criteria.where("_id").is(otherIssuer.id())),new Update().set("customerIssuer","https://otro-emisor.example.test"),"reservations").block();
        var expected=mongo.find(Query.query(Criteria.where("schemaVersion").is(2).and("customerIssuer").is("https://issuer.example.test").and("customerSubject").is("client")).with(Sort.by("_id")),Document.class,"reservations")
            .map(row->com.brenis.SpringWebFlux.repositories.LegacyReservationCommitmentAdapter.uuid(row.get("_id"))).collectList().block();
        var ids=new ArrayList<UUID>();
        for(int page=0;page<3;page++){
            var result=queries.mine(customer("client"),page,1,null).block();assertThat(result.items()).hasSize(1);
            ids.add(((ManagedReservationResponse)result.items().getFirst()).id());
        }
        assertThat(ids).containsExactlyElementsOf(expected);assertThat(new HashSet<>(ids)).hasSize(3);
        assertThat(queries.mine(customer("client"),3,1,null).block().items()).isEmpty();
        assertThat(queries.mine(customer("client"),0,100,"CONFIRMED").block().items()).hasSize(2);
        var cancelled=queries.mine(customer("client"),0,100,"CANCELLED").block();assertThat(cancelled.items()).hasSize(1);
        assertThat(((ManagedReservationResponse)cancelled.items().getFirst()).id()).isEqualTo(b.id());
        for(int size:new int[]{0,101})assertThatThrownBy(()->queries.mine(customer("client"),0,size,null).block()).hasMessageContaining("INVALID_REQUEST");
        assertThatThrownBy(()->queries.mine(customer("client"),-1,20,null).block()).hasMessageContaining("INVALID_REQUEST");
        assertThatThrownBy(()->queries.mine(customer("client"),0,20,"PENDING").block()).hasMessageContaining("INVALID_REQUEST");
    }
}
