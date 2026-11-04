package com.brenis.SpringWebFlux.validators;

import reactor.core.publisher.Mono;

import java.util.function.Function;

@FunctionalInterface
public interface BusinessValidator<T> {
    Mono<Void> validate(T input);
}
