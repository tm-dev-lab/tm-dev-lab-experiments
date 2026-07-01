package com.tmdevlab.bank.model;

import java.util.ArrayList;
import java.util.List;

/**
 * An in-memory account: a balance plus an append-only ledger. All access goes through the
 * synchronized methods; transfers across two accounts are ordered by id in {@code BankStore} to
 * avoid deadlock. The growing ledger is what keeps a realistic working set on the heap.
 */
public final class Account {

    private final long id;
    private long balanceCents;
    private final List<Transaction> ledger = new ArrayList<>(4);

    public Account(long id, long openingCents) {
        this.id = id;
        this.balanceCents = openingCents;
    }

    public long id() {
        return id;
    }

    public synchronized long balanceCents() {
        return balanceCents;
    }

    public synchronized int ledgerSize() {
        return ledger.size();
    }

    public synchronized void record(long newBalanceCents, Transaction t) {
        this.balanceCents = newBalanceCents;
        this.ledger.add(t);
    }

    /** Returns a fresh copy of the last {@code limit} entries (allocation under read load). */
    public synchronized List<Transaction> recent(int limit) {
        int n = ledger.size();
        int from = limit <= 0 ? n : Math.max(0, n - limit);
        return new ArrayList<>(ledger.subList(from, n));
    }
}
