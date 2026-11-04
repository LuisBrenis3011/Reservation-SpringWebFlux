package com.brenis.SpringWebFlux.validators;

import com.brenis.SpringWebFlux.collections.TableCollection;
import com.brenis.SpringWebFlux.dtos.requests.TableCombinationRequest;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import com.brenis.SpringWebFlux.mappers.TableCombinationMapper;
import com.brenis.SpringWebFlux.collections.TableCombinationCollection;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class AvailabilityCombinationValidatorTests {
    final TableCombinationValidator validator=new TableCombinationValidator(new TableConfigurationValidator());
    final UUID owner=UUID.randomUUID(), a=UUID.randomUUID(), b=UUID.randomUUID();
    TableCombinationRequest input(UUID... ids) { return new TableCombinationRequest(Arrays.stream(ids).map(UUID::toString).toList()); }
    void invalid(TableCombinationRequest request) {
        assertThatThrownBy(() -> validator.validate(request)).isInstanceOf(AvailabilityException.class)
                .hasMessageContaining("VALIDATION_ERROR");
    }
    @Test void esc0203_0204_ordenNoDistingueConjuntosYLaClaveEsCanonica() {
        var forward=validator.validate(input(a,b));
        var reverse=validator.validate(input(b,a));
        assertThat(reverse).isEqualTo(forward);
        assertThat(forward.tableIds()).containsExactlyElementsOf(
                List.of(a,b).stream().sorted(Comparator.comparing(UUID::toString)).toList());
        assertThat(forward.memberKey()).isEqualTo(String.join(",",forward.tableIds().stream().map(UUID::toString).toList()));
    }
    @Test void esc0204_repetidosSeRechazanAntesDeConvertirEnConjunto() {
        invalid(input(a,a));
        invalid(new TableCombinationRequest(List.of(a.toString(),a.toString().toUpperCase(Locale.ROOT))));
    }
    @Test void esc0204_minimoDosSinNullNiUuidInvalido() {
        invalid(null); invalid(new TableCombinationRequest(null)); invalid(input()); invalid(input(a));
        invalid(new TableCombinationRequest(Arrays.asList(a.toString(),null)));
        invalid(new TableCombinationRequest(List.of(a.toString(),"no-es-uuid")));
        invalid(new TableCombinationRequest(List.of(a.toString(),"1-1-1-1-1")));
    }
    @Test void esc0202_0204_todosLosMiembrosDebenExistirYSerPropios() {
        var selected=validator.validate(input(a,b));
        var first=new TableCollection(a,owner,"Uno","uno",4);
        var second=new TableCollection(b,owner,"Dos","dos",2);
        validator.requireOwned(owner,selected,List.of(second,first));
        assertThatThrownBy(() -> validator.requireOwned(owner,selected,List.of(first)))
                .hasMessageContaining("VALIDATION_ERROR");
        assertThatThrownBy(() -> validator.requireOwned(owner,selected,List.of(first,
                new TableCollection(b,UUID.randomUUID(),"Ajena","ajena",2))))
                .hasMessageContaining("VALIDATION_ERROR");
        assertThatThrownBy(() -> validator.requireOwned(owner,selected,List.of(first,first)))
                .hasMessageContaining("VALIDATION_ERROR");
    }
    @Test void esc0205_mapperSumaCapacidadesSinPersistirUnaSumaParalela() {
        var selected=validator.validate(input(a,b));
        var stored=new TableCombinationCollection(UUID.randomUUID(),owner,selected.tableIds(),selected.memberKey());
        var mapper=new TableCombinationMapper(validator);
        var response=mapper.response(stored,List.of(new TableCollection(a,owner,"Uno","uno",4),
                new TableCollection(b,owner,"Dos","dos",2)),7);
        assertThat(response.capacity()).isEqualTo(6);
        assertThat(response.revision()).isEqualTo(7);
        assertThat(response.tableIds()).containsExactlyElementsOf(selected.tableIds());
    }
    @Test void sumaExactaRechazaOverflowSinTruncarInt64() {
        assertThatThrownBy(() -> validator.sum(List.of(new TableCollection(a,owner,"Uno","uno",Long.MAX_VALUE),
                new TableCollection(b,owner,"Dos","dos",1))))
                .isInstanceOf(AvailabilityException.class).hasMessageContaining("VALIDATION_ERROR");
    }
    @Test void putAdmiteConjuntoCompletoDeCardinalidadDistintaSinModificarElAnterior() {
        UUID third=UUID.randomUUID(), fourth=UUID.randomUUID();
        var current=validator.validate(input(a,b,third));
        var fewer=validator.validate(input(b,a));
        var more=validator.validate(input(fourth,third,b,a));
        assertThat(current.tableIds()).hasSize(3);
        assertThat(fewer.tableIds()).hasSize(2);
        assertThat(more.tableIds()).hasSize(4);
        assertThat(fewer.memberKey()).isNotEqualTo(current.memberKey());
        assertThat(more.memberKey()).isNotEqualTo(current.memberKey());
        assertThat(validator.validate(input(third,b,a))).isEqualTo(current);
    }
    @Test void putNoAceptaMiembroAjenoAunqueElOtroYaPertenezcaAlConjuntoActual() {
        UUID third=UUID.randomUUID();
        var selected=validator.validate(input(a,third));
        assertThatThrownBy(() -> validator.requireOwned(owner,selected,List.of(
                new TableCollection(a,owner,"Actual","actual",4),
                new TableCollection(third,UUID.randomUUID(),"Ajena","ajena",3))))
                .hasMessageContaining("VALIDATION_ERROR");
    }
}
