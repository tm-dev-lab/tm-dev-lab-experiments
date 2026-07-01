package com.tmdevlab.bank.store;

import com.tmdevlab.bank.model.Account;
import com.tmdevlab.bank.model.Transaction;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Thread-safe in-memory bank. Single-account operations lock the account; transfers lock both
 * accounts in id order to avoid deadlock. Everything lives on the heap on purpose: this is the
 * memory pressure the experiment puts the JVM under.
 */
@Component
public class BankStore {

    private final ConcurrentHashMap<Long, Account> accounts = new ConcurrentHashMap<>();
    private final AtomicLong accountSeq = new AtomicLong();
    private final AtomicLong txSeq = new AtomicLong();

    public long open(long openingCents) {
        long id = accountSeq.incrementAndGet();
        accounts.put(id, new Account(id, openingCents));
        return id;
    }

    public Account get(long id) {
        Account a = accounts.get(id);
        if (a == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "account " + id + " not found");
        }
        return a;
    }

    public Transaction deposit(long id, long cents, String description) {
        requirePositive(cents);
        Account a = get(id);
        synchronized (a) {
            long balance = a.balanceCents() + cents;
            Transaction t = new Transaction(txSeq.incrementAndGet(), "DEPOSIT", cents, balance, Instant.now(), description);
            a.record(balance, t);
            return t;
        }
    }

    public Transaction withdraw(long id, long cents, String description) {
        requirePositive(cents);
        Account a = get(id);
        synchronized (a) {
            if (a.balanceCents() < cents) {
                throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "insufficient funds");
            }
            long balance = a.balanceCents() - cents;
            Transaction t = new Transaction(txSeq.incrementAndGet(), "WITHDRAW", -cents, balance, Instant.now(), description);
            a.record(balance, t);
            return t;
        }
    }

    public Transaction transfer(long fromId, long toId, long cents) {
        requirePositive(cents);
        if (fromId == toId) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "cannot transfer to the same account");
        }
        Account from = get(fromId);
        Account to = get(toId);
        // Lock in a stable order (by id) so concurrent opposite transfers can't deadlock.
        Account first = fromId < toId ? from : to;
        Account second = fromId < toId ? to : from;
        synchronized (first) {
            synchronized (second) {
                if (from.balanceCents() < cents) {
                    throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "insufficient funds");
                }
                Instant now = Instant.now();
                long fromBalance = from.balanceCents() - cents;
                long toBalance = to.balanceCents() + cents;
                Transaction out = new Transaction(txSeq.incrementAndGet(), "TRANSFER_OUT", -cents, fromBalance, now, "to " + toId);
                Transaction in = new Transaction(txSeq.incrementAndGet(), "TRANSFER_IN", cents, toBalance, now, "from " + fromId);
                from.record(fromBalance, out);
                to.record(toBalance, in);
                return out;
            }
        }
    }

    public List<Transaction> statement(long id, int limit) {
        return get(id).recent(limit);
    }

    public long count() {
        return accounts.size();
    }

    private static void requirePositive(long cents) {
        if (cents <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "amount must be positive");
        }
    }
}
