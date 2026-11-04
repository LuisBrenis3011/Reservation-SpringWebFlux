package com.brenis.SpringWebFlux.services;

import com.brenis.SpringWebFlux.collections.TableCollection;
import com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import com.brenis.SpringWebFlux.dtos.responses.TableAvailabilityResponse;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.mappers.TableAvailabilityMapper;
import com.brenis.SpringWebFlux.repositories.TableRepository;
import com.brenis.SpringWebFlux.services.definitions.RestaurantOperationCoordinator;
import com.brenis.SpringWebFlux.services.impls.*;
import com.brenis.SpringWebFlux.support.*;
import com.brenis.SpringWebFlux.validators.TableConfigurationValidator;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import reactor.core.publisher.*;
import reactor.test.StepVerifier;
import java.time.Instant;
import java.util.*;
import java.util.function.Function;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static com.brenis.SpringWebFlux.services.impls.ReservationMutationGuard.MutationKind.*;

class AvailabilityTablePatchTests {
    final UUID owner=UUID.randomUUID(), id=UUID.randomUUID();
    final AvailabilityClockFixture clock=new AvailabilityClockFixture(Instant.parse("2026-11-01T10:00:00Z"));
    final JwtAuthenticationToken manager=new JwtAuthenticationToken(AvailabilityIdentityFixture.managerJwt(owner,clock));
    TableRepository repository;
    RestaurantOperationCoordinator coordinator;
    ReservationMutationGuard guard;
    TableConfigurationServiceImpl service;
    TableCollection original;
    @BeforeEach @SuppressWarnings("unchecked") void setup() {
        repository=mock(TableRepository.class);
        coordinator=mock(RestaurantOperationCoordinator.class);
        guard=mock(ReservationMutationGuard.class);
        var validator=new TableConfigurationValidator();
        service=new TableConfigurationServiceImpl(repository,coordinator,guard,new RestaurantAccessPolicy(),
                validator,new TableAvailabilityMapper(validator));
        original=new TableCollection(id,owner,"Mesa 1","mesa 1",4);
        when(coordinator.write(eq(owner),eq(TableAvailabilityResponse.class),any(),any())).thenAnswer(inv -> {
            Function<RestaurantOperationCoordinator.Context,Mono<TableAvailabilityResponse>> work=inv.getArgument(3);
            return Mono.defer(() -> work.apply(new RestaurantOperationCoordinator.Context(owner,2,clock.instant())))
                    .map(reply -> new RestaurantOperationCoordinator.Result<>(reply,2,200,null));
        });
        when(repository.findByIdAndRestaurantId(id,owner)).thenReturn(Mono.just(original));
        when(repository.existsByRestaurantIdAndLabelKey(eq(owner),anyString())).thenReturn(Mono.just(false));
        when(repository.findAllByRestaurantId(owner)).thenReturn(Flux.just(original));
        when(repository.save(any(TableCollection.class))).thenAnswer(inv -> Mono.just(inv.getArgument(0,TableCollection.class)));
        when(guard.check(any(),any(),eq(id))).thenReturn(Mono.empty());
    }
    CommandMetadata command() { return new CommandMetadata("patch","PATCH:"+id,1L,200,null); }
    @Test void esc0107_omitidoConservaCapacidadEIdentidad() {
        StepVerifier.create(service.patch(manager,owner,id,new TablePatchRequest("  Ventana  ",null),command()))
                .assertNext(result -> {
                    assertThat(result.body()).isEqualTo(new TableAvailabilityResponse(id,owner,"Ventana",4,2));
                    assertThat(result.revision()).isEqualTo(2);
                }).verifyComplete();
        verify(guard).check(any(),eq(LABEL_ONLY),eq(id));
        verify(repository,never()).findAllByRestaurantId(any());
    }
    @Test void esc0107_capacidadOmitidaNoSeConfundeConCero() {
        StepVerifier.create(service.patch(manager,owner,id,new TablePatchRequest(null,6L),command()))
                .assertNext(result -> {
                    assertThat(result.body().label()).isEqualTo("Mesa 1");
                    assertThat(result.body().capacity()).isEqualTo(6);
                    assertThat(result.body().id()).isEqualTo(id);
                    assertThat(result.body().restaurantId()).isEqualTo(owner);
                }).verifyComplete();
        verify(guard).check(any(),eq(TABLE_CAPACITY),eq(id));
    }
    @Test void esc0107_actualizaAmbosCamposEnUnaSolaEscritura() {
        StepVerifier.create(service.patch(manager,owner,id,new TablePatchRequest("Terraza",8L),command()))
                .assertNext(result -> {
                    assertThat(result.body().label()).isEqualTo("Terraza");
                    assertThat(result.body().capacity()).isEqualTo(8);
                }).verifyComplete();
        verify(repository,times(1)).save(new TableCollection(id,owner,"Terraza","terraza",8));
    }
    @Test void esc0108_colisionNoGuardaEtiquetaNiCapacidad() {
        when(repository.existsByRestaurantIdAndLabelKey(owner,"mesa 2")).thenReturn(Mono.just(true));
        StepVerifier.create(service.patch(manager,owner,id,new TablePatchRequest(" MESA 2 ",8L),command()))
                .expectErrorMatches(e -> e.getMessage().contains("DUPLICATE_LABEL")).verify();
        verify(repository,never()).save(any());
        assertThat(original.capacity()).isEqualTo(4);
    }
    @Test void mismaClaveNormalizadaNoColisionaConsigoMisma() {
        StepVerifier.create(service.patch(manager,owner,id,new TablePatchRequest(" MESA 1 ",null),command()))
                .assertNext(result -> assertThat(result.body().label()).isEqualTo("MESA 1")).verifyComplete();
        verify(repository,never()).existsByRestaurantIdAndLabelKey(any(),anyString());
    }
    @Test void capacidadPresentePeroIgualEsSoloRenombrado() {
        StepVerifier.create(service.patch(manager,owner,id,new TablePatchRequest("Nueva",4L),command()))
                .assertNext(result -> assertThat(result.body().capacity()).isEqualTo(4)).verifyComplete();
        verify(guard).check(any(),eq(LABEL_ONLY),eq(id));
        verify(guard,never()).check(any(),eq(TABLE_CAPACITY),any());
    }
    @ParameterizedTest @ValueSource(longs={0,-1})
    void capacidadNoPositivaNoEscribe(long invalid) {
        StepVerifier.create(service.patch(manager,owner,id,new TablePatchRequest(null,invalid),command()))
                .expectErrorMatches(e -> e.getMessage().contains("VALIDATION_ERROR")).verify();
        verify(repository,never()).save(any());
    }
    @Test void etiquetaVaciaNoEscribe() {
        StepVerifier.create(service.patch(manager,owner,id,new TablePatchRequest("   ",null),command()))
                .expectErrorMatches(e -> e.getMessage().contains("VALIDATION_ERROR")).verify();
        verify(repository,never()).save(any());
    }
    @Test void sumaExactaRechazaOverflowSinGuardar() {
        when(repository.findAllByRestaurantId(owner)).thenReturn(Flux.just(original,
                new TableCollection(UUID.randomUUID(),owner,"Otra","otra",Long.MAX_VALUE-4)));
        StepVerifier.create(service.patch(manager,owner,id,new TablePatchRequest("Nueva",5L),command()))
                .expectErrorMatches(e -> e.getMessage().contains("VALIDATION_ERROR")).verify();
        verify(repository,never()).save(any());
    }
    @Test void recursoFueraDelRestauranteEs404SinConsultarCompromisos() {
        when(repository.findByIdAndRestaurantId(id,owner)).thenReturn(Mono.empty());
        StepVerifier.create(service.patch(manager,owner,id,new TablePatchRequest("Nueva",null),command()))
                .expectErrorMatches(e -> e.getMessage().contains("NOT_FOUND")).verify();
        verifyNoInteractions(guard);
        verify(repository,never()).save(any());
    }
    @Test void sinPermisoNoInvocaCoordinadorNiRepositorio() {
        var foreign=new JwtAuthenticationToken(AvailabilityIdentityFixture.managerJwt(UUID.randomUUID(),clock));
        StepVerifier.create(service.patch(foreign,owner,id,new TablePatchRequest("Nueva",null),command()))
                .expectErrorMatches(e -> e.getMessage().contains("FORBIDDEN")).verify();
        verifyNoInteractions(coordinator,repository,guard);
    }
    @Test void fronteraDeServicioTambienExigeRevision() {
        var noRevision=new CommandMetadata("missing","fingerprint",null,200,null);
        StepVerifier.create(service.patch(manager,owner,id,new TablePatchRequest("Nueva",null),noRevision))
                .expectErrorMatches(e -> e.getMessage().contains("INVALID_REQUEST")).verify();
        verifyNoInteractions(coordinator,repository,guard);
    }
    @Test void duplicadoDetectadoPorIndiceSeTraduceAConflictoDeDominio() {
        when(repository.save(any(TableCollection.class))).thenReturn(Mono.error(
                new org.springframework.dao.DuplicateKeyException("índice")));
        StepVerifier.create(service.patch(manager,owner,id,new TablePatchRequest("Nueva",null),command()))
                .expectErrorMatches(e -> e.getMessage().contains("DUPLICATE_LABEL")).verify();
    }
}

