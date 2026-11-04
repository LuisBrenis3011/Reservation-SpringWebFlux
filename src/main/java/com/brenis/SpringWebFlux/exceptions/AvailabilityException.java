package com.brenis.SpringWebFlux.exceptions;
public class AvailabilityException extends RuntimeException {
    private final String code;
    public AvailabilityException(String code, String message) { super(code + ": " + message); this.code=code; }
    public AvailabilityException(String code, String message, Throwable cause) { super(code+": "+message,cause); this.code=code; }
    public String code() { return code; }
}

