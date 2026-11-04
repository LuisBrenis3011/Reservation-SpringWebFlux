package com.brenis.SpringWebFlux.configs;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
@Component
@ConfigurationProperties(prefix="reservations")
public class ReservationProperties {
    private boolean enabled;
    public boolean isEnabled(){return enabled;}
    public void setEnabled(boolean enabled){this.enabled=enabled;}
}
