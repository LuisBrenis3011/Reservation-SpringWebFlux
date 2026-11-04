package com.brenis.SpringWebFlux.services.impls;

import java.util.Date;
import java.util.UUID;
import org.bson.Document;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import reactor.core.publisher.Mono;
import com.brenis.SpringWebFlux.collections.ReservationPolicyCollection;
import com.brenis.SpringWebFlux.repositories.ReservationRepository;
import com.brenis.SpringWebFlux.repositories.RestaurantRepository;
import com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator;
import com.brenis.SpringWebFlux.validators.ReservationValidator;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

/**
 * Se copia exclusivamente a una extraccion nueva del archive del candidato.
 * Ejercita el servicio y lector reales; los repositorios son dobles que deben
 * permanecer sin llamadas. No es una prueba HTTP ni un ensayo real de Mongo.
 */
class BridgeExportedAssertions {
    private ReactiveMongoTemplate mongo;
    private ReservationRepository reservations;
    private RestaurantRepository restaurants;
    private ReservationValidator validator;
    private RestaurantOperationCoordinator coordinator;
    private ReservationCrudServiceImpl legacy;

    @BeforeEach
    @SuppressWarnings("unchecked")
    void prepare() {
        mongo=mock(ReactiveMongoTemplate.class);
        reservations=mock(ReservationRepository.class);
        restaurants=mock(RestaurantRepository.class);
        validator=mock(ReservationValidator.class);
        coordinator=mock(RestaurantOperationCoordinator.class);
        legacy=new ReservationCrudServiceImpl(reservations,restaurants,validator,coordinator);
        legacy.configureWriteBarrier(mongo);
        when(mongo.findById(ReservationPolicyCollection.ID,Document.class,"reservation_policy"))
            .thenReturn(Mono.just(new Document("_id",ReservationPolicyCollection.ID)
                .append("legacyWritesRetired",true).append("cutoverAt",new Date(0))));
    }

    private void unchanged() {
        verifyNoInteractions(reservations,restaurants,validator,coordinator);
    }

    @Test void BARRIER_INTERNAL_CREATE() {
        assertThatThrownBy(() -> legacy.createReservation(null).block())
            .hasMessageContaining("LEGACY_WRITES_RETIRED");
        unchanged();
    }
    @Test void BARRIER_INTERNAL_UPDATE() {
        assertThatThrownBy(() -> legacy.updateReservation(UUID.randomUUID(),null).block())
            .hasMessageContaining("LEGACY_WRITES_RETIRED");
        unchanged();
    }
    @Test void BARRIER_INTERNAL_DELETE() {
        assertThatThrownBy(() -> legacy.deleteReservation(UUID.randomUUID()).block())
            .hasMessageContaining("LEGACY_WRITES_RETIRED");
        unchanged();
    }
    @Test void BARRIER_READ_FAIL() {
        when(mongo.findById(ReservationPolicyCollection.ID,Document.class,"reservation_policy"))
            .thenReturn(Mono.error(new IllegalStateException("Fallo sintetico del transporte")));
        assertThatThrownBy(() -> legacy.createReservation(null).block()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");
        assertThatThrownBy(() -> legacy.updateReservation(UUID.randomUUID(),null).block()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");
        assertThatThrownBy(() -> legacy.deleteReservation(UUID.randomUUID()).block()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");
        unchanged();
    }
}
