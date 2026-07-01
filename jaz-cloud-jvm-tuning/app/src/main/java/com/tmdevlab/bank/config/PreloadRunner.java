package com.tmdevlab.bank.config;

import com.tmdevlab.bank.store.BankStore;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

import java.util.concurrent.ThreadLocalRandom;

/**
 * Preloads a warm working set at startup (accounts + ledger entries) so the heap holds a realistic
 * amount of live data. This is deliberate: without retained state, heap sizing and GC choice barely
 * matter, and the experiment would be measuring almost-empty JVMs.
 */
@Component
public class PreloadRunner implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(PreloadRunner.class);

    private final BankStore store;
    private final int accounts;
    private final int txPerAccount;

    public PreloadRunner(BankStore store,
                         @Value("${bank.preload-accounts:100000}") int accounts,
                         @Value("${bank.preload-tx-per-account:8}") int txPerAccount) {
        this.store = store;
        this.accounts = accounts;
        this.txPerAccount = txPerAccount;
    }

    @Override
    public void run(ApplicationArguments args) {
        long start = System.nanoTime();
        ThreadLocalRandom rnd = ThreadLocalRandom.current();
        for (int i = 0; i < accounts; i++) {
            long id = store.open(100_00 + rnd.nextLong(0, 1_000_00));
            for (int j = 0; j < txPerAccount; j++) {
                store.deposit(id, rnd.nextLong(1_00, 500_00), "seed");
            }
        }
        long ms = (System.nanoTime() - start) / 1_000_000;
        log.info("Preloaded {} accounts x {} tx ({} ledger entries) in {} ms",
                accounts, txPerAccount, (long) accounts * txPerAccount, ms);
    }
}
