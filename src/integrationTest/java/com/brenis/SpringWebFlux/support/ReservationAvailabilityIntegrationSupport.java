package com.brenis.SpringWebFlux.support;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;
import com.brenis.SpringWebFlux.services.definitions.ReservationAvailabilityService;
@SpringJUnitConfig(ReservationAvailabilityIntegrationSupport.Configuration.class)
public abstract class ReservationAvailabilityIntegrationSupport extends ReservationConfirmationSupport {
    @org.springframework.context.annotation.Configuration(proxyBeanMethods=false)
    @org.springframework.context.annotation.Import({ReservationConfirmationSupport.Configuration.class,
        com.brenis.SpringWebFlux.services.impls.ReservationAvailabilityServiceImpl.class})
    public static class Configuration {}
    @Autowired protected ReservationAvailabilityService availability;
    protected java.time.LocalDate day(){return java.time.LocalDate.ofInstant(clock.instant(),java.time.ZoneOffset.UTC);}
}
