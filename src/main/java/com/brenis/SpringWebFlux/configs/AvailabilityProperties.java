package com.brenis.SpringWebFlux.configs;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.time.Duration;

/** Configuración preparatoria; los gates y consumidores se implementan en la fase 2. */
@Component
@ConfigurationProperties(prefix = "availability")
public class AvailabilityProperties {
    private boolean enabled;
    private String issuerUri = "";
    private String jwkSetUri = "";
    private String audience = "eats-hub-catalog";
    private Duration commitmentCheckTimeout = Duration.ofSeconds(3);
    private Duration transactionTimeout = Duration.ofSeconds(5);
    private int maxTransactionAttempts = 3;
    private Duration firstRetryBackoff = Duration.ofMillis(50);
    private Duration secondRetryBackoff = Duration.ofMillis(100);

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean enabled) { this.enabled = enabled; }
    public String getIssuerUri() { return issuerUri; }
    public void setIssuerUri(String issuerUri) { this.issuerUri = issuerUri; }
    public String getJwkSetUri() { return jwkSetUri; }
    public void setJwkSetUri(String jwkSetUri) { this.jwkSetUri = jwkSetUri; }
    public String getAudience() { return audience; }
    public void setAudience(String audience) { this.audience = audience; }
    public Duration getCommitmentCheckTimeout() { return commitmentCheckTimeout; }
    public void setCommitmentCheckTimeout(Duration value) { commitmentCheckTimeout = value; }
    public Duration getTransactionTimeout() { return transactionTimeout; }
    public void setTransactionTimeout(Duration value) { transactionTimeout = value; }
    public int getMaxTransactionAttempts() { return maxTransactionAttempts; }
    public void setMaxTransactionAttempts(int value) { maxTransactionAttempts = value; }
    public Duration getFirstRetryBackoff() { return firstRetryBackoff; }
    public void setFirstRetryBackoff(Duration value) { firstRetryBackoff = value; }
    public Duration getSecondRetryBackoff() { return secondRetryBackoff; }
    public void setSecondRetryBackoff(Duration value) { secondRetryBackoff = value; }
}
