package com.brenis.SpringWebFlux.services;
import java.time.Clock;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import com.brenis.SpringWebFlux.support.ReservationIdentityFixture;
import com.brenis.SpringWebFlux.services.impls.*;
import static org.mockito.Mockito.*;
import static org.assertj.core.api.Assertions.*;
class ReservationQueryAuthorizationTests {
    @Test void perfilesSinPermisoNoConsultanMongoParaNingunId(){
        var mongo=mock(org.springframework.data.mongodb.core.ReactiveMongoTemplate.class);
        var tx=mock(org.springframework.transaction.reactive.TransactionalOperator.class);
        var mapper=mock(com.brenis.SpringWebFlux.mappers.ManagedReservationMapper.class);
        var legacy=mock(com.brenis.SpringWebFlux.repositories.LegacyReservationQueryRepository.class);
        var query=new ReservationQueryServiceImpl(mongo,tx,new ReservationAccessPolicy(),mapper,legacy,new com.brenis.SpringWebFlux.configs.AvailabilityProperties());
        var owner=UUID.randomUUID();
        var manager=new JwtAuthenticationToken(ReservationIdentityFixture.manager(UUID.randomUUID(),Clock.systemUTC()),List.of(new SimpleGrantedAuthority("ROLE_RESTAURANT_MANAGER")));
        var noRoleJwt=org.springframework.security.oauth2.jwt.Jwt.withTokenValue("test").header("alg","RS256").issuer("https://issuer.example.test").subject("sin-rol").claim("roles",List.of()).build();
        var noRole=new JwtAuthenticationToken(noRoleJwt,List.of());
        for(var principal:List.of(manager,noRole))for(var id:List.of(UUID.randomUUID(),UUID.randomUUID()))
            assertThatThrownBy(()->query.managed(principal,owner,id).block()).hasMessageContaining("FORBIDDEN");
        verifyNoInteractions(mongo,tx,mapper,legacy);
    }
}
