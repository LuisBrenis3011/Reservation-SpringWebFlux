package com.brenis.SpringWebFlux.support;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Objects;
import java.util.concurrent.atomic.AtomicReference;

/** Reloj controlable; withZone comparte el mismo instante con la instancia original. */
public final class AvailabilityClockFixture extends Clock {
    private final AtomicReference<Instant> current;
    private final ZoneId zone;

    public AvailabilityClockFixture(Instant initial) {
        this(new AtomicReference<>(Objects.requireNonNull(initial)), ZoneOffset.UTC);
    }

    private AvailabilityClockFixture(AtomicReference<Instant> current, ZoneId zone) {
        this.current = current;
        this.zone = Objects.requireNonNull(zone);
    }

    public void set(Instant instant) { current.set(Objects.requireNonNull(instant)); }
    public void advance(Duration duration) { current.updateAndGet(value -> value.plus(duration)); }
    @Override public ZoneId getZone() { return zone; }
    @Override public Clock withZone(ZoneId zone) { return new AvailabilityClockFixture(current, zone); }
    @Override public Instant instant() { return current.get(); }
}
