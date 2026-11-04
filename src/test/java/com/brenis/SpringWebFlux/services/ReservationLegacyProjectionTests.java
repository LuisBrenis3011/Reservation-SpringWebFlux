package com.brenis.SpringWebFlux.services;
import java.util.UUID;
import org.bson.Document;
import org.bson.types.ObjectId;
import org.junit.jupiter.api.Test;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import com.brenis.SpringWebFlux.repositories.LegacyReservationQueryRepository;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.mock;
class ReservationLegacyProjectionTests {
    private final LegacyReservationQueryRepository repository=new LegacyReservationQueryRepository(mock(ReactiveMongoTemplate.class));
    @Test void referenciasConservanTipoYRechazanFormaNoCanonica(){
        for(Object id:new Object[]{"123",123,new ObjectId(),new org.bson.BsonBinary(UUID.randomUUID(),org.bson.UuidRepresentation.STANDARD)}){
            String ref=repository.reference(id);assertThat(ref).doesNotContain("=");
            assertThat(repository.reference(repository.parseReference(ref))).isEqualTo(ref);
        }
        assertThatThrownBy(()->repository.parseReference("invalid===")).hasMessageContaining("INVALID_REQUEST");
        assertThatThrownBy(()->repository.parseReference("a".repeat(4097))).hasMessageContaining("INVALID_REQUEST");
    }
    @Test void proyeccionNoFiltraCorreoNiAtribuyeCliente(){
        var owner=UUID.randomUUID();var row=new Document("_id",new ObjectId()).append("restaurantId",owner.toString())
            .append("customerEmail","secreto@example.test").append("customerId","ajeno").append("customerName","Cliente");
        var result=repository.project(row,owner);assertThat(result.kind()).isEqualTo("LEGACY");
        assertThat(result.customerName()).isEqualTo("Cliente");assertThat(result.notes()).isNull();
        assertThat(result.toString()).doesNotContain("secreto@example.test","ajeno");
        assertThatThrownBy(()->repository.project(row,UUID.randomUUID())).hasMessageContaining("RESERVATION_UNVERIFIABLE");
        row.put("schemaVersion",2L);assertThatThrownBy(()->repository.project(row,owner)).hasMessageContaining("RESERVATION_UNVERIFIABLE");
    }
}
