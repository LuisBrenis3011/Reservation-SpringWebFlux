package com.brenis.SpringWebFlux.configs;

import com.brenis.SpringWebFlux.dtos.responses.RestaurantResponse;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.event.EventListener;
import org.springframework.data.redis.connection.RedisStandaloneConfiguration;
import org.springframework.data.redis.connection.lettuce.LettuceClientConfiguration;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.ReactiveRedisTemplate;

import org.springframework.data.redis.serializer.JacksonJsonRedisSerializer;
import org.springframework.data.redis.serializer.RedisSerializationContext;
import org.springframework.data.redis.serializer.StringRedisSerializer;
import tools.jackson.databind.DeserializationFeature;
import tools.jackson.databind.JavaType;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.cfg.DateTimeFeature;
import tools.jackson.databind.json.JsonMapper;

import java.time.Duration;
import java.util.List;

@Configuration
//@EnableCaching
@Slf4j
public class RedisConfig {

    @Value("${REDIS_HOST:localhost}")
    private String redisHost;

    @Value("${REDIS_PORT:6379}")
    private int redisPort;

    @Value("${REDIS_PASSWORD}")
    private String redisPassword;

    @Value("${REDIS_DATABASE:0}")
    private int redisDatabase;

    @Bean
    public LettuceConnectionFactory lettuceConnectionFactory() {
        log.info("Connecting to Redis: {}, {}", redisHost, redisPort);

        RedisStandaloneConfiguration redisConfig =
                new RedisStandaloneConfiguration(redisHost, redisPort);

        redisConfig.setPassword(redisPassword);
        redisConfig.setDatabase(redisDatabase);

        LettuceClientConfiguration clientConfig = LettuceClientConfiguration.builder()
                .commandTimeout(Duration.ofSeconds(3))
                .shutdownTimeout(Duration.ofMillis(150))
                .build();

        return new LettuceConnectionFactory(redisConfig, clientConfig);
    }

    @Bean
    public ReactiveRedisTemplate<String, RestaurantResponse> reactiveRedisTemplate(
            LettuceConnectionFactory connectionFactory) {

        JacksonJsonRedisSerializer<RestaurantResponse> serializer =
                new JacksonJsonRedisSerializer<>(createObjectMapper(), RestaurantResponse.class);

        RedisSerializationContext<String, RestaurantResponse> context =
                RedisSerializationContext.<String, RestaurantResponse>newSerializationContext()
                        .key(StringRedisSerializer.UTF_8)
                        .value(serializer)
                        .hashKey(StringRedisSerializer.UTF_8)
                        .hashValue(serializer)
                        .build();

        return new ReactiveRedisTemplate<>(connectionFactory, context);
    }

    @Bean
    public ReactiveRedisTemplate<String, List<RestaurantResponse>> reactiveRedisListTemplate(
            LettuceConnectionFactory connectionFactory) {

        ObjectMapper objectMapper = createObjectMapper();
        JavaType type = objectMapper.getTypeFactory()
                .constructCollectionType(List.class, RestaurantResponse.class);

        JacksonJsonRedisSerializer<List<RestaurantResponse>> serializer =
                new JacksonJsonRedisSerializer<>(objectMapper, type);

        RedisSerializationContext<String, List<RestaurantResponse>> context =
                RedisSerializationContext.<String, List<RestaurantResponse>>newSerializationContext()
                        .key(StringRedisSerializer.UTF_8)
                        .value(serializer)
                        .hashKey(StringRedisSerializer.UTF_8)
                        .hashValue(serializer)
                        .build();

        return new ReactiveRedisTemplate<>(connectionFactory, context);
    }

    @EventListener(ApplicationReadyEvent.class)
    public void verifyRedisConnection() {
        log.info("Connection successfully established.");
    }

    private ObjectMapper createObjectMapper() {
        return JsonMapper.builder()
                .disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
                .disable(DateTimeFeature.WRITE_DATES_AS_TIMESTAMPS)
                .build();
    }
}
