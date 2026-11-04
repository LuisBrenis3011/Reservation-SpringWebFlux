package com.brenis.SpringWebFlux.exceptions;

/** Mensajes públicos fijos; no incorpora entradas del cliente ni causas internas. */
public final class ShiftLocalTimeException extends AvailabilityException {
    public enum Reason {
        NONEXISTENT("La hora local no existe en la zona del restaurante."),
        AMBIGUOUS("La hora local es ambigua porque se repite en la zona del restaurante.");

        private final String message;
        Reason(String message) { this.message=message; }
    }

    private final Reason reason;

    public ShiftLocalTimeException(Reason reason) {
        super("VALIDATION_ERROR",reason.message);
        this.reason=reason;
    }

    public Reason reason() { return reason; }
    public String publicMessage() { return reason.message; }
}
