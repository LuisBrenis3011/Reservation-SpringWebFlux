package com.brenis.SpringWebFlux.services;
import java.util.*;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationReplacementSupport;
import static org.assertj.core.api.Assertions.*;

class ReservationReassignmentIT extends ReservationReplacementSupport {
    @Test void q1_conservaCombinacionAunqueAhoraBasteUnaMesa(){
        UUID second=UUID.randomUUID(),combination=UUID.randomUUID();extraTable(second,4);
        var members=java.util.stream.Stream.of(table,second).sorted(Comparator.comparing(UUID::toString)).toList();
        mongo.insert(new com.brenis.SpringWebFlux.collections.TableCombinationCollection(combination,restaurant,members,
            members.stream().map(UUID::toString).collect(java.util.stream.Collectors.joining("|")))).block();
        var first=confirm("client","combination",6).block().body();
        assertThat(first.combinationId()).isEqualTo(combination);
        var next=replace(customer("client"),first.id(),1,"reduce",shift,2,"").block().body();
        assertThat(next.combinationId()).isEqualTo(combination);assertThat(next.tableIds()).isEqualTo(members);
        assertThat(next.assignedCapacity()).isEqualTo(8);
    }
    @Test void esc0701_05_notasYGrupoSuficienteConservanAsignacionEIdentidad(){
        var first=confirm("client","initial",3).block().body();
        var next=replace(customer("client"),first.id(),1,"notes",shift,2,"Ventana").block().body();
        assertThat(next.id()).isEqualTo(first.id());assertThat(next.owner()).isEqualTo(first.owner());
        assertThat(next.restaurantId()).isEqualTo(first.restaurantId());assertThat(next.createdAt()).isEqualTo(first.createdAt());
        assertThat(next.tableIds()).isEqualTo(first.tableIds());assertThat(next.startInstant()).isEqualTo(first.startInstant());
        assertThat(next.notes()).isEqualTo("Ventana");assertThat(next.version()).isEqualTo(2);
        // Una mesa mejor aparece después; Q1 prohíbe optimizar una asignación todavía válida.
        extraTable(UUID.randomUUID(),2);
        var equivalent=replace(customer("client"),first.id(),2,"equivalent",shift,2,"Ventana").block().body();
        assertThat(equivalent.tableIds()).isEqualTo(first.tableIds());assertThat(equivalent.version()).isEqualTo(3);
        assertThat(revision()).isEqualTo(3);assertThat(receiptCount()).isEqualTo(3);
    }
    @Test void esc0706_grupoQueNoCabeReasignaSinCambiarReserva(){
        var first=confirm("client","initial",3).block().body();UUID larger=UUID.randomUUID();extraTable(larger,8);
        var next=replace(customer("client"),first.id(),1,"larger",shift,6,"").block().body();
        assertThat(next.tableIds()).containsExactly(larger);assertThat(next.assignedCapacity()).isEqualTo(8);
        assertThat(next.id()).isEqualTo(first.id());assertThat(next.version()).isEqualTo(2);
    }
    @Test void esc0707_cambiarTurnoLiberaOrigenYActualizaSnapshot(){
        var first=confirm("client","initial",3).block().body();UUID target=destination(18000);
        var next=replace(customer("client"),first.id(),1,"move",target,3,"").block().body();
        assertThat(next.shiftId()).isEqualTo(target);assertThat(next.startInstant()).isEqualTo(clock.instant().plusSeconds(18000));
        assertThat(confirm("other","released",3).block().body().tableIds()).isEqualTo(first.tableIds());
        assertThat(mongo.find(byId(first.id()),org.bson.Document.class,"reservations").collectList().block()).hasSize(1);
    }
}
