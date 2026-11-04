package com.brenis.SpringWebFlux.services;
import org.junit.jupiter.api.Test;
import com.brenis.SpringWebFlux.support.ReservationReplacementSupport;
import static org.assertj.core.api.Assertions.*;

class ReservationReplaceReplayIT extends ReservationReplacementSupport {
    @Test void esc0711_12_replayHistoricoYConflictoSinEfectos(){
        var original=confirm("client","first",3).block().body();
        var accepted=replace(customer("client"),original.id(),1,"edit",shift,3,"Uno").block();
        replace(customer("client"),original.id(),2,"later",shift,3,"Dos").block();var before=state();
        assertThat(replace(customer("client"),original.id(),1,"edit",shift,3,"Uno").block()).isEqualTo(accepted);
        assertThat(state()).isEqualTo(before);
        assertThatThrownBy(()->replace(customer("client"),original.id(),1,"edit",shift,2,"Otro").block()).hasMessageContaining("IDEMPOTENCY_CONFLICT");
        assertThat(state()).isEqualTo(before);
        var instant=clock.instant();
        try{
            clock.advance(java.time.Duration.ofHours(4));
            assertThat(replace(customer("client"),original.id(),1,"edit",shift,3,"Uno").block()).isEqualTo(accepted);
            assertThat(state()).isEqualTo(before);
        }finally{clock.set(instant);}
    }
    @Test void replayNoOmitePermisosActuales(){
        var original=confirm("client","first",3).block().body();
        replace(manager,original.id(),1,"manager",shift,3,"Uno").block();var before=state();
        var jwt=((org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken)manager).getToken();
        var formerManager=new org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken(
            org.springframework.security.oauth2.jwt.Jwt.withTokenValue("test-revoked-manager").header("alg","RS256")
                .claims(claims->claims.putAll(jwt.getClaims())).claim("roles",java.util.List.of("CUSTOMER")).build(),
            java.util.List.of(new org.springframework.security.core.authority.SimpleGrantedAuthority("ROLE_CUSTOMER")));
        assertThatThrownBy(()->replace(formerManager,original.id(),1,"manager",shift,3,"Uno").block()).hasMessageContaining("NOT_FOUND");
        assertThat(state()).isEqualTo(before);
    }
}
