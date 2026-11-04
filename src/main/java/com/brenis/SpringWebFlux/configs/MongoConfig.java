package com.brenis.SpringWebFlux.configs;
import com.mongodb.*;
import com.mongodb.reactivestreams.client.*;
import org.bson.UuidRepresentation;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.data.mongodb.*;
import org.springframework.data.mongodb.core.*;
import org.springframework.data.mongodb.repository.config.EnableReactiveMongoRepositories;
import org.springframework.transaction.reactive.*;
import reactor.core.publisher.Mono;
import java.time.Duration;
import java.util.concurrent.TimeUnit;
import com.brenis.SpringWebFlux.exceptions.AvailabilityException;
@Configuration(proxyBeanMethods=false)
@PropertySource("classpath:mongo-connection.properties")
@EnableReactiveMongoRepositories("com.brenis.SpringWebFlux.repositories")
public class MongoConfig {
    @Bean(destroyMethod="close")
    public MongoClient reactiveMongoClient(
            @Value("${mongodb.uri:}") String uri,@Value("${mongodb.host}") String host,
            @Value("${mongodb.port}") int port,@Value("${mongodb.database}") String database,
            @Value("${mongodb.username}") String user,@Value("${mongodb.password}") String password,
            @Value("${mongodb.authentication-database}") String auth,
            @Value("${mongodb.maxPoolSize}") int max,@Value("${mongodb.minPoolSize}") int min,
            @Value("${mongodb.maxConnectionLifeTime}") long lifetime) {
        var settings=MongoClientSettings.builder().uuidRepresentation(UuidRepresentation.STANDARD)
                .applyConnectionString(new ConnectionString(uri.isBlank()?"mongodb://"+host+":"+port+"/"+database:uri))
                .applyToConnectionPoolSettings(p -> p.maxSize(max).minSize(min).maxConnectionLifeTime(lifetime,TimeUnit.MILLISECONDS))
                .applyToClusterSettings(c -> c.serverSelectionTimeout(5,TimeUnit.SECONDS));
        if(uri.isBlank()) settings.credential(MongoCredential.createCredential(user,auth,password.toCharArray()));
        return MongoClients.create(settings.build());
    }
    @Bean public ReactiveMongoDatabaseFactory reactiveMongoDatabaseFactory(MongoClient client,
            @Value("${mongodb.database}") String database) { return new SimpleReactiveMongoDatabaseFactory(client,database); }
    @Bean public ReactiveMongoTemplate reactiveMongoTemplate(ReactiveMongoDatabaseFactory factory) {
        return new ReactiveMongoTemplate(factory);
    }
    @Bean public ReactiveMongoTransactionManager transactionManager(ReactiveMongoDatabaseFactory factory,AvailabilityProperties properties) {
        return new AvailabilityTransactionManager(factory,properties.getTransactionTimeout());
    }
    @Bean public TransactionalOperator transactionalOperator(ReactiveMongoTransactionManager manager) {
        return TransactionalOperator.create(manager);
    }
    public static boolean hasLabel(Throwable error,String label) {
        for(Throwable e=error;e!=null;e=e.getCause()) if(e instanceof MongoException m && m.hasErrorLabel(label)) return true;
        return false;
    }
    /** Reintenta SOLO commit sobre la misma sesión; nunca vuelve a ejecutar el callback. */
    public static class AvailabilityTransactionManager extends ReactiveMongoTransactionManager {
        private final Duration budget;
        public AvailabilityTransactionManager(ReactiveMongoDatabaseFactory factory,Duration budget) {
            super(factory,TransactionOptions.builder().readConcern(ReadConcern.SNAPSHOT)
                    .writeConcern(WriteConcern.MAJORITY).readPreference(ReadPreference.primary()).build());
            this.budget=budget;
        }
        @Override protected Mono<Void> doCommit(TransactionSynchronizationManager manager,
                                                 ReactiveMongoTransactionObject transaction) {
            return Mono.deferContextual(context -> Mono.defer(() -> super.doCommit(manager,transaction))
                    .retryWhen(reactor.util.retry.Retry.fixedDelay(Long.MAX_VALUE,Duration.ofMillis(50))
                            .filter(e -> hasLabel(e,"UnknownTransactionCommitResult")))
                    .timeout(Duration.ofNanos(Math.max(1L,context.<Long>getOrDefault("availability.deadline",System.nanoTime()+budget.toNanos())-System.nanoTime())))
                    .onErrorMap(e -> hasLabel(e,"UnknownTransactionCommitResult") || e instanceof java.util.concurrent.TimeoutException
                            ?new AvailabilityException("OPERATION_OUTCOME_UNKNOWN","Repetir la misma Idempotency-Key",e):e));
        }
    }
}
