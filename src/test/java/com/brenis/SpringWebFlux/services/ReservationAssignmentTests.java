package com.brenis.SpringWebFlux.services;
import java.util.*;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.collections.ManagedReservationCollection.TableSnapshot;
import com.brenis.SpringWebFlux.services.impls.ReservationAssignmentPolicy;
import static org.assertj.core.api.Assertions.*;
class ReservationAssignmentTests {
    @Test void menorSobranteMenosMesasYOrdenEstable(){
        var p=new ReservationAssignmentPolicy();var a=UUID.fromString("00000000-0000-4000-8000-000000000001");
        var b=UUID.fromString("00000000-0000-4000-8000-000000000002");var c=UUID.randomUUID();
        var eight=new ReservationAssignmentPolicy.Option(null,List.of(new TableSnapshot(a,8)));
        var ten=new ReservationAssignmentPolicy.Option(null,List.of(new TableSnapshot(b,10)));
        var combined=new ReservationAssignmentPolicy.Option(c,List.of(new TableSnapshot(a,4),new TableSnapshot(b,4)));
        assertThat(p.select(List.of(ten,combined,eight),Set.of(),7).orElseThrow()).isEqualTo(eight);
        var tie=new ReservationAssignmentPolicy.Option(null,List.of(new TableSnapshot(b,8)));
        assertThat(p.select(List.of(tie,eight),Set.of(),7).orElseThrow()).isEqualTo(eight);
        assertThat(p.select(List.of(eight,tie),Set.of(),7).orElseThrow()).isEqualTo(eight);
        assertThat(p.select(List.of(combined),Set.of(a),7)).isEmpty();
    }
    @Test void overflowNoSeInterpretaComoDisponibilidad(){
        var p=new ReservationAssignmentPolicy();var option=new ReservationAssignmentPolicy.Option(UUID.randomUUID(),List.of(
            new TableSnapshot(UUID.randomUUID(),Long.MAX_VALUE),new TableSnapshot(UUID.randomUUID(),1)));
        assertThatThrownBy(()->p.select(List.of(option),Set.of(),1)).hasMessageContaining("COMMITMENT_CHECK_UNAVAILABLE");
    }
}
