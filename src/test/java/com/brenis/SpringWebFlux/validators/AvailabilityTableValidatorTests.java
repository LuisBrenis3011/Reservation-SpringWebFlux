package com.brenis.SpringWebFlux.validators;

import com.brenis.SpringWebFlux.dtos.requests.TableCreateRequest;
import com.brenis.SpringWebFlux.dtos.requests.TablePatchRequest;
import com.brenis.SpringWebFlux.collections.TableCollection;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.*;
import static org.assertj.core.api.Assertions.*;

class AvailabilityTableValidatorTests {
    final TableConfigurationValidator validator = new TableConfigurationValidator();

    @Test void esc0103_normalizaEtiquetaSinCambiarIdentidadSemantica() {
        var value = validator.validate(new TableCreateRequest("  Mesa I  ", 4L));
        assertThat(value.label()).isEqualTo("Mesa I");
        assertThat(value.labelKey()).isEqualTo("mesa i");
        assertThat(value.capacity()).isEqualTo(4);
    }
    @ParameterizedTest @NullAndEmptySource @ValueSource(strings={" ", "   "})
    void esc0104_rechazaEtiquetaAusenteOVacia(String label) {
        assertThatThrownBy(() -> validator.validate(new TableCreateRequest(label,4L)))
                .isInstanceOf(AvailabilityException.class).hasMessageContaining("VALIDATION_ERROR");
    }
    @ParameterizedTest @NullSource @ValueSource(longs={0,-1,Long.MIN_VALUE})
    void esc0104_rechazaCapacidadAusenteONoPositiva(Long capacity) {
        assertThatThrownBy(() -> validator.validate(new TableCreateRequest("Mesa",capacity)))
                .hasMessageContaining("VALIDATION_ERROR");
    }
    @Test void noInventaLimiteDeNegocioPeroRechazaDesbordamiento() {
        assertThat(validator.validate(new TableCreateRequest("Grande",Long.MAX_VALUE)).capacity())
                .isEqualTo(Long.MAX_VALUE);
        assertThatThrownBy(() -> validator.addCapacity(Long.MAX_VALUE,1))
                .hasMessageContaining("VALIDATION_ERROR");
    }
    @Test void esc0107_patchDeEtiquetaConservaCamposOmitidosEIdentidad() {
        var original=new TableCollection(java.util.UUID.randomUUID(),java.util.UUID.randomUUID(),"Mesa","mesa",4);
        var updated=validator.patch(original,new TablePatchRequest("  Ventana  ",null));
        assertThat(updated.id()).isEqualTo(original.id());
        assertThat(updated.restaurantId()).isEqualTo(original.restaurantId());
        assertThat(updated.label()).isEqualTo("Ventana");
        assertThat(updated.labelKey()).isEqualTo("ventana");
        assertThat(updated.capacity()).isEqualTo(4);
    }
    @Test void esc0107_patchDeCapacidadConservaEtiquetaYNoInventaLimite() {
        var original=new TableCollection(java.util.UUID.randomUUID(),java.util.UUID.randomUUID(),"Mesa","mesa",4);
        var updated=validator.patch(original,new TablePatchRequest(null,Long.MAX_VALUE));
        assertThat(updated.label()).isEqualTo(original.label());
        assertThat(updated.labelKey()).isEqualTo(original.labelKey());
        assertThat(updated.capacity()).isEqualTo(Long.MAX_VALUE);
    }
    @Test void patchSinCamposNoRepresentaUnaActualizacionValida() {
        assertThatThrownBy(() -> new TablePatchRequest(null,null)).hasMessageContaining("INVALID_REQUEST");
    }
}

