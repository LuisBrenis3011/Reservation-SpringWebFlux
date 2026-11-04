package com.brenis.SpringWebFlux.services.impls;

import com.brenis.SpringWebFlux.clientes.PlannerMSClient;
import com.brenis.SpringWebFlux.collections.ReservationCollection;
import com.brenis.SpringWebFlux.collections.RestaurantCollection;
import com.brenis.SpringWebFlux.enums.ReservationStatusEnum;
import com.brenis.SpringWebFlux.exceptions.BusinessException;
import com.brenis.SpringWebFlux.exceptions.ResourceNotFoundException;
import com.brenis.SpringWebFlux.repositories.ReservationRepository;
import com.brenis.SpringWebFlux.repositories.RestaurantRepository;
import com.brenis.SpringWebFlux.validators.ReservationValidator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.Locale;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ReservationCrudServiceImplTests {
    private static final Duration TIMEOUT = Duration.ofSeconds(2);
    private static final UUID RESERVATION_ID = UUID.randomUUID();
    private static final String CUSTOMER_ID = UUID.randomUUID().toString();
    private static final UUID RESTAURANT_ID = UUID.fromString("fa7b71e6-788e-460d-b8c1-0a59bfea2ea2");

    @Mock private ReservationRepository reservations;
    @Mock private RestaurantRepository restaurants;
    @Mock private PlannerMSClient planner;

    private ReservationCrudServiceImpl service;
    private ReservationCollection existing;
    private ReservationCollection update;

    private com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator coordinatorForUnitTest() {
        var coordinator = mock(com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator.class);
        lenient().when(coordinator.writeLegacy(any(), any())).thenAnswer(call -> {
            java.util.function.Function<com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator.Context, Mono<Object>> work=call.getArgument(1);
            return work.apply(new com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator.Context(call.getArgument(0),1,java.time.Instant.now()));
        });
        return coordinator;
    }
    @BeforeEach
    void setUp() {
        service = new ReservationCrudServiceImpl(reservations, restaurants,
                new ReservationValidator<ReservationCollection>(restaurants, planner), coordinatorForUnitTest());
        var policyMongo=mock(org.springframework.data.mongodb.core.ReactiveMongoTemplate.class);
        lenient().when(policyMongo.findById(com.brenis.SpringWebFlux.collections.ReservationPolicyCollection.ID,
                org.bson.Document.class,"reservation_policy")).thenReturn(Mono.empty());
        service.configureWriteBarrier(policyMongo);
        lenient().when(policyMongo.findById(any(UUID.class),org.mockito.ArgumentMatchers.eq(org.bson.Document.class),org.mockito.ArgumentMatchers.eq("reservations"))).thenReturn(Mono.empty());
        existing = ReservationCollection.builder()
                .id(RESERVATION_ID).restaurantId(RESTAURANT_ID.toString())
                .customerId(CUSTOMER_ID).customerName("Original customer")
                .customerEmail("original@example.com").date("2026-11-01").time("18:00")
                .partySize(2).notes("Original notes").status(ReservationStatusEnum.CONFIRMED)
                .build();
        update = ReservationCollection.builder()
                .restaurantId(RESTAURANT_ID.toString()).customerName("Updated customer")
                .date("2026-11-02").time("19:30").partySize(4).notes("Window seat")
                .build();
        when(reservations.findById(RESERVATION_ID)).thenReturn(Mono.just(existing));
    }

    @ParameterizedTest
    @EnumSource(ReservationStatusEnum.class)
    void updatesEditableFieldsAndPreservesIdentityAndStatus(ReservationStatusEnum status) {
        existing.setStatus(status);
        stubAvailableRestaurant();
        when(reservations.save(any(ReservationCollection.class)))
                .thenAnswer(invocation -> Mono.just(invocation.getArgument(0)));

        ReservationCollection result = service.updateReservation(RESERVATION_ID, update).block(TIMEOUT);

        assertNotNull(result);
        assertAll(
                () -> assertEquals(RESERVATION_ID, result.getId()),
                () -> assertEquals(RESTAURANT_ID.toString(), result.getRestaurantId()),
                () -> assertEquals(CUSTOMER_ID, result.getCustomerId()),
                () -> assertEquals("original@example.com", result.getCustomerEmail()),
                () -> assertEquals(status, result.getStatus()),
                () -> assertEquals("Updated customer", result.getCustomerName()),
                () -> assertEquals("2026-11-02", result.getDate()),
                () -> assertEquals("19:30", result.getTime()),
                () -> assertEquals(4, result.getPartySize()),
                () -> assertEquals("Window seat", result.getNotes()));
        verify(reservations).save(existing);
    }

    @Test
    void rejectsChangingRestaurantBeforeCheckingAvailability() {
        update.setRestaurantId(UUID.randomUUID().toString());

        BusinessException error = assertThrows(BusinessException.class,
                () -> service.updateReservation(RESERVATION_ID, update).block(TIMEOUT));

        assertEquals("Restaurant ID must be the same as the original Restaurant", error.getMessage());
        assertUnchangedAndNotSaved();
        verifyNoInteractions(restaurants, planner);
    }

    @Test
    void acceptsTheSameRestaurantWithUppercaseUuid() {
        update.setRestaurantId(RESTAURANT_ID.toString().toUpperCase(Locale.ROOT));
        stubAvailableRestaurant();
        when(reservations.save(any(ReservationCollection.class)))
                .thenAnswer(invocation -> Mono.just(invocation.getArgument(0)));

        ReservationCollection result = service.updateReservation(RESERVATION_ID, update).block(TIMEOUT);

        assertNotNull(result);
        assertEquals(RESTAURANT_ID.toString(), result.getRestaurantId());
        verify(reservations).save(existing);
    }

    @Test
    void rejectsUnavailableReservationWithoutSaving() {
        when(planner.verifyAvailability(update.getDate(), update.getTime(), RESTAURANT_ID))
                .thenReturn(Mono.just(false));
        // The validation chain currently assembles both publishers eagerly.
        when(restaurants.findById(RESTAURANT_ID)).thenReturn(Mono.just(openRestaurant()));

        BusinessException error = assertThrows(BusinessException.class,
                () -> service.updateReservation(RESERVATION_ID, update).block(TIMEOUT));

        assertEquals("No availability...", error.getMessage());
        assertUnchangedAndNotSaved();
    }

    @Test
    void rejectsReservationAfterClosingWithoutSaving() {
        update.setTime("23:00");
        stubAvailableRestaurant();

        BusinessException error = assertThrows(BusinessException.class,
                () -> service.updateReservation(RESERVATION_ID, update).block(TIMEOUT));

        assertEquals("Restaurant already closed", error.getMessage());
        assertUnchangedAndNotSaved();
    }

    @Test
    void rejectsMissingReservationWithoutCheckingAvailability() {
        when(reservations.findById(RESERVATION_ID)).thenReturn(Mono.empty());

        assertThrows(ResourceNotFoundException.class,
                () -> service.updateReservation(RESERVATION_ID, update).block(TIMEOUT));

        verify(reservations, never()).save(any(ReservationCollection.class));
        verifyNoInteractions(restaurants, planner);
    }

    private void stubAvailableRestaurant() {
        when(planner.verifyAvailability(update.getDate(), update.getTime(), RESTAURANT_ID))
                .thenReturn(Mono.just(true));
        when(restaurants.findById(RESTAURANT_ID)).thenReturn(Mono.just(openRestaurant()));
    }

    private RestaurantCollection openRestaurant() {
        return RestaurantCollection.builder().id(RESTAURANT_ID).closeAt("22:00").build();
    }

    private void assertUnchangedAndNotSaved() {
        assertEquals("Original customer", existing.getCustomerName());
        assertEquals("18:00", existing.getTime());
        assertEquals(ReservationStatusEnum.CONFIRMED, existing.getStatus());
        verify(reservations, never()).save(any(ReservationCollection.class));
    }
}
