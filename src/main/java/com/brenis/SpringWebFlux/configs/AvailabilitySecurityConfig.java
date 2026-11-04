package com.brenis.SpringWebFlux.configs;
import java.time.*;
import java.util.*;
import org.springframework.context.annotation.*;
import org.springframework.security.config.annotation.web.reactive.EnableWebFluxSecurity;
import org.springframework.security.config.web.server.*;
import org.springframework.security.oauth2.core.*;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.security.web.server.*;
import org.springframework.security.web.server.util.matcher.*;
import org.springframework.http.*;
import reactor.core.publisher.Mono;
@Configuration(proxyBeanMethods=false)
@EnableWebFluxSecurity
public class AvailabilitySecurityConfig {
    public OAuth2TokenValidator<Jwt> jwtValidator(AvailabilityProperties p,Clock clock) {
        JwtTimestampValidator time=new JwtTimestampValidator(Duration.ofSeconds(60)); time.setClock(clock);
        return new DelegatingOAuth2TokenValidator<>(time, jwt -> {
            boolean valid=p.getIssuerUri().equals(Objects.toString(jwt.getClaims().get("iss"),""))
                    && jwt.getAudience().contains(p.getAudience()) && jwt.getSubject()!=null && !jwt.getSubject().isBlank()
                    && jwt.getExpiresAt()!=null;
            return valid?OAuth2TokenValidatorResult.success():OAuth2TokenValidatorResult.failure(
                    new OAuth2Error("invalid_token","Claims inválidas",null));
        });
    }
    @Bean
    public SecurityWebFilterChain availabilitySecurity(ServerHttpSecurity http,AvailabilityProperties p,Clock clock) {
        List<String> paths=new ArrayList<>();
        for(String prefix:List.of("","/catalog")) for(String part:List.of("tables","table-combinations","shifts","time-zone"))
            paths.add(prefix+"/restaurants/*/"+part+"/**");
        http.securityMatcher(ServerWebExchangeMatchers.pathMatchers(paths.toArray(String[]::new)))
                .csrf(ServerHttpSecurity.CsrfSpec::disable)
                .httpBasic(ServerHttpSecurity.HttpBasicSpec::disable)
                .formLogin(ServerHttpSecurity.FormLoginSpec::disable)
                .securityContextRepository(org.springframework.security.web.server.context.NoOpServerSecurityContextRepository.getInstance());
        if(!p.isEnabled()) {
            http.addFilterAt((exchange,chain) -> jsonError(exchange,404,"NOT_FOUND",clock),SecurityWebFiltersOrder.FIRST)
                    .authorizeExchange(a -> a.anyExchange().denyAll());
        } else {
            if(p.getIssuerUri().isBlank() || p.getJwkSetUri().isBlank()) throw new IllegalStateException("issuer/JWK requeridos");
            NimbusReactiveJwtDecoder decoder=NimbusReactiveJwtDecoder.withJwkSetUri(p.getJwkSetUri())
                    .jwsAlgorithm(org.springframework.security.oauth2.jose.jws.SignatureAlgorithm.RS256).build();
            decoder.setJwtValidator(jwtValidator(p,clock));
            http.authorizeExchange(a -> a.anyExchange().authenticated())
                .oauth2ResourceServer(o -> o.jwt(j -> j.jwtDecoder(decoder))
                    .authenticationEntryPoint((exchange,error) -> jsonError(exchange,401,"UNAUTHENTICATED",clock)))
                .exceptionHandling(e -> e.accessDeniedHandler((exchange,error) -> jsonError(exchange,403,"FORBIDDEN",clock)));
        }
        return http.build();
    }
    private Mono<Void> jsonError(org.springframework.web.server.ServerWebExchange exchange,int status,String code,Clock clock) {
        exchange.getResponse().setStatusCode(HttpStatus.valueOf(status));
        exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
        String body="{\"code\":\""+code+"\",\"message\":\""+code+"\",\"status\":"+status+
                ",\"operationId\":\""+UUID.randomUUID()+"\",\"timestamp\":\""+clock.instant()+"\"}";
        return exchange.getResponse().writeWith(Mono.just(exchange.getResponse().bufferFactory()
                .wrap(body.getBytes(java.nio.charset.StandardCharsets.UTF_8))));
    }
}

