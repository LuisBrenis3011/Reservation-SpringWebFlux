package com.brenis.SpringWebFlux.configs;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.context.annotation.*;

@Configuration(proxyBeanMethods=false)
public class AvailabilityMetricsConfig {
    @Bean @ConditionalOnMissingBean(MeterRegistry.class)
    public MeterRegistry availabilityMeterRegistry() { return new SimpleMeterRegistry(); }
}

