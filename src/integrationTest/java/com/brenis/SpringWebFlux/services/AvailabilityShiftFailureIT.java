package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import reactor.test.StepVerifier;
import static org.assertj.core.api.Assertions.*;
class AvailabilityShiftFailureIT extends AvailabilityShiftIntegrationSupport {
    @ParameterizedTest @ValueSource(strings={"fail","delay"})
    void falloNoModificaTurnoNiZona(String mode){
        var first=createShift("first","2027-01-01T10:00:00","2027-01-01T11:00:00").block();long v=revision(),r=receiptCount();reader.mode=mode;
        try{
            StepVerifier.create(edit(first.body().id(),"edit","2027-01-01T12:00:00","2027-01-01T13:00:00",v)).expectErrorMatches(e -> e.getMessage().contains("COMMITMENT_CHECK_UNAVAILABLE")).verify();
            StepVerifier.create(shifts.replaceZone(manager,restaurant,new com.brenis.SpringWebFlux.dtos.requests.RestaurantTimeZoneRequest("UTC"),new com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata("zone-edit","zone-edit",v,200,null))).expectErrorMatches(e -> e.getMessage().contains("COMMITMENT_CHECK_UNAVAILABLE")).verify();
        }finally{reader.mode="";}
        assertThat(shifts.read(manager,restaurant,first.body().id()).block().body()).isEqualTo(first.body());assertThat(revision()).isEqualTo(v);assertThat(receiptCount()).isEqualTo(r);
        assertThat(edit(first.body().id(),"edit","2027-01-01T12:00:00","2027-01-01T13:00:00",v).block().revision()).isEqualTo(v+1);
    }
    @ParameterizedTest @ValueSource(strings={"fail","delay"})
    void esc0321_0322_falloNoDejaParcialesYReintentaMismaClave(String mode){
        reader.mode=mode;
        try{StepVerifier.create(createShift("retry","2026-11-01T22:00:00","2026-11-02T02:00:00")).expectErrorMatches(e -> e.getMessage().contains("COMMITMENT_CHECK_UNAVAILABLE")).verify();}finally{reader.mode="";}
        assertThat(shiftRepository.findAllByRestaurantId(restaurant).collectList().block()).isEmpty();assertThat(revision()).isEqualTo(1);assertThat(receiptCount()).isEqualTo(1);
        assertThat(createShift("retry","2026-11-01T22:00:00","2026-11-02T02:00:00").block().httpStatus()).isEqualTo(201);
        assertThat(revision()).isEqualTo(2);
    }
}
