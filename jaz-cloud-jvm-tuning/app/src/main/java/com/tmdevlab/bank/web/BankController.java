package com.tmdevlab.bank.web;

import com.tmdevlab.bank.model.Transaction;
import com.tmdevlab.bank.store.BankStore;
import com.tmdevlab.bank.web.dto.BankDtos.AccountResponse;
import com.tmdevlab.bank.web.dto.BankDtos.AmountRequest;
import com.tmdevlab.bank.web.dto.BankDtos.IdResponse;
import com.tmdevlab.bank.web.dto.BankDtos.OpenRequest;
import com.tmdevlab.bank.web.dto.BankDtos.StatsResponse;
import com.tmdevlab.bank.web.dto.BankDtos.TransferRequest;
import com.tmdevlab.bank.web.dto.BankDtos.TxResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/** REST surface of the bank. Reads (balance, statement) and writes (deposit/withdraw/transfer). */
@RestController
@RequestMapping("/api")
public class BankController {

    private final BankStore store;
    private final long ioDelayMs;

    public BankController(BankStore store, @Value("${bank.io-delay-ms:5}") long ioDelayMs) {
        this.store = store;
        this.ioDelayMs = ioDelayMs;
    }

    @PostMapping("/accounts")
    public IdResponse open(@RequestBody OpenRequest req) {
        return new IdResponse(store.open(req.openingCents()));
    }

    @GetMapping("/accounts/{id}")
    public AccountResponse account(@PathVariable long id) {
        var a = store.get(id);
        return new AccountResponse(a.id(), a.balanceCents(), a.ledgerSize());
    }

    @PostMapping("/accounts/{id}/deposit")
    public TxResponse deposit(@PathVariable long id, @RequestBody AmountRequest req) {
        return toResponse(store.deposit(id, req.amountCents(), req.description()));
    }

    @PostMapping("/accounts/{id}/withdraw")
    public TxResponse withdraw(@PathVariable long id, @RequestBody AmountRequest req) {
        return toResponse(store.withdraw(id, req.amountCents(), req.description()));
    }

    @PostMapping("/transfers")
    public TxResponse transfer(@RequestBody TransferRequest req) {
        return toResponse(store.transfer(req.fromId(), req.toId(), req.amountCents()));
    }

    @GetMapping("/accounts/{id}/statement")
    public List<TxResponse> statement(@PathVariable long id, @RequestParam(defaultValue = "50") int limit) {
        return store.statement(id, limit).stream().map(this::toResponse).toList();
    }

    @GetMapping("/stats")
    public StatsResponse stats() {
        return new StatsResponse(store.count(), ioDelayMs);
    }

    private TxResponse toResponse(Transaction t) {
        return new TxResponse(t.id(), t.type(), t.amountCents(), t.balanceAfterCents(), t.at().toString(), t.description());
    }
}
