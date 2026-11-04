package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationConfirmationSupport;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.ManagedReservationRequest;
import static org.assertj.core.api.Assertions.*;
class ReservationReceiptAuthorizationIT extends ReservationConfirmationSupport {
    @Test void actorAjenoNoRecuperaReciboAunqueUnConsumidorInternoReutiliceMetadata(){
        confirm("client","same",3).block();
        var receipt=mongo.findOne(org.springframework.data.mongodb.core.query.Query.query(org.springframework.data.mongodb.core.query.Criteria.where("restaurantId").is(restaurant)),
            com.brenis.SpringWebFlux.collections.OperationReceiptCollection.class).block();
        assertThatThrownBy(()->commands.confirm(otherCustomer(),restaurant,new ManagedReservationRequest(shift,3,""),
            new CommandMetadata(receipt.idempotencyKey(),receipt.fingerprint(),null,201,null)).block()).hasMessageContaining("NOT_FOUND");
        assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
    }
    @Test void replayConservaTodoYConflictoNoModificaNada(){
        var first=confirm("client","same",3).block();
        assertThat(confirm("client","same",3).block()).isEqualTo(first);
        assertThatThrownBy(()->confirm("client","same",2).block()).hasMessageContaining("IDEMPOTENCY_CONFLICT");
        assertThatThrownBy(()->confirm("other","same",1).block()).hasMessageContaining("NO_AVAILABILITY");
        assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
    }
    @Test void perfilRevocadoNoRecuperaRecibos(){
        confirm("client","same",3).block();
        assertThatThrownBy(()->commands.confirm(manager,restaurant,new ManagedReservationRequest(shift,3,""),
            new CommandMetadata("key","hash",null,201,null)).block()).hasMessageContaining("FORBIDDEN");
        assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
    }
}
