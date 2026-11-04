package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationConfirmationSupport;
import static org.assertj.core.api.Assertions.*;
class ReservationConfirmationIT extends ReservationConfirmationSupport {
    @Test void mismoClientePuedeReservarOtroTurnoSinCompartirOcupacion(){
        confirm("client","one",3).block();
        var second=java.util.UUID.randomUUID();var start=clock.instant().plusSeconds(18000);var end=start.plusSeconds(3600);
        mongo.insert(new com.brenis.SpringWebFlux.collections.RestaurantShiftCollection(second,restaurant,
            java.time.LocalDateTime.ofInstant(start,java.time.ZoneOffset.UTC).toString(),java.time.LocalDateTime.ofInstant(end,java.time.ZoneOffset.UTC).toString(),"UTC",start,end)).block();
        var next=confirm("client","two",new com.brenis.SpringWebFlux.dtos.requests.ManagedReservationRequest(second,3,"")).block();
        assertThat(next.body().tableIds()).containsExactly(table);assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);
    }
    @Test void cuentaDualReservaSoloConTitularidadPropia(){
        var result=commands.confirm(dual("dual-client"),restaurant,new com.brenis.SpringWebFlux.dtos.requests.ManagedReservationRequest(shift,2,""),
            new com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata("dual-key","dual-body",null,201,null)).block();
        assertThat(result.body().owner().subject()).isEqualTo("dual-client");assertThat(result.body().owner().issuer()).isEqualTo("https://issuer.example.test");
    }
    @Test void confirmaConSnapshotIntegroYNoOcupaOtroTurno(){
        var result=confirm("client","first",3).block();
        assertThat(result.httpStatus()).isEqualTo(201);assertThat(result.body().tableIds()).containsExactly(table);
        assertThat(result.body().version()).isEqualTo(1);assertThat(result.body().owner().subject()).isEqualTo("client");
        assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
        var reader=new com.brenis.SpringWebFlux.repositories.LegacyReservationCommitmentAdapter(mongo);
        assertThat(reader.read(restaurant,clock.instant()).block().protectedTableIds()).contains(table);
        var occupancy=new com.brenis.SpringWebFlux.repositories.ReservationOccupancyReader(mongo,reader,new com.brenis.SpringWebFlux.validators.ReservationIntegrityValidator());
        assertThat(occupancy.read(restaurant,java.util.UUID.randomUUID(),null,clock.instant()).block().tableIds()).isEmpty();
    }
    @Test void combinacionOcupaTodosSusIntegrantes(){
        var second=java.util.UUID.randomUUID();var combination=java.util.UUID.randomUUID();
        mongo.insert(new com.brenis.SpringWebFlux.collections.TableCollection(second,restaurant,"Otra","otra",4)).block();
        mongo.insert(new com.brenis.SpringWebFlux.collections.TableCombinationCollection(combination,restaurant,java.util.List.of(table,second),"fixture")).block();
        var accepted=confirm("one","one",7).block();assertThat(accepted.body().tableIds()).containsExactlyInAnyOrder(table,second);
        assertThatThrownBy(()->confirm("two","two",1).block()).hasMessageContaining("NO_AVAILABILITY");
        assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
    }
}
