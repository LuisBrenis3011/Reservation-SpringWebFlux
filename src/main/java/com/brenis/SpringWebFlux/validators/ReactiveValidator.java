package com.brenis.SpringWebFlux.validators;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.ValidationException;
import jakarta.validation.Validator;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.util.stream.Collectors;

@Component
@RequiredArgsConstructor
public class ReactiveValidator {

    private final Validator validator;

    public <T> Mono<T> validate(T object) {
        final var setValidation = this.validator.validate(object);
        if (setValidation.isEmpty()) {
            return Mono.just(object);
        }

        final var errors = setValidation.stream()
                .map(ConstraintViolation::getMessage)
                .collect(Collectors.joining(","));

        return Mono.error(new ValidationException(errors));
    }

}
