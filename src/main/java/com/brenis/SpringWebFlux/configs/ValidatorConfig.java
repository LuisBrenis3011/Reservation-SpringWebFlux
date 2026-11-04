package com.brenis.SpringWebFlux.configs;

import jakarta.annotation.PreDestroy;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;
import org.springframework.context.annotation.Bean;

public class ValidatorConfig {

    private ValidatorFactory validatorFactory;

    @Bean
    public Validator validator(){
        this.validatorFactory = Validation.buildDefaultValidatorFactory();
        return validatorFactory.getValidator();
    }

    @PreDestroy
    public void destroy(){
        if(this.validatorFactory != null){
            this.validatorFactory.close();
        }
    }
}
