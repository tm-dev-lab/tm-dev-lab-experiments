package com.tmdevlab.bank;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * In-memory digital bank: an I/O- and memory-bound Spring MVC microservice used as the workload
 * for the "jaz vs java" cloud JVM tuning experiment. It holds accounts and an append-only ledger
 * entirely on the heap, and simulates downstream I/O latency per request.
 */
@SpringBootApplication
public class BankApplication {
    public static void main(String[] args) {
        SpringApplication.run(BankApplication.class, args);
    }
}
