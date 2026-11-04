package com.brenis.SpringWebFlux.services;
import com.brenis.SpringWebFlux.support.AvailabilityMongoFixture;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.bson.Document;
import reactor.test.StepVerifier;
import static org.assertj.core.api.Assertions.*;
class AvailabilityShiftLegacyIT extends AvailabilityShiftIntegrationSupport {
    @ParameterizedTest @ValueSource(booleans={false,true})
    void esc0323_0324_legadoStringOBinarioPermiteConsultaBloqueaAlta(boolean binary){
        var saved=createShift("before","2026-11-01T22:00:00","2026-11-02T02:00:00").block();
        var fixture=AvailabilityMongoFixture.unresolvedLegacy(restaurant,binary,"CONFIRMED");mongo.insert(fixture,"reservations").block();
        var before=mongo.findById(fixture.get("_id"),Document.class,"reservations").block();
        assertThat(shifts.read(manager,restaurant,saved.body().id()).block().body()).isEqualTo(saved.body());
        StepVerifier.create(createShift("blocked","2026-11-02T03:00:00","2026-11-02T04:00:00")).expectErrorMatches(e -> e.getMessage().contains("LEGACY_RESERVATION_BLOCK")).verify();
        StepVerifier.create(edit(saved.body().id(),"blocked-edit","2026-11-02T03:00:00","2026-11-02T04:00:00",revision())).expectErrorMatches(e -> e.getMessage().contains("LEGACY_RESERVATION_BLOCK")).verify();
        StepVerifier.create(shifts.replaceZone(manager,restaurant,new com.brenis.SpringWebFlux.dtos.requests.RestaurantTimeZoneRequest("UTC"),new com.brenis.SpringWebFlux.dtos.AvailabilityHttpModels.CommandMetadata("blocked-zone","blocked-zone",revision(),200,null))).expectErrorMatches(e -> e.getMessage().contains("LEGACY_RESERVATION_BLOCK")).verify();
        assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(2);assertThat(shiftRepository.findAllByRestaurantId(restaurant).collectList().block()).hasSize(1);
        assertThat(mongo.findById(fixture.get("_id"),Document.class,"reservations").block()).isEqualTo(before);
    }
}
