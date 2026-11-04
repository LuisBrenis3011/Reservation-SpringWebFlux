package com.brenis.SpringWebFlux.configs;
import java.time.Clock;
import org.springframework.context.annotation.*;
import org.springframework.core.annotation.Order;
import org.springframework.security.config.web.server.*;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.web.server.*;
import org.springframework.security.web.server.util.matcher.ServerWebExchangeMatchers;
import org.springframework.http.*;
import reactor.core.publisher.Mono;

@Configuration(proxyBeanMethods=false)
public class ReservationSecurityConfig {
    @Bean @Order(-10)
    public SecurityWebFilterChain reservationSecurity(ServerHttpSecurity http,ReservationProperties reservations,AvailabilityProperties availability,Clock clock){
        http.securityMatcher(ServerWebExchangeMatchers.pathMatchers("/reservation/**","/catalog/reservation/**","/me/reservations/**","/catalog/me/reservations/**",
            "/restaurants/*/reservations/**","/catalog/restaurants/*/reservations/**","/restaurants/*/availability","/catalog/restaurants/*/availability"))
            .csrf(ServerHttpSecurity.CsrfSpec::disable).httpBasic(ServerHttpSecurity.HttpBasicSpec::disable).formLogin(ServerHttpSecurity.FormLoginSpec::disable)
            .securityContextRepository(org.springframework.security.web.server.context.NoOpServerSecurityContextRepository.getInstance());
        http.addFilterAt((exchange,chain)->{
            String path=exchange.getRequest().getPath().value().replaceFirst("^/catalog(?=/)","");
            if(!reservations.isEnabled()&&!path.startsWith("/reservation")){
                exchange.getResponse().setStatusCode(HttpStatus.NOT_FOUND);return exchange.getResponse().setComplete();
            }
            return chain.filter(exchange);
        },SecurityWebFiltersOrder.FIRST);
        ReactiveJwtDecoder decoder;
        if(availability.getJwkSetUri().isBlank())decoder=token->Mono.error(new BadJwtException("Emisor local no configurado"));
        else {
            var jwt=NimbusReactiveJwtDecoder.withJwkSetUri(availability.getJwkSetUri()).jwsAlgorithm(SignatureAlgorithm.RS256).build();
            jwt.setJwtValidator(new AvailabilitySecurityConfig().jwtValidator(availability,clock));decoder=jwt;
        }
        var converter=new org.springframework.security.oauth2.server.resource.authentication.ReactiveJwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(jwt->{java.util.List<String> roles=jwt.getClaimAsStringList("roles");
            return reactor.core.publisher.Flux.fromIterable(roles==null?java.util.List.<String>of():roles)
                .map(role->new org.springframework.security.core.authority.SimpleGrantedAuthority("ROLE_"+role));});
        http.authorizeExchange(a->a.pathMatchers(HttpMethod.GET,"/restaurants/*/availability","/catalog/restaurants/*/availability").permitAll()
            .pathMatchers(HttpMethod.GET,"/reservation/**","/catalog/reservation/**").hasRole("RESTAURANT_MANAGER").anyExchange().authenticated())
            .oauth2ResourceServer(o->o.jwt(j->j.jwtDecoder(decoder).jwtAuthenticationConverter(converter)).authenticationEntryPoint((exchange,error)->error(exchange,401,"UNAUTHENTICATED",clock)))
            .exceptionHandling(e->e.accessDeniedHandler((exchange,error)->error(exchange,403,"FORBIDDEN",clock)));
        return http.build();
    }
    private Mono<Void> error(org.springframework.web.server.ServerWebExchange exchange,int status,String code,Clock clock){
        exchange.getResponse().setStatusCode(HttpStatus.valueOf(status));exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
        String body="{\"code\":\""+code+"\",\"message\":\""+code+"\",\"status\":"+status+",\"operationId\":\""+java.util.UUID.randomUUID()+"\",\"timestamp\":\""+clock.instant()+"\"}";
        return exchange.getResponse().writeWith(Mono.just(exchange.getResponse().bufferFactory().wrap(body.getBytes(java.nio.charset.StandardCharsets.UTF_8))));
    }
}
