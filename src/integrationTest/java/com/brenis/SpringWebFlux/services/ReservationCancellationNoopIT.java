package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationCancellationSupport;
import static org.assertj.core.api.Assertions.*;
class ReservationCancellationNoopIT extends ReservationCancellationSupport {
    @Test void esc0805_otroIdentificadorFueraDePlazoNoCambiaDocumentoNiRevision(){
        var first=confirm("client","first",2).block().body();var cancelled=cancel(customer("client"),first.id(),1,"cancel").block();
        var row=raw(first.id());long revision=revision();long receipts=receiptCount();var initial=clock.instant();
        try{
            clock.advance(java.time.Duration.ofDays(1));
            var again=cancel(customer("client"),first.id(),0,"new-key").block();
            assertThat(again.body()).isEqualTo(cancelled.body());assertThat(again.revision()).isEqualTo(cancelled.revision());
            assertThat(raw(first.id())).isEqualTo(row);assertThat(revision()).isEqualTo(revision);assertThat(receiptCount()).isEqualTo(receipts+1);
            var stable=state();assertThat(cancel(customer("client"),first.id(),0,"new-key").block()).isEqualTo(again);assertThat(state()).isEqualTo(stable);
            assertThat(cancel(customer("client"),first.id(),1,"cancel").block()).isEqualTo(cancelled);assertThat(state()).isEqualTo(stable);
        }finally{clock.set(initial);}
    }
    @Test void esc0806_noReactivaNiOmiteAutorizacionActual(){
        var first=confirm("client","first",2).block().body();cancel(customer("client"),first.id(),1,"cancel").block();var before=state();
        assertThatThrownBy(()->replace(customer("client"),first.id(),2,"edit",shift,2,"").block()).hasMessageContaining("RESERVATION_NOT_EDITABLE");
        assertThatThrownBy(()->cancel(otherCustomer(),first.id(),0,"cancel").block()).hasMessageContaining("NOT_FOUND");
        assertThatThrownBy(()->cancel(customer("client"),first.id(),2,"cancel").block()).hasMessageContaining("IDEMPOTENCY_CONFLICT");
        assertThat(state()).isEqualTo(before);
    }
    @Test void permisoRetiradoNoRecuperaReciboDeEncargado(){
        var first=confirm("client","first",2).block().body();cancel(manager,first.id(),1,"manager").block();var before=state();
        var jwt=((org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken)manager).getToken();
        var revoked=new org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken(
            org.springframework.security.oauth2.jwt.Jwt.withTokenValue("test-revoked").header("alg","RS256")
                .claims(claims->claims.putAll(jwt.getClaims())).claim("roles",java.util.List.of("CUSTOMER")).build(),
            java.util.List.of(new org.springframework.security.core.authority.SimpleGrantedAuthority("ROLE_CUSTOMER")));
        assertThatThrownBy(()->cancel(revoked,first.id(),1,"manager").block()).hasMessageContaining("NOT_FOUND");assertThat(state()).isEqualTo(before);
    }
    @Test void falloDeReciboNoopNoCambiaRevisionNiHistoria(){
        var first=confirm("client","first",2).block().body();cancel(customer("client"),first.id(),1,"cancel").block();var before=state();
        admin(new org.bson.Document("configureFailPoint","failCommand").append("mode",new org.bson.Document("times",1))
            .append("data",new org.bson.Document("failCommands",java.util.List.of("insert")).append("errorCode",2))).block();
        try{assertThatThrownBy(()->cancel(customer("client"),first.id(),0,"noop").block()).hasMessageContaining("DEPENDENCY_UNAVAILABLE");}
        finally{admin(new org.bson.Document("configureFailPoint","failCommand").append("mode","off")).block();}
        assertThat(state()).isEqualTo(before);var row=raw(first.id());
        cancel(customer("client"),first.id(),0,"noop").block();assertThat(raw(first.id())).isEqualTo(row);assertThat(revision()).isEqualTo(2);assertThat(receiptCount()).isEqualTo(3);
    }
}
