package com.brenis.SpringWebFlux.services;

import com.brenis.SpringWebFlux.collections.TableCollection;
import com.brenis.SpringWebFlux.mappers.TableAvailabilityMapper;
import com.brenis.SpringWebFlux.validators.TableConfigurationValidator;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class AvailabilityTableReadTests {
    final TableAvailabilityMapper mapper = new TableAvailabilityMapper(new TableConfigurationValidator());
    @Test void esc0105_0115_sumaMesasFisicasUnaVezConRevisionComun() {
        UUID owner=UUID.randomUUID(), first=UUID.randomUUID(), second=UUID.randomUUID();
        var result=mapper.list(List.of(new TableCollection(first,owner,"Uno","uno",4),
                new TableCollection(second,owner,"Dos","dos",2)),7);
        assertThat(result.totalCapacity()).isEqualTo(6);
        assertThat(result.revision()).isEqualTo(7);
        assertThat(result.items()).extracting(t -> t.id()).containsExactly(first,second);
        assertThat(result.items()).allSatisfy(t -> {
            assertThat(t.restaurantId()).isEqualTo(owner);
            assertThat(t.revision()).isEqualTo(result.revision());
        });
    }
    @Test void esc0106_0116_coleccionVaciaNoInventaPlazas() {
        var result=mapper.list(List.of(),0);
        assertThat(result.items()).isEmpty();
        assertThat(result.totalCapacity()).isZero();
        assertThat(result.revision()).isZero();
    }
    @Test void totalNoPuedeDesbordarseSilenciosamente() {
        UUID owner=UUID.randomUUID();
        assertThatThrownBy(() -> mapper.list(List.of(
                new TableCollection(UUID.randomUUID(),owner,"A","a",Long.MAX_VALUE),
                new TableCollection(UUID.randomUUID(),owner,"B","b",1)),1))
                .hasMessageContaining("VALIDATION_ERROR");
    }
}

